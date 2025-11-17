// -------------------------------------------------------
// 目的・役割: 外部ウォレットとの接続・切断・署名を仲介するコンポーネント。
// 作成日: 2025/11/08
//
// 更新履歴:
// 2025/11/08 23:59 追記: 非カストディアル運用における受取側の毎回署名が必要である旨を内部コメントに明記。
// 理由: 受取UX設計の前提を統一するため。
// 2025/11/09 00:12 追記: 署名要求APIのスタブを追加（signAndSubmit）。
// 理由: 非カストディアル運用で外部署名フローをSDKから呼び出すための入口を用意。
// 2025/11/09 12:30 変更: マルチプロバイダ対応のアダプタ構造（Xaman/Crossmark/GemWallet/WalletConnect想定）を導入。
// 理由: 普及率の高いウォレットの順次対応を柔軟化し、SDKの価値を高めるため（内部拡張）。
// 2025/11/09 12:58 変更: WalletConnectorConfig/XRPLClientの受け入れを追加。Xaman連携のプロキシ方式に対応する準備（HTTP呼び出し）を実装（スタブ）。
// 理由: XUMMキーをクライアントに置かない設計のため、バックエンドプロキシを前提とした連携を容易にする。
// 2025/11/09 13:26 追加: 進捗イベントStream（SignProgressEvent）とキャンセル制御（CancelToken）を導入。Xamanアダプタでイベントを発火。
// 理由: 進捗ステート/キャンセル/タイムアウトのイベントAPIをWalletConnectorレベルで提供し、UX向上と運用計測に備える。
// 2025/11/09 14:02 変更: Crossmark/GemWalletアダプタの骨子を拡張し、イベント発火（created/opened/signed/submitted）とキャンセル対応のスタブを追加。
// 理由: Web拡張連携に向けたUI/UX検証用の土台を整備するため（JS interop実装前のスタブ）。
// 2025/11/09 14:40 追記: Web拡張（Crossmark/GemWallet）の存在検出（条件付きimport）を追加。非Webではスタブを読み込む。
// 理由: Flutter WebでJS interop実装前に拡張の存在可否をUXに反映するため。
// 2025/11/09 14:58 変更: Crossmark/GemWalletアダプタが拡張検出時にInterop呼び出しを試行し、戻り値（txHash/tx_blob/rejected）に応じてイベント発火する仮実装を追加。
// 理由: 最小のJS interop骨子を導入してUI/UXの挙動を早期検証するため。
// 2025/11/09 15:36 変更: Interop結果のエラー（error）を正しく SignProgressState.error として通知、payloadId を可能ならイベントに反映、アドレス整合チェックを追加。
// 理由: エラーとユーザー拒否を区別し、拡張が返す補助情報を活用して診断性を高めるため。
// 2025/11/09 15:50 変更: 設定フラグ（webSubmitByExtension/verifyAddressBeforeSign）を導入し、Web拡張の送信方式制御と事前アドレス検証を任意化。
// 理由: 実拡張の挙動差に対応しつつ、ユースケースに応じて検証強度を調整できるようにするため。
// 2025/11/09 16:05 追記: openedイベントに拡張の現在アドレス/ネットワーク（取得可能な場合）をメッセージに反映。
// 理由: 実機検証でアドレス/ネットワークの視認性を高め、診断とUX確認を容易にするため。
// 2025/11/09 16:56 変更: Web拡張Interop呼び出しにタイムアウト処理（30秒）を追加し、SignProgressState.timeout を発火。
// 理由: 実機環境で応答が返らないケースのUIフリーズを防ぎ、明確にユーザーへ通知するため。
// 2025/11/09 17:30 変更: connect()でWeb拡張からアドレス取得できる場合はセッションへ反映。
// 理由: 実機検証でアドレス整合チェック（verifyAddressBeforeSign）の誤検知を避け、より現実的な接続状態を再現するため。
// 2025/11/09 17:40 追記: Interopレスポンスの観測キー（トップ/ネスト）をイベントメッセージに含めるデバッグ補助を追加。
// 理由: 実機レスポンスの形式差を把握しやすくし、アダプタ具体化のための情報採取を容易にするため。
// 2025/11/10 11:05 変更: Web拡張Interopのタイムアウトを固定30秒から WalletConnectorConfig.signingTimeout に切り替え。
// 理由: 設定値に基づく柔軟な制御を可能にし、実機での操作時間に合わせて不必要な早期タイムアウトを防ぐため。
// 2025/11/10 14:20 追加: WalletConnect v2 の最小骨子（ペアリングURI生成・イベント発火のスタブ）を実装。
// 理由: セッション・ペアリング・署名リクエスト・イベント通知の流れをUI/UX確認用に可視化するため（実ハンドシェイクは今後のプロキシ連携で拡充）。
// 2025/11/10 18:45 変更: WalletConnectAdapter にプロキシ連携の骨子を追加（session/create と session/status ポーリング、tx_hash/tx_blobハンドリング、失敗時はwc: URI生成スタブへフォールバック）。
// 理由: BYOSプロキシ連携のUX確認と段階的な実装の足がかりを整備するため。
// 2025/11/10 19:20 変更: プロキシURL結合処理を Uri.resolve に置換し、末尾スラッシュ有無に依存しない安全なURL組み立てに改善。
// 理由: ベースURLの記述揺れ（末尾スラッシュ有無）による連結不整合を防ぎ、設定の扱いやすさを高めるため。
// 2025/11/13 13:30 変更: Xaman作成イベントのdeepLink/qrUrl取得を強化（next.pushed と refs.qr_png をフォールバックに追加）。
// 理由: 環境によって応答キーが異なるケースに対応し、QR未表示の問題を解消するため。
// 2025/11/13 13:47 変更: deepLinkからpayloadIdを推定して補完。payloadIdが不明な場合のステータスポーリングを中止し、エラー通知。
// 理由: 一部環境でpayloadIdキーが返らないため、リンクからUUIDを抽出して安定動作させる。
// 2025/11/13 14:20 変更: ステータス応答の観測キーをイベントメッセージへ併記し、診断性を向上。
// 理由: opened/signed/rejected時の応答差異をUIログで把握しやすくするため。
// 2025/11/13 15:20 変更: プロキシ呼び出しの認可ヘッダから暗黙の 'dev-secret' フォールバックを廃止し、JWT未設定時は即時エラー化。
// 理由: 認可迂回のリスクを排除し本番相当のセキュア設定を強制するため。
// 2025/11/13 15:20 追記: プロキシベースURLのスキーム検証（http/httpsのみ許可）を追加し、SSRFの足がかりとなる不正スキームを拒否。
// 理由: data:, file:, javascript: 等の不正スキーム混入による誤リクエストを防止するため。
// 2025/11/13 15:20 追記: HTTPリクエストにタイムアウト（10秒）を付与し、ハングによるUX悪化とDoS連鎖を防止。
// 理由: ネットワーク異常時の待機無制限を避けるため。
// 2025/11/16 10:22 変更: deepLink/qrUrlのスキーム検証とサニタイズを追加。
// 理由: 不正スキーム混入によるXSS/不正リダイレクトの回避。
// 2025/11/16 10:22 変更: WalletConnectスタブの乱数生成をRandom.secure()へ変更。
// 理由: 誤用時の推測耐性を高める安全策。
// 2025/11/16 12:30 変更: XamanフローにSignInフォールバックを追加。payload/detailsからresponse.accountを抽出しセッション/戻り値へ反映、signedメッセージへaccount=を出力。
// 理由: 送信を伴わない署名ケースでアドレス未確定となる問題の解消と診断性向上。
// 2025/11/16 12:31 変更: ステータスからのアカウント抽出を強化（status.account→response.account→meta.accountの順で走査）し、検出時はsession.addressへ反映。
// 理由: Xaman/BYOSの応答差によりaccountがトップにない環境で未確定化する問題を解消。
// 2025/11/16 12:32 変更: ペイロード作成失敗時にSignProgressState.errorを必ず発火（HTTP非200/例外）。
// 理由: UIが待機継続してしまう問題の解消。
// 2025/11/16 12:33 変更: WalletSession.addressの可変化に追随し、検出したaccountをセッションへ更新。
// 理由: 承認後に確定したアドレスを後続APIへ反映するため。
// 2025/11/16 12:34 変更: signedメッセージにaccount=を付与し、既存のkeys=ログを維持。
// 理由: 診断ログの充実と可観測性向上。
// 2025/11/16 13:16 変更: HTTPタイムアウトを構成値（httpTimeout）へ統一し、観測キー（keys=）の計算を設定（logObservedKeys）で制御。
// 理由: 高頻度ポーリング時の効率化と運用制御性の向上。
// -------------------------------------------------------

