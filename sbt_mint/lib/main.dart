// -------------------------------------------------------
// 目的・役割: SBT 2枚ミント→2枚バーン→ゴールドチケットミント→送付のデモUI（Flutter Web）
// 作成日: 2025/11/18
//
// 更新履歴:
// 2025/11/18 10:05 合成ボタンを追加（2枚選択→二段バーン→ゴールドミント連鎖）
// 理由: バーン開始とゴールドミントの操作を1ボタンに統合するため
// 2025/11/18 10:40 メタデータ画像の表示に対応（URI取得→image解決→サムネイル表示）
// 理由: ミントしたNFTの画像が一覧で見えるようにするため
// 2025/11/18 10:50 タイトルに(Testnet)を付与
// 理由: 接続ネットワークの明示
// 2025/11/18 11:10 送付処理のバリデーションと転送可否チェックを追加
// 理由: 不正なアドレス入力による失敗を防止しUXを改善
// 2025/11/18 11:30 ギフトQR送付フローを追加（オファー作成→受取用QR）
// 理由: 送付先アドレス不要でその場の相手へ渡せるようにする
// 2025/11/18 12:00 送付待ち状態の表示とボタン無効化を追加
// 理由: オファー作成済みNFTの重複送付を防ぎ、状態を明示
// 2025/11/18 15:20 バーン連鎖の安定化: 署名後のポーリング停止条件をtxHash取得まで延長し、拒否時の状態リセットを追加。
// 理由: 1枚目バーン後にポーリングを早期停止するとtxHash未取得のままとなり、次のバーン開始タイミングと競合するため。
// 2025/11/18 15:20 連続バーン時の同期強化: _runAndWaitでtx検証(awaitTransaction)を待機してから次処理へ進むよう変更。
// 理由: 連続トランザクションでシーケンスや検証待ちの競合を減らし、2枚目のバーンが確実に実行されるようにする。
// 2025/11/18 15:20 NFTokenBurnにOwnerフィールドを付与（自ウォレット所有で明示）。
// 理由: 発行者/所有者の差異やXamanオートフィル差異による不一致を避け、バーン対象所有者を明示するため。
// 2025/11/18 15:45 合成の手動再表示ボタンを追加（2枚目バーン/ゴールドミント）
// 理由: 2枚目バーン用QRが自動表示されないケースへのフォールバック操作を提供
// 2025/11/18 16:00 ゴールドミントボタンの条件付与（2枚バーン達成時のみ可）
// 理由: 合成未達でもミントできてしまう挙動を防ぎ、要件に合致させるため
// 2025/11/18 16:10 送付のギフトQR機能を廃止
// 理由: アドレス入力送付に一本化する運用に変更するため
// -------------------------------------------------------
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xrplutter_sdk/xrplutter.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XRPLutter SBT Demo (Testnet)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final NftService xrpl;
  String? _account;
  List<Map<String, dynamic>> _sbt = [];
  List<Map<String, dynamic>> _gold = [];
  List<String> _selectedSbtIds = [];
  final Map<String, String> _imageById = {};
  final Map<String, bool> _pendingById = {};
  String? _currentPayloadId;
  String? _currentQrUrl;
  String? _currentDeepLink;
  bool _currentSigned = false;
  String? _currentTxHash;
  Timer? _poller;

  String get _baseUrl => html.window.location.origin;

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final proxy = Uri.parse('$_baseUrl/api/xrpl/v1/jsonrpc').toString();
    xrpl = NftService(client: XRPLClient(endpoint: proxy));
  }

  Future<void> _createPayload(Map<String, dynamic> txJson) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/xumm/v1/payload/create');
      final r = await http.post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'tx_json': txJson}),
      );
      if (r.statusCode != 200) {
        String msg;
        try {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (body['error'] == 'xumm create failed') {
            msg = 'Xaman APIで認証失敗。XUMM_API_KEY/SECRETを確認してください。';
          } else if (r.statusCode == 401) {
            msg = '認証が必要です。VercelでAUTH_DISABLED=trueを設定してください。';
          } else {
            msg = 'ペイロード作成に失敗しました。${r.body}';
          }
        } catch (_) {
          msg = r.statusCode == 401
              ? '認証が必要です。VercelでAUTH_DISABLED=trueを設定してください。'
              : 'ペイロード作成に失敗しました。${r.body}';
        }
        _showError(msg);
        return;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      setState(() {
        _currentPayloadId = j['payloadId']?.toString();
        _currentQrUrl = j['qrUrl']?.toString();
        _currentDeepLink = j['deepLink']?.toString();
        _currentSigned = false;
        _currentTxHash = null;
      });
      _startPolling();
    } catch (e) {
      _showError('エラー: $e');
    }
  }

  void _startPolling() {
    _poller?.cancel();
    final id = _currentPayloadId;
    if (id == null) return;
    int attempts = 0;
    int hashAttempts = 0;
    _poller = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final uri = Uri.parse('$_baseUrl/api/xumm/v1/payload/status/$id');
        final r = await http.get(uri);
        if (r.statusCode != 200) return;
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final acc = j['account']?.toString();
        if (acc != null && acc.isNotEmpty) {
          setState(() {
            _account = acc;
          });
        }
        if (j['signed'] == true) {
          final txhPolled = j['txHash']?.toString();
          setState(() {
            _currentSigned = true;
            _currentTxHash = txhPolled;
            _currentQrUrl = null;
            _currentDeepLink = null;
          });
          // txHashが未取得の場合は一定回数までポーリング継続
          if (txhPolled == null || txhPolled.isEmpty) {
            if (hashAttempts < 10) {
              hashAttempts++;
              return; // 次回ポーリングへ（停止しない）
            }
          }
          // account未取得時も一定回数までは継続
          final hasAccount = (_account != null && _account!.isNotEmpty);
          if (!hasAccount && attempts < 8) {
            attempts++;
          } else {
            _poller?.cancel();
          }
          final txh = _currentTxHash;
          if (txh != null && txh.isNotEmpty) {
            try {
              await XRPLClient(
                endpoint: Uri.parse('$_baseUrl/api/xrpl/v1/jsonrpc').toString(),
              ).awaitTransaction(txh, timeout: const Duration(seconds: 20));
            } catch (_) {}
          }
          await _refreshNftsWithRetry();
        }
        if (j['rejected'] == true) {
          _poller?.cancel();
          setState(() {
            _currentQrUrl = null;
            _currentPayloadId = null;
            _currentDeepLink = null;
            _currentSigned = false;
            _currentTxHash = null;
          });
        }
      } catch (_) {}
    });
  }

  void _showError(String msg) {
    final sc = ScaffoldMessenger.maybeOf(context);
    sc?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _refreshNfts() async {
    if (_account == null) return;
    final page = await xrpl.fetchAccountNfts(account: _account!, limit: 200);
    final items = page.items;
    setState(() {
      _sbt = items
          .where((e) => _isTicketUri(e['URI']?.toString()))
          .where((e) => !_isTransferableFlag(e['Flags']))
          .toList();
      _gold = items.where((e) => _isGoldUri(e['URI']?.toString())).toList();
    });
    await _prefetchImages([..._sbt, ..._gold]);
    await _refreshOfferStates();
  }

  Future<void> _refreshNftsWithRetry({int attempts = 8}) async {
    for (int i = 0; i < attempts; i++) {
      await _refreshNfts();
      if (_sbt.isNotEmpty || _gold.isNotEmpty) break;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  bool _isTicketUri(String? hexUri) {
    if (hexUri == null) return false;
    final uri = _hexToString(hexUri);
    return uri.endsWith('/metadata/ticket.json');
  }

  bool _isGoldUri(String? hexUri) {
    if (hexUri == null) return false;
    final uri = _hexToString(hexUri);
    return uri.endsWith('/metadata/gold.json');
  }

  bool _isTransferableFlag(dynamic flags) {
    if (flags is int) return (flags & 0x00000008) != 0;
    return false;
  }

  String _hexToString(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return utf8.decode(bytes);
  }

  bool _selectedBothBurned() {
    if (_selectedSbtIds.length != 2) return false;
    final ids = _sbt.map((e) => e['NFTokenID']?.toString()).toSet();
    return !ids.contains(_selectedSbtIds[0]) &&
        !ids.contains(_selectedSbtIds[1]);
  }

  bool _firstOfSelectedBurned() {
    if (_selectedSbtIds.length != 2) return false;
    final ids = _sbt.map((e) => e['NFTokenID']?.toString()).toSet();
    return !ids.contains(_selectedSbtIds[0]) &&
        ids.contains(_selectedSbtIds[1]);
  }

  Future<void> _prefetchImages(List<Map<String, dynamic>> items) async {
    final futures = items.map((e) async {
      final id = e['NFTokenID']?.toString();
      final hexUri = e['URI']?.toString();
      if (id == null || hexUri == null) return;
      final uri = _hexToString(hexUri);
      try {
        final r = await http.get(Uri.parse(uri));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final img = j['image']?.toString();
          if (img != null && img.isNotEmpty) {
            final abs = img.startsWith('http')
                ? img
                : (img.startsWith('/') ? '$_baseUrl$img' : '$_baseUrl/$img');
            _imageById[id] = abs;
          }
        }
      } catch (_) {}
    }).toList();
    await Future.wait(futures);
    if (mounted) setState(() {});
  }

  Future<void> _refreshOfferStates() async {
    if (_account == null) return;
    final futures = _gold.map((e) async {
      final id = e['NFTokenID']?.toString();
      if (id == null) return;
      try {
        final offers = await xrpl.fetchNftOffers(nftId: id);
        final sell = offers.sellOffers;
        bool pending = false;
        for (final o in sell) {
          final owner = (o['owner'] ?? o['Owner'] ?? '').toString();
          final amt = (o['amount'] ?? o['Amount'] ?? '').toString();
          if (owner == _account && amt == '0') {
            pending = true;
            break;
          }
        }
        _pendingById[id] = pending;
      } catch (_) {}
    }).toList();
    await Future.wait(futures);
    if (mounted) setState(() {});
  }

  Future<void> _onConnect() async {
    await _createPayload({'TransactionType': 'SignIn'});
  }

  Future<void> _onMintSbt() async {
    final uri = '$_baseUrl/metadata/ticket.json';
    final tx = xrpl.buildMintTxJson(
      accountAddress: 'r',
      metadataUri: uri,
      taxon: 0,
      transferable: false,
    );
    tx.remove('Account');
    await _createPayload(tx);
  }

  Future<void> _onComposeGold() async {
    if (_account == null || _sbt.length < 2) return;
    final a = _sbt[0]['NFTokenID']?.toString();
    final b = _sbt[1]['NFTokenID']?.toString();
    if (a == null || b == null) return;
    await _createPayload({'TransactionType': 'NFTokenBurn', 'NFTokenID': a});
  }

  Future<void> _onMintGold() async {
    final uri = '$_baseUrl/metadata/gold.json';
    final tx = xrpl.buildMintTxJson(
      accountAddress: 'r',
      metadataUri: uri,
      taxon: 0,
      transferable: true,
    );
    tx.remove('Account');
    await _createPayload(tx);
  }

  Future<bool> _runAndWait(Map<String, dynamic> txJson) async {
    await _createPayload(txJson);
    for (int i = 0; i < 120; i++) {
      if (_currentSigned) {
        for (int j = 0; j < 10; j++) {
          if (_currentTxHash != null && _currentTxHash!.isNotEmpty) break;
          await Future.delayed(const Duration(seconds: 1));
        }
        // 可能なら検証完了まで待機し、次のトランザクションとの競合を防ぐ
        final txh = _currentTxHash;
        if (txh != null && txh.isNotEmpty) {
          try {
            await XRPLClient(
              endpoint: Uri.parse('$_baseUrl/api/xrpl/v1/jsonrpc').toString(),
            ).awaitTransaction(txh, timeout: const Duration(seconds: 20));
          } catch (_) {}
        }
        await _refreshNftsWithRetry();
        return true;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<void> _onCombineCompose() async {
    if (_account == null || _selectedSbtIds.length != 2) return;
    final a = _selectedSbtIds[0];
    final b = _selectedSbtIds[1];
    final ok1 = await _runAndWait({
      'TransactionType': 'NFTokenBurn',
      'NFTokenID': a,
      'Owner': _account,
      'Fee': '10',
    });
    if (!ok1) {
      _showError('1枚目のバーンが完了しませんでした');
      return;
    }
    final ok2 = await _runAndWait({
      'TransactionType': 'NFTokenBurn',
      'NFTokenID': b,
      'Owner': _account,
      'Fee': '10',
    });
    if (!ok2) {
      _showError('2枚目のバーンが完了しませんでした');
      return;
    }
    final uri = '$_baseUrl/metadata/gold.json';
    final tx = xrpl.buildMintTxJson(
      accountAddress: 'r',
      metadataUri: uri,
      taxon: 0,
      transferable: true,
    );
    tx.remove('Account');
    final ok3 = await _runAndWait(tx);
    if (!ok3) {
      _showError('ゴールドのミントが完了しませんでした');
      return;
    }
    setState(() {
      _selectedSbtIds.clear();
    });
  }

  Future<void> _onSendGold({
    required String nftId,
    required String dest,
  }) async {
    final d = dest.trim();
    if (d.isEmpty || !d.startsWith('r') || d.length < 25) {
      _showError('送付先アドレスが不正です');
      return;
    }
    final ok = await xrpl.isTransferable(nftId: nftId).catchError((_) => true);
    if (!ok) {
      _showError('このNFTは転送不可です');
      return;
    }
    final tx = xrpl.buildCreateOfferTxJson(
      accountAddress: 'r',
      nftId: nftId,
      destinationAddress: d,
      amountDrops: '0',
    );
    tx.remove('Account');
    await _createPayload(tx);
  }

  Future<void> _onGiftQr({required String nftId}) async {
    final ok = await xrpl.isTransferable(nftId: nftId).catchError((_) => true);
    if (!ok) {
      _showError('このNFTは転送不可です');
      return;
    }
    final create = xrpl.buildCreateOfferTxJson(
      accountAddress: 'r',
      nftId: nftId,
      destinationAddress: 'r',
      amountDrops: '0',
    );
    create.remove('Destination');
    create.remove('Account');
    final ok1 = await _runAndWait(create);
    if (!ok1) {
      _showError('ギフト用オファーの作成に失敗しました');
      return;
    }
    final offers = await xrpl.fetchNftOffers(nftId: nftId);
    final sell = offers.sellOffers;
    String? offerId;
    for (final o in sell) {
      final owner = (o['owner'] ?? o['Owner'] ?? '').toString();
      final dest = o['destination'] ?? o['Destination'];
      final amt = (o['amount'] ?? o['Amount'] ?? '').toString();
      final idx =
          (o['index'] ?? o['Index'] ?? o['offer_id'] ?? o['OfferID'] ?? '')
              .toString();
      if ((dest == null) && amt == '0' && owner == _account) {
        offerId = idx;
        break;
      }
    }
    if (offerId == null || offerId.isEmpty) {
      _showError('オファーIDの取得に失敗しました');
      return;
    }
    final accept = xrpl.buildAcceptOfferTxJson(
      accountAddress: 'r',
      offerId: offerId,
    );
    accept.remove('Account');
    await _createPayload(accept);
  }

  Future<void> _onShowSecondBurnSelected() async {
    if (_selectedSbtIds.length != 2) {
      _showError('2枚選択してください');
      return;
    }
    final b = _selectedSbtIds[1];
    await _createPayload({
      'TransactionType': 'NFTokenBurn',
      'NFTokenID': b,
      'Fee': '10',
    });
  }

  Future<void> _onShowGoldMint() async {
    if (!_selectedBothBurned()) {
      _showError('2枚バーン達成後にミントできます');
      return;
    }
    final uri = '$_baseUrl/metadata/gold.json';
    final tx = xrpl.buildMintTxJson(
      accountAddress: 'r',
      metadataUri: uri,
      taxon: 0,
      transferable: true,
    );
    tx.remove('Account');
    await _createPayload(tx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XRPLutter SBT Demo (Testnet)')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _onConnect,
                      child: Text(
                        _account == null
                            ? 'ウォレットを読み込み'
                            : (_currentSigned
                                  ? '署名済み: $_account'
                                  : '接続済み: $_account'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_currentTxHash != null)
                      InkWell(
                        onTap: () {
                          final h = _currentTxHash!;
                          final url =
                              'https://testnet.xrpl.org/transactions/$h';
                          html.window.open(url, '_blank');
                        },
                        child: Text(
                          'Tx: $_currentTxHash',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                    const SizedBox(width: 16),
                    if (_account != null)
                      OutlinedButton(
                        onPressed: _refreshNfts,
                        child: const Text('NFT再読み込み'),
                      ),
                  ],
                ),
                if (_account != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'アカウント: $_account',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'ミント',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Image.network('/images/ticket.png', width: 160, height: 90),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _onMintSbt,
                      child: const Text('Mint'),
                    ),
                  ],
                ),
                const Divider(height: 32),
                const Text(
                  '合成（2枚バーン→ゴールドミント）',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _sbt.map((e) {
                    final id = e['NFTokenID'].toString();
                    final selected = _selectedSbtIds.contains(id);
                    final canSelectMore =
                        selected || _selectedSbtIds.length < 2;
                    return FilterChip(
                      label: Text(id),
                      avatar: _imageById[id] != null
                          ? CircleAvatar(
                              backgroundImage: NetworkImage(_imageById[id]!),
                            )
                          : null,
                      selected: selected,
                      onSelected: (v) {
                        if (v) {
                          if (canSelectMore) {
                            setState(() {
                              _selectedSbtIds.add(id);
                            });
                          } else {
                            _showError('合成には最大2枚まで選択できます');
                          }
                        } else {
                          setState(() {
                            _selectedSbtIds.remove(id);
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed:
                          (_account != null && _selectedSbtIds.length == 2)
                          ? _onCombineCompose
                          : null,
                      child: const Text('合成'),
                    ),
                    const SizedBox(width: 12),
                    Text('選択: ${_selectedSbtIds.length}/2'),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: (_account != null && _firstOfSelectedBurned())
                          ? _onShowSecondBurnSelected
                          : null,
                      child: const Text('2枚目バーンQRを表示'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: (_account != null && _selectedBothBurned())
                          ? _onShowGoldMint
                          : null,
                      child: const Text('ゴールドミントQRを表示'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '注意: 自働化は未実装のため、各ステップ後は「NFT再読み込み」を押してください。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const Divider(height: 32),
                const Text(
                  '送付（ゴールドのみ）',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _gold
                      .map(
                        (e) => _SendTile(
                          nftId: e['NFTokenID'].toString(),
                          imageUrl: _imageById[e['NFTokenID'].toString()],
                          pending:
                              _pendingById[e['NFTokenID'].toString()] == true,
                          onSend: _onSendGold,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          if (_currentQrUrl != null || _currentDeepLink != null)
            _QrOverlay(
              qrUrl: _currentQrUrl,
              deepLink: _currentDeepLink,
              onClose: () {
                _poller?.cancel();
                setState(() {
                  _currentQrUrl = null;
                  _currentPayloadId = null;
                  _currentDeepLink = null;
                });
              },
            ),
        ],
      ),
    );
  }
}

class _QrOverlay extends StatelessWidget {
  const _QrOverlay({this.qrUrl, this.deepLink, required this.onClose});
  final String? qrUrl;
  final String? deepLink;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Xamanで署名',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 8),
              if (qrUrl != null)
                Image.network(
                  qrUrl!,
                  width: 240,
                  height: 240,
                  fit: BoxFit.contain,
                ),
              const SizedBox(height: 8),
              if (deepLink != null)
                ElevatedButton(
                  onPressed: () {
                    try {
                      html.window.open(deepLink!, '_blank');
                    } catch (_) {}
                  },
                  child: const Text('Xamanで開く'),
                ),
              if (deepLink != null)
                SelectableText(deepLink!, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendTile extends StatefulWidget {
  const _SendTile({
    required this.nftId,
    this.imageUrl,
    this.pending = false,
    required this.onSend,
  });
  final String nftId;
  final String? imageUrl;
  final bool pending;
  final Future<void> Function({required String nftId, required String dest})
  onSend;
  @override
  State<_SendTile> createState() => _SendTileState();
}

class _SendTileState extends State<_SendTile> {
  final c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.imageUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Image.network(
                widget.imageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          Text(widget.nftId, overflow: TextOverflow.ellipsis),
          const SizedBox(width: 8),
          SizedBox(
            width: 240,
            child: TextField(
              controller: c,
              decoration: const InputDecoration(hintText: '送付先アドレス'),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: widget.pending
                ? null
                : () => widget.onSend(nftId: widget.nftId, dest: c.text.trim()),
            child: const Text('送付'),
          ),
          const SizedBox(width: 8),
          if (widget.pending)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '受取待ち',
                style: TextStyle(color: Colors.orange.shade700),
              ),
            ),
        ],
      ),
    );
  }
}
