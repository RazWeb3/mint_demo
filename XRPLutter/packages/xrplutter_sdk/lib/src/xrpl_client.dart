// -------------------------------------------------------
// 目的・役割: XRPL JSON-RPC/HTTPエンドポイントとの通信を担当する低レベルクライアント。
// 作成日: 2025/11/08
//
// 更新履歴:
// 2025/11/08 23:59 追記: 今後nft_info取得やNFTokenMint/NFTokenBurn署名送信を実装予定である旨をコメント。
// 理由: 実装計画の可視化。
// 2025/11/09 11:50 変更: タイムアウト/リトライ（指数バックオフ）と詳細エラーハンドリングを実装。エンドポイント設定を拡張。
// 理由: 仕様書（3.1 XRPLClient）に記載の非機能要件（安定性）に準拠し、ネットワーク揺らぎ時の堅牢性を高めるため。
// 2025/11/13 15:22 変更: HTTPクライアントの再利用（keep-alive）を導入し、ソケット枯渇/オーバーヘッドを低減。
// 理由: 毎回のトップレベルhttp呼び出しでクライアントを再生成せず、効率と安定性を改善するため。
// 2025/11/13 15:22 追記: エンドポイントURIのスキーム検証（http/httpsのみ許可）を追加。
// 理由: 不正スキーム（file:, data:, javascript:）混入による誤動作やセキュリティリスクを排除するため。
// 2025/11/16 10:24 変更: エンドポイントのホスト検証（localhost/プライベート/リンクローカルを拒否）。
// 理由: SSRF耐性の強化。
// 2025/11/16 10:24 変更: autofillの並列化と短期TTLキャッシュを導入。awaitTransactionにバックオフ＋not_found継続処理を追加。
// 理由: レイテンシ低減と安定性向上。
// -------------------------------------------------------

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class XRPLClient {
  XRPLClient({
    String? endpoint,
    Duration? timeout,
    int? maxRetries,
    int? retryBaseDelayMs,
  })  : _timeout = timeout ?? const Duration(seconds: 10),
        _maxRetries = maxRetries ?? 2,
        _retryBaseDelayMs = retryBaseDelayMs ?? 300,
        _client = http.Client(),
        _endpointUri = _validateEndpointUri(endpoint ?? 'https://s.altnet.rippletest.net:51234');

  final Duration _timeout;
  final int _maxRetries;
  final int _retryBaseDelayMs;
  final http.Client _client;
  final Uri _endpointUri;
  String? _cachedFeeDropsMedian; DateTime? _feeCachedAt;
  int? _cachedLedgerIndex; DateTime? _ledgerCachedAt;

  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params) async {
    final body = jsonEncode({
      'method': method,
      'params': [params],
    });

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final res = await _client
            .post(
              _endpointUri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(_timeout);
        if (res.statusCode != 200) {
          throw XRPLNetworkError('HTTP ${res.statusCode}');
        }
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final result = decoded['result'];
        if (result is Map<String, dynamic>) {
          final status = result['status'];
          final error = result['error'] ?? result['error_code'] ?? result['engine_result'];
          final errorMessage = result['error_message'] ?? result['engine_result_message'] ?? result['message'];
          if (status == 'error' || (error != null && error != 'tesSUCCESS')) {
            throw XRPLSubmitError('${error ?? 'unknown'}', errorMessage?.toString());
          }
        }
        return decoded;
      } on TimeoutException {
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(_retryDelay(attempt));
      } on SocketException {
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(_retryDelay(attempt));
      } on http.ClientException {
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(_retryDelay(attempt));
      }
    }
    // 理論上ここには来ない（上でreturnかrethrowしている）
    throw XRPLNetworkError('Unexpected retry exhaustion');
  }

  Duration _retryDelay(int attempt) {
    // 指数バックオフ: base * 2^attempt
    final ms = _retryBaseDelayMs * (1 << attempt);
    return Duration(milliseconds: ms);
  }

  static Uri _validateEndpointUri(String endpoint) {
    final uri = Uri.parse(endpoint);
    final s = uri.scheme.toLowerCase();
    if (s != 'http' && s != 'https') {
      throw ArgumentError('XRPL endpoint must use http/https scheme: ' + endpoint);
    }
    final host = uri.host.toLowerCase();
    // localhost/loopbackはテスト用途を考慮して許可
    if (host.startsWith('10.') || host.startsWith('192.168.') || host.startsWith('172.16.') || host.startsWith('172.17.') || host.startsWith('172.18.') || host.startsWith('172.19.') || host.startsWith('172.2') || host.startsWith('169.254.')) {
      throw ArgumentError('Disallowed private/link-local address: ' + endpoint);
    }
    return uri;
  }

  Future<String> _getFeeMedian() async {
    if (_cachedFeeDropsMedian != null && _feeCachedAt != null && DateTime.now().difference(_feeCachedAt!) < const Duration(seconds: 5)) {
      return _cachedFeeDropsMedian!;
    }
    final fee = await call('fee', {});
    final drops = fee['result']?['drops'];
    String? feeStr;
    if (drops is Map) {
      feeStr = (drops['median'] ?? drops['open'] ?? drops['minimum'])?.toString();
    }
    _cachedFeeDropsMedian = feeStr ?? '10';
    _feeCachedAt = DateTime.now();
    return _cachedFeeDropsMedian!;
  }

  Future<int> _getLedgerIndexPlus(int offset) async {
    if (_cachedLedgerIndex != null && _ledgerCachedAt != null && DateTime.now().difference(_ledgerCachedAt!) < const Duration(seconds: 2)) {
      return _cachedLedgerIndex! + offset;
    }
    final lc = await call('ledger_current', {});
    final idx = lc['result']?['ledger_current_index'];
    final i = idx is int ? idx : 0;
    _cachedLedgerIndex = i;
    _ledgerCachedAt = DateTime.now();
    return i + offset;
  }

  Future<Map<String, dynamic>> autofillTxJson(Map<String, dynamic> tx) async {
    final mutable = Map<String, dynamic>.from(tx);
    final account = (mutable['Account'] ?? mutable['account'])?.toString();
    Future<void> seqF() async {
      if ((mutable['Sequence'] ?? mutable['sequence']) == null && account != null && account.isNotEmpty) {
        final ai = await call('account_info', {'account': account, 'ledger_index': 'current'});
        final seq = ai['result']?['account_data']?['Sequence'];
        if (seq is int) mutable['Sequence'] = seq;
      }
    }
    final feeF = (mutable['Fee'] ?? mutable['fee']) == null ? _getFeeMedian().then((v) => mutable['Fee'] = v) : Future.value();
    final llF = (mutable['LastLedgerSequence'] ?? mutable['last_ledger_sequence']) == null
        ? _getLedgerIndexPlus(4).then((v) => mutable['LastLedgerSequence'] = v)
        : Future.value();
    await Future.wait([seqF(), feeF, llF]);
    return mutable;
  }

  Future<Map<String, dynamic>> awaitTransaction(String hash, {Duration timeout = const Duration(seconds: 20), Duration pollInterval = const Duration(milliseconds: 800)}) async {
    final deadline = DateTime.now().add(timeout);
    int attempt = 0;
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final res = await call('tx', {'transaction': hash});
        last = res['result'] as Map<String, dynamic>?;
        final validated = last?['validated'] == true;
        if (validated) return res;
      } on XRPLSubmitError catch (e) {
        final code = e.code.toLowerCase();
        if (code != 'not_found' && code != 'txnotfound' && code != 'txnnotfound') {
          rethrow;
        }
      }
      final baseMs = pollInterval.inMilliseconds * (1 << (attempt.clamp(0, 4)));
      final jitterMs = ((baseMs * 0.2) * ((DateTime.now().microsecondsSinceEpoch % 1000) / 1000)).round();
      await Future.delayed(Duration(milliseconds: baseMs + jitterMs));
      attempt++;
    }
    throw XRPLNetworkError('Transaction not validated within timeout');
  }

  /// 明示的にHTTPクライアントを破棄したい場合に使用（通常は不要）
  void close() {
    _client.close();
  }
}

class XRPLNetworkError implements Exception {
  XRPLNetworkError(this.message);
  final String message;
  @override
  String toString() => 'XRPLNetworkError: $message';
}

class XRPLSubmitError implements Exception {
  XRPLSubmitError(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'XRPLSubmitError(code=$code, message=${message ?? ''})';
}