import 'models.dart';
import 'wallet_config.dart';
import 'xrpl_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
// Web拡張（Crossmark/GemWallet）の存在検出（Webのみ有効）
import 'web/wallet_web_stub.dart' if (dart.library.html) 'web/wallet_web_interop.dart';

class WalletConnector {
  WalletSession? _session;
  WalletAdapter? _adapter;
  final WalletConnectorConfig _config;
  final XRPLClient _client;
  final StreamController<SignProgressEvent> _progressController = StreamController.broadcast();
  CancelToken? _cancelToken;

  WalletConnector({WalletConnectorConfig? config, XRPLClient? client})
      : _config = config ?? const WalletConnectorConfig(),
        _client = client ?? XRPLClient();

  /// 進捗イベントの購読用Stream
  Stream<SignProgressEvent> get progressStream => _progressController.stream;

  /// 進行中の署名フローをキャンセル
  void cancelSigning() {
    _cancelToken?.cancel();
    _progressController.add(SignProgressEvent(state: SignProgressState.canceled, message: 'Canceled by client'));
  }

  Future<WalletSession> connect({required WalletProvider provider}) async {
    _adapter = _resolveAdapter(provider);
    String address = 'rEXAMPLEADDRESS';
    try {
      // Web拡張が利用可能なら現在アドレスを取得してセッションへ反映（Crossmark/GemWallet）
      if (provider.name.toLowerCase() == 'crossmark') {
        final addr = await BrowserWalletInterop.instance.getAddressCrossmark();
        if (addr != null && addr.isNotEmpty) address = addr;
      } else if (provider.name.toLowerCase() == 'gemwallet') {
        final addr = await BrowserWalletInterop.instance.getAddressGemWallet();
        if (addr != null && addr.isNotEmpty) address = addr;
      }
    } catch (_) {
      // アドレス取得失敗時はフォールバック
    }
    _session = WalletSession(address: address);
    return _session!;
  }

  Future<void> disconnect() async {
    _session = null;
  }

  Future<AccountInfo> getAccountInfo() async {
    if (_session == null) {
      throw StateError('Wallet not connected');
    }
    return AccountInfo(address: _session!.address, sequence: 1);
  }

  /// 署名要求＋送信のスタブ（今後、Xumm/WalletConnect等と連携）
  /// txJson: 署名前のトランザクションJSON（NFTokenMint/NFTokenCreateOffer/NFTokenBurn等）
  /// 戻り値: 送信結果（ダミー）
  Future<Map<String, dynamic>> signAndSubmit({required Map<String, dynamic> txJson}) async {
    if (_session == null) {
      throw StateError('Wallet not connected');
    }
    if (_cancelToken != null && !_cancelToken!.canceled) {
      throw StateError('SigningInProgress');
    }
    if (_adapter != null) {
      _cancelToken = CancelToken();
      return _adapter!.signAndSubmit(
        txJson: txJson,
        session: _session!,
        config: _config,
        client: _client,
        onEvent: (e) => _progressController.add(e),
        cancelToken: _cancelToken!,
      );
    }
    // 既定のフォールバック（ダミー）
    return {
      'result': {
        'tx_json': txJson,
        'hash': 'dummyHash',
      }
    };
  }

  WalletAdapter? _resolveAdapter(WalletProvider provider) {
    switch (provider.name.toLowerCase()) {
      case 'xaman': // 旧xumm
      case 'xumm':
        return XamanAdapter();
      case 'crossmark':
        return CrossmarkAdapter();
      case 'gemwallet':
        return GemWalletAdapter();
      case 'walletconnect':
      case 'walletconnect_v2':
        return WalletConnectAdapter();
      default:
        return null; // 未対応はフォールバックダミーに委ねる
    }
  }
}

/// アダプタIF: 署名＋送信を各ウォレットに委譲
abstract class WalletAdapter {
  Future<Map<String, dynamic>> signAndSubmit({
    required Map<String, dynamic> txJson,
    required WalletSession session,
    required WalletConnectorConfig config,
    required XRPLClient client,
    required void Function(SignProgressEvent event) onEvent,
    required CancelToken cancelToken,
  });
}

