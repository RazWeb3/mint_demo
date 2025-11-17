// -------------------------------------------------------
// 目的・役割: SBT 2枚ミント→2枚バーン→ゴールドチケットミント→送付のデモUI（Flutter Web）
// 作成日: 2025/11/18
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
      title: 'XRPLutter SBT Demo',
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
          setState(() {
            _currentSigned = true;
            _currentTxHash = j['txHash']?.toString();
            _currentQrUrl = null;
            _currentDeepLink = null;
          });
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

  Future<void> _onSendGold({
    required String nftId,
    required String dest,
  }) async {
    final tx = xrpl.buildCreateOfferTxJson(
      accountAddress: 'r',
      nftId: nftId,
      destinationAddress: dest,
      amountDrops: '0',
    );
    tx.remove('Account');
    await _createPayload(tx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XRPLutter SBT Demo')),
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
                            : (_currentSigned ? '署名済み: $_account' : '接続済み: $_account'),
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
                  children: _sbt
                      .map((e) => Chip(label: Text(e['NFTokenID'].toString())))
                      .toList(),
                ),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _onComposeGold,
                      child: const Text('バーン開始'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _onMintGold,
                      child: const Text('ゴールドミント'),
                    ),
                  ],
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
  const _SendTile({required this.nftId, required this.onSend});
  final String nftId;
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
            onPressed: () =>
                widget.onSend(nftId: widget.nftId, dest: c.text.trim()),
            child: const Text('送付'),
          ),
        ],
      ),
    );
  }
}
