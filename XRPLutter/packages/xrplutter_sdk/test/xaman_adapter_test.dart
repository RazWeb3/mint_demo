// -------------------------------------------------------
// 目的・役割: XamanAdapter（XUMM）連携の統合テスト（モックサーバ）を実施し、
//             payload/create→statusポーリング→結果返却のイベント順序と最終hashを検証する。
// 作成日: 2025/11/09
//
// 更新履歴:
// 2025/11/09 13:40 初版作成。モックHTTPサーバによりtxHash返却（プロキシ送信済み）パスをテスト。
// 理由: 実際のXRPL submitを行わずに、SDKの進捗イベントと結果構造の正しさを担保するため。
// -------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

import 'package:xrplutter_sdk/src/wallet_connector.dart';
import 'package:xrplutter_sdk/src/wallet_config.dart';
import 'package:xrplutter_sdk/src/xrpl_client.dart';
import 'package:xrplutter_sdk/src/models.dart';

void main() {
  group('XamanAdapter mock integration', () {
    late HttpServer server;
    late int port;

    // 状態管理: status呼び出し回数
    int statusCalls = 0;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      statusCalls = 0;

      // シンプルなルーティング
      server.listen((HttpRequest req) async {
        final path = req.uri.path;
        if (req.method == 'POST' && path.endsWith('/xumm/v1/payload/create')) {
          final body = await utf8.decoder.bind(req).join();
          // 受信tx_jsonは検証不要（存在だけ確認）
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          expect(decoded.containsKey('tx_json'), isTrue);
          final res = {
            'payloadId': 'TEST_PAYLOAD_ID',
            'deepLink': 'xumm://payload/TEST_PAYLOAD_ID',
            'qrUrl': 'https://example.com/qr/TEST_PAYLOAD_ID',
          };
          final text = jsonEncode(res);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(text);
          await req.response.close();
          return;
        }

        if (req.method == 'GET' && path.contains('/xumm/v1/payload/status/')) {
          statusCalls += 1;
          Map<String, dynamic> res;
          if (statusCalls == 1) {
            // 初回はopenedのみ
            res = {
              'opened': true,
              'signed': false,
              'rejected': false,
            };
          } else {
            // 2回目以降はsigned+txHash返却（プロキシ送信済みパス）
            res = {
              'opened': true,
              'signed': true,
              'rejected': false,
              'txHash': 'TEST_TX_HASH_123',
            };
          }
          final text = jsonEncode(res);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(text);
          await req.response.close();
          return;
        }

        // 未対応パス
        req.response.statusCode = 404;
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('signAndSubmit emits events and returns final hash', () async {
      final config = WalletConnectorConfig(
        xamanProxyBaseUrl: Uri.parse('http://localhost:$port/xumm/v1/'),
        signingTimeout: const Duration(seconds: 5),
        pollingInterval: const Duration(milliseconds: 100),
        jwtBearerToken: 'dev-secret',
      );
      final connector = WalletConnector(config: config, client: XRPLClient());
      final events = <SignProgressEvent>[];
      final sub = connector.progressStream.listen(events.add);

      await connector.connect(provider: WalletProvider.xaman);

      final result = await connector.signAndSubmit(txJson: {
        'TransactionType': 'NFTokenMint',
        'Account': 'rTEST',
        'URI': 'https://example.com/nft',
      });
      // 非同期Stream配信の遅延を吸収
      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      // 結果の検証
      expect(result['result'], isA<Map<String, dynamic>>());
      expect(result['result']['hash'], equals('TEST_TX_HASH_123'));

      // イベント順序の検証: created -> opened -> signed -> submitted
      final states = events.map((e) => e.state).toList();
      expect(states.first, equals(SignProgressState.created));
      expect(states.contains(SignProgressState.opened), isTrue);
      final signedIndex = states.indexOf(SignProgressState.signed);
      final submittedIndex = states.indexOf(SignProgressState.submitted);
      expect(signedIndex, isNot(-1));
      expect(submittedIndex, isNot(-1));
      expect(signedIndex < submittedIndex, isTrue);
    });
  });
}