/// Xaman（旧XUMM）用アダプタ（現時点はスタブ）。
class XamanAdapter implements WalletAdapter {
  @override
  Future<Map<String, dynamic>> signAndSubmit({
    required Map<String, dynamic> txJson,
    required WalletSession session,
    required WalletConnectorConfig config,
    required XRPLClient client,
    required void Function(SignProgressEvent event) onEvent,
    required CancelToken cancelToken,
  }) async {
    // 署名UX（最適案）:
    // 1) バックエンドプロキシへpayload作成要求（tx_json渡し）
    // 2) 戻り値のdeepLink/qrUrlでユーザーに署名を促す（UIはアプリ側）
    // 3) プロキシ経由で署名結果をポーリング取得（accepted/rejected/timeout）
    // 4) サイン済みならXRPL submit（プロキシがsubmit済みならtxHashをそのまま返却）

    if (config.xamanProxyBaseUrl == null) {
      // プロキシ未設定の場合はダミーにフォールバック
      return {
        'result': {
          'tx_json': txJson,
          'hash': 'dummyHash-xaman',
        }
      };
    }

    final base = config.xamanProxyBaseUrl!;
    final _scheme = base.scheme.toLowerCase();
    if (_scheme != 'http' && _scheme != 'https') {
      throw ArgumentError('Invalid proxy base URL scheme: ${base.scheme}');
    }
    if (config.disallowPrivateProxyHosts) {
      final host = base.host.toLowerCase();
      bool _isPrivate = host == 'localhost' || host == '127.0.0.1' || host.startsWith('10.') || host.startsWith('192.168.');
      if (!_isPrivate && host.startsWith('172.')) {
        final parts = host.split('.');
        if (parts.length > 1) {
          final s = int.tryParse(parts[1]) ?? -1;
          if (s >= 16 && s <= 31) {
            _isPrivate = true;
          }
        }
      }
      if (_isPrivate) {
        throw ArgumentError('Disallowed private/link-local proxy host: ' + base.toString());
      }
    }
    final _jwt = (config.jwtBearerToken ?? '').trim();
    if (_jwt.isEmpty) {
      throw StateError('Missing JWT bearer token for Xaman proxy');
    }
    Map<String, dynamic> createJson;
    try {
      final createRes = await http
          .post(
        base.resolve('payload/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + _jwt,
        },
        body: jsonEncode({'tx_json': txJson}),
      )
          .timeout(config.httpTimeout);
      if (createRes.statusCode != 200) {
        onEvent(SignProgressEvent(
          state: SignProgressState.error,
          message: 'Create failed: HTTP ' + createRes.statusCode.toString(),
        ));
        throw StateError('Xaman proxy create failed: HTTP ${createRes.statusCode}');
      }
      createJson = jsonDecode(createRes.body) as Map<String, dynamic>;
    } catch (e) {
      onEvent(SignProgressEvent(
        state: SignProgressState.error,
        message: 'Create request failed: ' + e.toString(),
      ));
      rethrow;
    }
    String? payloadId = createJson['payloadId']?.toString() ?? createJson['uuid']?.toString();
    String? deepLink = createJson['deepLink']?.toString();
    final dynamic next = createJson['next'];
    if ((deepLink == null || deepLink.isEmpty) && next is Map) {
      deepLink = (next['always']?.toString()) ?? (next['pushed']?.toString());
    }
    String? qrUrl = createJson['qrUrl']?.toString();
    final dynamic refs = createJson['refs'];
    if ((qrUrl == null || qrUrl.isEmpty) && refs is Map) {
      qrUrl = refs['qr_png']?.toString();
    }
    if ((deepLink == null || deepLink.isEmpty) && (payloadId != null && payloadId.isNotEmpty)) {
      deepLink = 'https://xumm.app/sign/' + payloadId;
    }
    if ((qrUrl == null || qrUrl.isEmpty) && (payloadId != null && payloadId.isNotEmpty)) {
      qrUrl = 'https://xumm.app/sign/' + payloadId + '_q.png';
    }
    if ((payloadId == null || payloadId.isEmpty) && (deepLink != null && deepLink.isNotEmpty)) {
      try {
        final uri = Uri.parse(deepLink);
        final q = uri.queryParameters['payload'];
        if (q != null && q.isNotEmpty) {
          payloadId = q;
        } else {
          final segs = uri.pathSegments;
          if (segs.isNotEmpty) {
            final last = segs.last;
            payloadId = last.split('?').first.split('_').first;
          }
        }
      } catch (_) {}
    }

    final observedCreateKeys = <String>[];
    if (config.logObservedKeys) {
      try {
        observedCreateKeys.addAll(createJson.keys.map((e) => e.toString()));
      } catch (_) {}
    }
    onEvent(SignProgressEvent(
      state: SignProgressState.created,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(deepLink),
      qrUrl: _sanitizeHttpsOnly(qrUrl),
      message: observedCreateKeys.isEmpty ? 'Payload created' : ('Payload created | keys=' + observedCreateKeys.join(',')),
    ));

    // ユーザー操作用のリンクはSDKから返却してもよいが、SDKの戻り値構造は現仕様ではhash中心のため
    // 現段階は内部でポーリングのみ実施し、UI提示はアプリ側が createJson を別途参照する前提とする。

    // payloadIdが確定していない場合はポーリングしても意味がないため中止
    if (payloadId == null || payloadId.isEmpty) {
      onEvent(SignProgressEvent(
        state: SignProgressState.error,
        message: 'Missing payloadId',
      ));
      throw StateError('PayloadIdMissing');
    }
    final deadline = DateTime.now().add(config.signingTimeout);
    Map<String, dynamic>? statusJson;
    bool _openedEmitted = false;
    int _attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (cancelToken.canceled) {
        throw StateError('SignCanceled');
      }
          final statusRes = await http
              .get(
            base.resolve('payload/status/$payloadId'),
            headers: {
              'Authorization': 'Bearer ' + _jwt,
            },
          )
              .timeout(config.httpTimeout);
      if (statusRes.statusCode != 200) {
        final baseMs = config.pollingInterval.inMilliseconds * (1 << (_attempt.clamp(0, 4)));
        final jitterMs = ((baseMs * 0.2) * ((DateTime.now().microsecondsSinceEpoch % 1000) / 1000)).round();
        await Future.delayed(Duration(milliseconds: baseMs + jitterMs));
        _attempt++;
        continue;
      }
      statusJson = jsonDecode(statusRes.body) as Map<String, dynamic>;
      final signed = statusJson['signed'] == true || (statusJson['response']?['signed'] == true);
      final rejected = statusJson['rejected'] == true || (statusJson['response']?['rejected'] == true);
      final opened = statusJson['opened'] == true || (statusJson['response']?['opened'] == true);
      final observedStatusKeys = <String>[];
      if (config.logObservedKeys) {
        try {
          observedStatusKeys.addAll(statusJson.keys.map((e) => e.toString()));
          final r2 = statusJson['response'];
          if (r2 is Map) observedStatusKeys.addAll(r2.keys.map((e) => 'response.' + e.toString()));
          final m2 = statusJson['meta'];
          if (m2 is Map) observedStatusKeys.addAll(m2.keys.map((e) => 'meta.' + e.toString()));
        } catch (_) {}
      }
      if (opened && !_openedEmitted) {
        onEvent(SignProgressEvent(
          state: SignProgressState.opened,
          payloadId: payloadId,
          deepLink: _sanitizeUrl(deepLink),
          qrUrl: _sanitizeHttpsOnly(qrUrl),
          message: observedStatusKeys.isEmpty ? 'Payload opened by user' : ('Payload opened by user | keys=' + observedStatusKeys.join(',')),
        ));
        _openedEmitted = true;
      }
      if (signed) break;
      if (rejected) {
        onEvent(SignProgressEvent(
          state: SignProgressState.rejected,
          payloadId: payloadId,
          message: observedStatusKeys.isEmpty ? 'User rejected signing' : ('User rejected signing | keys=' + observedStatusKeys.join(',')),
        ));
        throw StateError('SignRejected by user');
      }
      final baseMs = config.pollingInterval.inMilliseconds * (1 << (_attempt.clamp(0, 3)));
      final jitterMs = ((baseMs * 0.2) * ((DateTime.now().microsecondsSinceEpoch % 1000) / 1000)).round();
      await Future.delayed(Duration(milliseconds: baseMs + jitterMs));
      _attempt++;
    }

    if (statusJson == null) {
      onEvent(SignProgressEvent(
        state: SignProgressState.timeout,
        payloadId: payloadId,
        message: 'Signing timed out',
      ));
      throw StateError('SignTimeout');
    }
    final txnType = txJson['TransactionType']?.toString();
    String? _account = statusJson['account']?.toString() ?? statusJson['response']?['account']?.toString() ?? statusJson['meta']?['account']?.toString();
    if (_account != null && _account.isNotEmpty) {
      session.address = _account;
    }
    final _observedKeys = <String>[];
    try {
      _observedKeys.addAll(statusJson.keys.map((e) => e.toString()));
      final r2 = statusJson['response'];
      if (r2 is Map) _observedKeys.addAll(r2.keys.map((e) => 'response.' + e.toString()));
      final m2 = statusJson['meta'];
      if (m2 is Map) _observedKeys.addAll(m2.keys.map((e) => 'meta.' + e.toString()));
    } catch (_) {}

    if (txnType == 'SignIn') {
      String? acct = _account;
      if (acct == null || acct.isEmpty) {
        try {
          final detailsRes = await http
              .get(
            base.resolve('payload/details/' + payloadId),
            headers: {
              'Authorization': 'Bearer ' + _jwt,
            },
          )
              .timeout(config.httpTimeout);
          if (detailsRes.statusCode == 200) {
            final detailsJson = jsonDecode(detailsRes.body) as Map<String, dynamic>;
            acct = detailsJson['response']?['account']?.toString() ?? detailsJson['account']?.toString() ?? detailsJson['meta']?['account']?.toString();
          }
        } catch (_) {}
      }
      if (acct != null && acct.isNotEmpty) {
        session.address = acct;
        onEvent(SignProgressEvent(
          state: SignProgressState.signed,
          payloadId: payloadId,
          message: 'Signed' + ' | account=' + acct + (_observedKeys.isNotEmpty ? (' | keys=' + _observedKeys.join(',')) : ''),
        ));
        return {
          'result': {
            'account': acct,
            'deepLink': _sanitizeUrl(deepLink),
          }
        };
      }
      onEvent(SignProgressEvent(
        state: SignProgressState.error,
        payloadId: payloadId,
        message: 'Account not available for SignIn' + (_observedKeys.isNotEmpty ? (' | keys=' + _observedKeys.join(',')) : ''),
      ));
      throw StateError('SignInAccountNotAvailable');
    }

    // 提供側がsubmit済みならtxHashが入っている想定。未送信ならSDKからsubmit。
    final txHash = statusJson['txHash']?.toString() ?? statusJson['response']?['txid']?.toString();
    if (txHash != null && txHash.isNotEmpty) {
      onEvent(SignProgressEvent(
        state: SignProgressState.signed,
        payloadId: payloadId,
        message: 'Signed' + (_account != null && _account.isNotEmpty ? (' | account=' + _account) : '') + (_observedKeys.isNotEmpty ? (' | keys=' + _observedKeys.join(',')) : ''),
      ));
      onEvent(SignProgressEvent(
        state: SignProgressState.submitted,
        payloadId: payloadId,
        txHash: txHash,
        message: 'Submitted by proxy',
      ));
      return {
        'result': {
          'tx_json': txJson,
          'hash': txHash,
          'deepLink': _sanitizeUrl(deepLink),
        }
      };
    }

    // 未送信の場合は、プロキシから署名済みtx_blobを受領してSDKからsubmit（API設計はプロキシ側仕様に依存）
    final blob = statusJson['tx_blob']?.toString() ?? statusJson['response']?['tx_blob']?.toString();
    if (blob == null || blob.isEmpty) {
      throw StateError('Signed blob not available');
    }
    // XRPL submit（blob）: client.call('submit', {'tx_blob': blob}) を利用
    onEvent(SignProgressEvent(
      state: SignProgressState.signed,
      payloadId: payloadId,
      message: 'Signed, submitting via client' + (_account != null && _account.isNotEmpty ? (' | account=' + _account) : '') + (_observedKeys.isNotEmpty ? (' | keys=' + _observedKeys.join(',')) : ''),
    ));
    final submitRes = await client.call('submit', {'tx_blob': blob});
    final hash = submitRes['result']?['tx_json']?['hash']?.toString() ?? submitRes['result']?['txid']?.toString() ?? 'unknown';
    onEvent(SignProgressEvent(
      state: SignProgressState.submitted,
      payloadId: payloadId,
      txHash: hash,
      message: 'Submitted via client',
    ));
    return {
      'result': {
        'tx_json': txJson,
        'hash': hash,
        'deepLink': _sanitizeUrl(deepLink),
      }
    };
  }
}

/// Crossmark（Web拡張）用アダプタ（現時点はスタブ）。
class CrossmarkAdapter implements WalletAdapter {
  @override
  Future<Map<String, dynamic>> signAndSubmit({
    required Map<String, dynamic> txJson,
    required WalletSession session,
    required WalletConnectorConfig config,
    required XRPLClient client,
    required void Function(SignProgressEvent event) onEvent,
    required CancelToken cancelToken,
  }) async {
    final interop = BrowserWalletInterop.instance;
    final payloadId = 'CROSSMARK_SIM_' + DateTime.now().millisecondsSinceEpoch.toString();
    final deepLink = 'crossmark://sign';
    onEvent(SignProgressEvent(
      state: SignProgressState.created,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(deepLink),
      message: 'Crossmark signing requested' + (interop.isAvailableCrossmark ? ' (extension detected)' : ' (extension not detected - stub)'),
    ));

    // Web拡張が利用可能ならInterop経由で署名を試行、不可ならスタブにフォールバック
    if (interop.isAvailableCrossmark) {
      // 事前にウォレットアドレス取得が可能なら整合チェック
      if (config.verifyAddressBeforeSign) {
        try {
          final addr = await interop.getAddressCrossmark();
          if (addr != null && addr.isNotEmpty && addr != session.address) {
            onEvent(SignProgressEvent(
              state: SignProgressState.error,
              payloadId: payloadId,
              message: 'Wallet address mismatch: $addr != ${session.address}',
            ));
            throw StateError('WalletAddressMismatch');
          }
        } catch (_) {
          // アドレス取得失敗は非致命（続行）
        }
      }
      await Future.delayed(const Duration(milliseconds: 120));
      if (cancelToken.canceled) {
        throw StateError('SignCanceled');
      }
      String? openedAddr;
      String? openedNetwork;
      try {
        openedAddr = await interop.getAddressCrossmark();
      } catch (_) {}
      try {
        openedNetwork = await interop.getNetwork();
      } catch (_) {}
      final openedMsg = [
        'Crossmark UI opened (interop)',
        if (openedAddr != null && openedAddr.isNotEmpty) 'address=' + openedAddr,
        if (openedNetwork != null && openedNetwork.isNotEmpty) 'network=' + openedNetwork,
      ].join(' | ');
      onEvent(SignProgressEvent(
        state: SignProgressState.opened,
        payloadId: payloadId,
        deepLink: _sanitizeUrl(deepLink),
        message: openedMsg,
      ));
      try {
        // タイムアウト制御（config.signingTimeout を利用）
        final res = await interop
            .requestSignCrossmark(txJson, options: {'submit': config.webSubmitByExtension})
            .timeout(config.signingTimeout);
        if (cancelToken.canceled) {
          throw StateError('SignCanceled');
        }
        final payloadIdFromRes = (res['payloadId'] ?? res['uuid'])?.toString();
        final errorMsg = res['error']?.toString();
        final rejected = res['rejected'] == true;
        final txHash = (res['txHash'] ?? res['hash'] ?? res['txid'])?.toString();
        final blob = res['tx_blob']?.toString();
        // デバッグ補助: 観測キーを収集（トップレベル/代表的なネスト）
        final observedKeys = <String>{};
        if (config.logObservedKeys) {
          try {
            observedKeys.addAll(res.keys.map((e) => e.toString()));
            final r1 = res['result'];
            if (r1 is Map) {
              observedKeys.addAll(r1.keys.map((e) => 'result.' + e.toString()));
            }
            final r2 = res['response'];
            if (r2 is Map) {
              observedKeys.addAll(r2.keys.map((e) => 'response.' + e.toString()));
            }
          } catch (_) {}
        }
        final keysMsg = observedKeys.isNotEmpty ? (' keys=' + observedKeys.join(',')) : '';
        if (payloadIdFromRes != null && payloadIdFromRes.isNotEmpty) {
          // 参考情報としてpayloadIdをイベントに反映
          onEvent(SignProgressEvent(
            state: SignProgressState.created,
            payloadId: payloadIdFromRes,
            deepLink: _sanitizeUrl(deepLink),
            message: 'Payload info received (interop)'.toString(),
          ));
        }
        if (errorMsg != null && errorMsg.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.error,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'Interop error: ' + errorMsg,
          ));
          throw StateError('InteropError: $errorMsg');
        }
        if (rejected) {
          onEvent(SignProgressEvent(
            state: SignProgressState.rejected,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'User rejected (interop)',
          ));
          throw StateError('SignRejected by user');
        }
        if (txHash != null && txHash.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.signed,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'Signed (interop)' + keysMsg,
          ));
          onEvent(SignProgressEvent(
            state: SignProgressState.submitted,
            payloadId: payloadIdFromRes ?? payloadId,
            txHash: txHash,
            message: 'Submitted by extension',
          ));
          return {
            'result': {
              'tx_json': txJson,
              'hash': txHash,
              'deepLink': _sanitizeUrl(deepLink),
            }
          };
        }
        if (blob != null && blob.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.signed,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'Signed (interop) - submitting via client' + keysMsg,
          ));
          final submitRes = await client.call('submit', {'tx_blob': blob});
          final hash = submitRes['result']?['tx_json']?['hash']?.toString() ?? submitRes['result']?['txid']?.toString() ?? 'unknown';
          onEvent(SignProgressEvent(
            state: SignProgressState.submitted,
            payloadId: payloadIdFromRes ?? payloadId,
            txHash: hash,
            message: 'Submitted via client',
          ));
          return {
            'result': {
              'tx_json': txJson,
              'hash': hash,
              'deepLink': _sanitizeUrl(deepLink),
            }
          };
        }
        // 不明な結果はエラー扱い
        onEvent(SignProgressEvent(
          state: SignProgressState.error,
          payloadId: payloadIdFromRes ?? payloadId,
          message: 'Interop result not recognized' + keysMsg,
        ));
        throw StateError('InteropResultUnknown');
      } on TimeoutException catch (_) {
        onEvent(SignProgressEvent(
          state: SignProgressState.timeout,
          payloadId: payloadId,
          message: 'Interop timeout',
        ));
        throw StateError('SignTimeout');
      } catch (e) {
        onEvent(SignProgressEvent(
          state: SignProgressState.error,
          payloadId: payloadId,
          message: 'Interop error: ' + e.toString(),
        ));
        rethrow;
      }
    }

    // フォールバック（スタブ）
    await Future.delayed(const Duration(milliseconds: 150));
    if (cancelToken.canceled) {
      throw StateError('SignCanceled');
    }
    onEvent(SignProgressEvent(
      state: SignProgressState.opened,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(deepLink),
      message: 'Crossmark UI opened',
    ));

    await Future.delayed(const Duration(milliseconds: 200));
    if (cancelToken.canceled) {
      throw StateError('SignCanceled');
    }
    onEvent(SignProgressEvent(
      state: SignProgressState.signed,
      payloadId: payloadId,
      message: 'Crossmark signed',
    ));

    final hash = 'dummyHash-crossmark';
    onEvent(SignProgressEvent(
      state: SignProgressState.submitted,
      payloadId: payloadId,
      txHash: hash,
      message: 'Submitted (stub)',
    ));
    return {
      'result': {
        'tx_json': txJson,
        'hash': hash,
        'deepLink': _sanitizeUrl(deepLink),
      }
    };
  }
}

/// GemWallet（Web拡張）用アダプタ（現時点はスタブ）。
class GemWalletAdapter implements WalletAdapter {
  @override
  Future<Map<String, dynamic>> signAndSubmit({
    required Map<String, dynamic> txJson,
    required WalletSession session,
    required WalletConnectorConfig config,
    required XRPLClient client,
    required void Function(SignProgressEvent event) onEvent,
    required CancelToken cancelToken,
  }) async {
    final interop = BrowserWalletInterop.instance;
    final payloadId = 'GEMWALLET_SIM_' + DateTime.now().millisecondsSinceEpoch.toString();
    final deepLink = 'gemwallet://sign';
    onEvent(SignProgressEvent(
      state: SignProgressState.created,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(deepLink),
      message: 'GemWallet signing requested' + (interop.isAvailableGemWallet ? ' (extension detected)' : ' (extension not detected - stub)'),
    ));

    if (interop.isAvailableGemWallet) {
      // 事前にウォレットアドレス取得が可能なら整合チェック
      if (config.verifyAddressBeforeSign) {
        try {
          final addr = await interop.getAddressGemWallet();
          if (addr != null && addr.isNotEmpty && addr != session.address) {
            onEvent(SignProgressEvent(
              state: SignProgressState.error,
              payloadId: payloadId,
              message: 'Wallet address mismatch: $addr != ${session.address}',
            ));
            throw StateError('WalletAddressMismatch');
          }
        } catch (_) {
          // アドレス取得失敗は非致命（続行）
        }
      }
      await Future.delayed(const Duration(milliseconds: 120));
      if (cancelToken.canceled) {
        throw StateError('SignCanceled');
      }
      String? openedAddr;
      String? openedNetwork;
      try {
        openedAddr = await interop.getAddressGemWallet();
      } catch (_) {}
      try {
        openedNetwork = await interop.getNetwork();
      } catch (_) {}
      final openedMsg = [
        'GemWallet UI opened (interop)',
        if (openedAddr != null && openedAddr.isNotEmpty) 'address=' + openedAddr,
        if (openedNetwork != null && openedNetwork.isNotEmpty) 'network=' + openedNetwork,
      ].join(' | ');
      onEvent(SignProgressEvent(
        state: SignProgressState.opened,
        payloadId: payloadId,
        deepLink: _sanitizeUrl(deepLink),
        message: openedMsg,
      ));
      try {
        // タイムアウト制御（config.signingTimeout を利用）
        final res = await interop
            .requestSignGemWallet(txJson, options: {'submit': config.webSubmitByExtension})
            .timeout(config.signingTimeout);
        if (cancelToken.canceled) {
          throw StateError('SignCanceled');
        }
        final payloadIdFromRes = (res['payloadId'] ?? res['uuid'])?.toString();
        final errorMsg = res['error']?.toString();
        final rejected = res['rejected'] == true;
        final txHash = (res['txHash'] ?? res['hash'] ?? res['txid'])?.toString();
        final blob = res['tx_blob']?.toString();
        // デバッグ補助: 観測キーを収集（トップレベル/代表的なネスト）
        final observedKeys = <String>{};
        if (config.logObservedKeys) {
          try {
            observedKeys.addAll(res.keys.map((e) => e.toString()));
            final r1 = res['result'];
            if (r1 is Map) {
              observedKeys.addAll(r1.keys.map((e) => 'result.' + e.toString()));
            }
            final r2 = res['response'];
            if (r2 is Map) {
              observedKeys.addAll(r2.keys.map((e) => 'response.' + e.toString()));
            }
          } catch (_) {}
        }
        final keysMsg = observedKeys.isNotEmpty ? (' keys=' + observedKeys.join(',')) : '';
        if (payloadIdFromRes != null && payloadIdFromRes.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.created,
            payloadId: payloadIdFromRes,
            deepLink: deepLink,
            message: 'Payload info received (interop)'.toString(),
          ));
        }
        if (errorMsg != null && errorMsg.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.error,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'Interop error: ' + errorMsg,
          ));
          throw StateError('InteropError: $errorMsg');
        }
        if (rejected) {
          onEvent(SignProgressEvent(
            state: SignProgressState.rejected,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'User rejected (interop)',
          ));
          throw StateError('SignRejected by user');
        }
        if (txHash != null && txHash.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.signed,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'Signed (interop)' + keysMsg,
          ));
          onEvent(SignProgressEvent(
            state: SignProgressState.submitted,
            payloadId: payloadIdFromRes ?? payloadId,
            txHash: txHash,
            message: 'Submitted by extension',
          ));
          return {
            'result': {
              'tx_json': txJson,
              'hash': txHash,
              'deepLink': _sanitizeUrl(deepLink),
            }
          };
        }
        if (blob != null && blob.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.signed,
            payloadId: payloadIdFromRes ?? payloadId,
            message: 'Signed (interop) - submitting via client' + keysMsg,
          ));
          final submitRes = await client.call('submit', {'tx_blob': blob});
          final hash = submitRes['result']?['tx_json']?['hash']?.toString() ?? submitRes['result']?['txid']?.toString() ?? 'unknown';
          onEvent(SignProgressEvent(
            state: SignProgressState.submitted,
            payloadId: payloadIdFromRes ?? payloadId,
            txHash: hash,
            message: 'Submitted via client',
          ));
          return {
            'result': {
              'tx_json': txJson,
              'hash': hash,
              'deepLink': _sanitizeUrl(deepLink),
            }
          };
        }
        onEvent(SignProgressEvent(
          state: SignProgressState.error,
          payloadId: payloadIdFromRes ?? payloadId,
          message: 'Interop result not recognized' + keysMsg,
        ));
        throw StateError('InteropResultUnknown');
      } on TimeoutException catch (_) {
        onEvent(SignProgressEvent(
          state: SignProgressState.timeout,
          payloadId: payloadId,
          message: 'Interop timeout',
        ));
        throw StateError('SignTimeout');
      } catch (e) {
        onEvent(SignProgressEvent(
          state: SignProgressState.error,
          payloadId: payloadId,
          message: 'Interop error: ' + e.toString(),
        ));
        rethrow;
      }
    }

    // フォールバック（スタブ）
    await Future.delayed(const Duration(milliseconds: 150));
    if (cancelToken.canceled) {
      throw StateError('SignCanceled');
    }
    onEvent(SignProgressEvent(
      state: SignProgressState.opened,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(deepLink),
      message: 'GemWallet UI opened',
    ));

    await Future.delayed(const Duration(milliseconds: 200));
    if (cancelToken.canceled) {
      throw StateError('SignCanceled');
    }
    onEvent(SignProgressEvent(
      state: SignProgressState.signed,
      payloadId: payloadId,
      message: 'GemWallet signed',
    ));

    final hash = 'dummyHash-gemwallet';
    onEvent(SignProgressEvent(
      state: SignProgressState.submitted,
      payloadId: payloadId,
      txHash: hash,
      message: 'Submitted (stub)',
    ));
    return {
      'result': {
        'tx_json': txJson,
        'hash': hash,
        'deepLink': _sanitizeUrl(deepLink),
      }
    };
  }
}

/// WalletConnect v2 経由のアダプタ（現時点はスタブ）。
class WalletConnectAdapter implements WalletAdapter {
  @override
  Future<Map<String, dynamic>> signAndSubmit({
    required Map<String, dynamic> txJson,
    required WalletSession session,
    required WalletConnectorConfig config,
    required XRPLClient client,
    required void Function(SignProgressEvent event) onEvent,
    required CancelToken cancelToken,
  }) async {
    // 実装方針:
    // - config.walletConnectProxyBaseUrl が設定されている場合、バックエンド（BYOS）経由でセッション生成・ステータス取得を試行
    // - 失敗または未設定の場合は、wc: ペアリングURIをローカル生成してスタブ進行（UI/UX確認用）

    // 1) プロキシ経由の試行
    if (config.walletConnectProxyBaseUrl != null) {
      final base = config.walletConnectProxyBaseUrl!; // 例: http://your.domain/walletconnect/v1/
      final _schemeWc = base.scheme.toLowerCase();
      if (_schemeWc != 'http' && _schemeWc != 'https') {
        throw ArgumentError('Invalid proxy base URL scheme: ${base.scheme}');
      }
      if (config.disallowPrivateProxyHosts) {
        final host = base.host.toLowerCase();
        bool _isPrivate = host == 'localhost' || host == '127.0.0.1' || host.startsWith('10.') || host.startsWith('192.168.');
        if (!_isPrivate && host.startsWith('172.')) {
          final parts = host.split('.');
          if (parts.length > 1) {
            final s = int.tryParse(parts[1]) ?? -1;
            if (s >= 16 && s <= 31) {
              _isPrivate = true;
            }
          }
        }
        if (_isPrivate) {
          throw ArgumentError('Disallowed private/link-local proxy host: ' + base.toString());
        }
      }
      try {
        // セッション生成（pairing URIを取得）。tx_jsonも渡しておく（サーバー側で後続のリクエストを発行する設計を想定）
        final _jwt = (config.jwtBearerToken ?? '').trim();
        if (_jwt.isEmpty) {
          throw StateError('Missing JWT bearer token for WalletConnect proxy');
        }
        final createRes = await http
            .post(
          base.resolve('session/create'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + _jwt,
          },
          body: jsonEncode({'tx_json': txJson}),
        )
            .timeout(const Duration(seconds: 10));
        if (createRes.statusCode != 200) {
          throw StateError('WalletConnect proxy create failed: HTTP ${createRes.statusCode}');
        }
        final createJson = jsonDecode(createRes.body) as Map<String, dynamic>;
        final payloadId = (createJson['payloadId'] ?? createJson['sessionId'] ?? createJson['topic'])?.toString() ??
            ('WC_PAIR_' + DateTime.now().millisecondsSinceEpoch.toString());
        final deepLink = (createJson['pairingUri'] ?? createJson['deepLink'])?.toString();
        final qrUrl = createJson['qrUrl']?.toString();

        onEvent(SignProgressEvent(
          state: SignProgressState.created,
          payloadId: payloadId,
          deepLink: _sanitizeUrl(deepLink),
          qrUrl: _sanitizeHttpsOnly(qrUrl),
          message: 'WalletConnect pairing created by proxy',
        ));

        // ステータス取得をポーリング
        final deadline = DateTime.now().add(config.signingTimeout);
        Map<String, dynamic>? statusJson;
        int _attempt = 0;
        while (DateTime.now().isBefore(deadline)) {
          if (cancelToken.canceled) {
            throw StateError('SignCanceled');
          }
          final statusRes = await http
              .get(
            base.resolve('session/status/$payloadId'),
            headers: {
              'Authorization': 'Bearer ' + _jwt,
            },
          )
              .timeout(config.httpTimeout);
          if (statusRes.statusCode != 200) {
            final baseMs = config.pollingInterval.inMilliseconds * (1 << (_attempt.clamp(0, 4)));
            final jitterMs = ((baseMs * 0.2) * ((DateTime.now().microsecondsSinceEpoch % 1000) / 1000)).round();
            await Future.delayed(Duration(milliseconds: baseMs + jitterMs));
            _attempt++;
            continue;
          }
          statusJson = jsonDecode(statusRes.body) as Map<String, dynamic>;
          final opened = statusJson['opened'] == true || (statusJson['response']?['opened'] == true);
          final signed = statusJson['signed'] == true || (statusJson['response']?['signed'] == true);
          final rejected = statusJson['rejected'] == true || (statusJson['response']?['rejected'] == true);

          if (opened) {
            onEvent(SignProgressEvent(
              state: SignProgressState.opened,
              payloadId: payloadId,
              deepLink: _sanitizeUrl(deepLink),
              qrUrl: _sanitizeHttpsOnly(qrUrl),
              message: 'Wallet opened via proxy',
            ));
          }
          if (signed) break;
          if (rejected) {
            onEvent(SignProgressEvent(
              state: SignProgressState.rejected,
              payloadId: payloadId,
              message: 'User rejected (proxy)',
            ));
            throw StateError('SignRejected by user');
          }
          final baseMs = config.pollingInterval.inMilliseconds * (1 << (_attempt.clamp(0, 3)));
          final jitterMs = ((baseMs * 0.2) * ((DateTime.now().microsecondsSinceEpoch % 1000) / 1000)).round();
          await Future.delayed(Duration(milliseconds: baseMs + jitterMs));
          _attempt++;
        }

        if (statusJson == null) {
          onEvent(SignProgressEvent(
            state: SignProgressState.timeout,
            payloadId: payloadId,
            message: 'Signing timed out (proxy)',
          ));
          throw StateError('SignTimeout');
        }

        // 署名結果ハンドリング
        final txHash = statusJson['txHash']?.toString() ?? statusJson['response']?['txid']?.toString();
        if (txHash != null && txHash.isNotEmpty) {
          onEvent(SignProgressEvent(
            state: SignProgressState.signed,
            payloadId: payloadId,
            message: 'Signed (proxy)',
          ));
          onEvent(SignProgressEvent(
            state: SignProgressState.submitted,
            payloadId: payloadId,
            txHash: txHash,
            message: 'Submitted by proxy',
          ));
          return {
            'result': {
              'tx_json': txJson,
              'hash': txHash,
              'deepLink': _sanitizeUrl(deepLink),
            }
          };
        }

        final blob = statusJson['tx_blob']?.toString() ?? statusJson['response']?['tx_blob']?.toString();
        if (blob == null || blob.isEmpty) {
          throw StateError('Signed blob not available');
        }
        onEvent(SignProgressEvent(
          state: SignProgressState.signed,
          payloadId: payloadId,
          message: 'Signed (proxy) - submitting via client',
        ));
        final submitRes = await client.call('submit', {'tx_blob': blob});
        final hash = submitRes['result']?['tx_json']?['hash']?.toString() ?? submitRes['result']?['txid']?.toString() ?? 'unknown';
        onEvent(SignProgressEvent(
          state: SignProgressState.submitted,
          payloadId: payloadId,
          txHash: hash,
          message: 'Submitted via client',
        ));
        return {
          'result': {
            'tx_json': txJson,
            'hash': hash,
            'deepLink': _sanitizeUrl(deepLink),
          }
        };
      } catch (e) {
        // プロキシ連携に失敗した場合はローカルスタブへフォールバック
        onEvent(SignProgressEvent(
          state: SignProgressState.error,
          payloadId: 'WC_PROXY_ERR',
          message: 'Proxy error, fallback to local pairing: ' + e.toString(),
        ));
      }
    }

    // 2) ローカル生成スタブ（wc: ペアリングURI生成→擬似的なopened/signed/submitted）
    String _randomHex(int bytes) {
      final rng = Random.secure();
      final data = List<int>.generate(bytes, (_) => rng.nextInt(256));
      final buf = StringBuffer();
      for (final b in data) {
        buf.write(b.toRadixString(16).padLeft(2, '0'));
      }
      return buf.toString();
    }

    final topic = _randomHex(32); // 32 bytes
    final symKey = _randomHex(32); // 32 bytes
    final pairingUri = 'wc:' + topic + '@2?relay-protocol=irn&symKey=' + symKey;
    final payloadId = 'WC_PAIR_' + DateTime.now().millisecondsSinceEpoch.toString();

    onEvent(SignProgressEvent(
      state: SignProgressState.created,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(pairingUri),
      message: 'WalletConnect v2 pairing URI generated (stub)',
    ));

    await Future.delayed(const Duration(milliseconds: 300));
    if (cancelToken.canceled) {
      throw StateError('SignCanceled');
    }
    onEvent(SignProgressEvent(
      state: SignProgressState.opened,
      payloadId: payloadId,
      deepLink: _sanitizeUrl(pairingUri),
      message: 'Wallet app opened (stub)',
    ));

    final deadline = DateTime.now().add(config.signingTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (cancelToken.canceled) {
        throw StateError('SignCanceled');
      }
      await Future.delayed(const Duration(milliseconds: 500));
      break;
    }
    if (DateTime.now().isAfter(deadline)) {
      onEvent(SignProgressEvent(
        state: SignProgressState.timeout,
        payloadId: payloadId,
        message: 'Signing timed out (stub)',
      ));
      throw StateError('SignTimeout');
    }

    onEvent(SignProgressEvent(
      state: SignProgressState.signed,
      payloadId: payloadId,
      message: 'Signed (stub)',
    ));

    final hash = 'dummyHash-wc-' + topic.substring(0, 8);
    onEvent(SignProgressEvent(
      state: SignProgressState.submitted,
      payloadId: payloadId,
      txHash: hash,
      message: 'Submitted (stub)',
    ));

    return {
      'result': {
        'tx_json': txJson,
        'hash': hash,
        'deepLink': _sanitizeUrl(pairingUri),
      }
    };
  }
}

bool _isAllowedUrlScheme(String? url, {Set<String> allow = const {'https', 'xumm', 'xaman', 'crossmark', 'gemwallet', 'wc'}}) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final s = uri.scheme.toLowerCase();
  return allow.contains(s);
}

String? _sanitizeUrl(String? url) {
  return _isAllowedUrlScheme(url) ? url : null;
}

String? _sanitizeHttpsOnly(String? url) {
  return _isAllowedUrlScheme(url, allow: const {'https'}) ? url : null;
}
