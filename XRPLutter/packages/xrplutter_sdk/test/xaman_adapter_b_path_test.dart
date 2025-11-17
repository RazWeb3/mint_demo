// -------------------------------------------------------
// 目的・役割: XamanAdapter（XUMM）連携のBパス（tx_blob返却→SDK側submit）をモックで検証する統合テスト。
//             payload/create→statusポーリング（signed & tx_blob）→XRPLClient.submit（スタブ）→hash返却までのイベント順序と結果を確認する。
// 作成日: 2025/11/09
// -------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

import 'package:xrplutter_sdk/src/wallet_connector.dart';
import 'package:xrplutter_sdk/src/wallet_config.dart';
import 'package:xrplutter_sdk/src/xrpl_client.dart';
import 'package:xrplutter_sdk/src/models.dart';

/// XRPLClientのスタブ（submit結果を擬似返却）
class FakeXRPLClient extends XRPLClient {
  FakeXRPLClient();
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params) async {
    // submitのみを想定。txidを返却する形にしてWalletConnector側のhash抽出に対応
    if (method == 'submit') {
      return {
        'result': {
          'txid': 'FAKE_HASH_456',
          'tx_json': {
            'hash': 'FAKE_HASH_456',
          }
        }
      };
    }
    return {'result': {}};
  }
}

void main() {
  group('XamanAdapter mock integration (B path: tx_blob -> submit)', () {
    late HttpServer server;
    late int port;

    int statusCalls = 0;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      statusCalls = 0;

      server.listen((HttpRequest req) async {
        final path = req.uri.path;
        if (req.method == 'POST' && path.endsWith('/xumm/v1/payload/create')) {
          final body = await utf8.decoder.bind(req).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          expect(decoded.containsKey('tx_json'), isTrue);
          final res = {
            'payloadId': 'TEST_PAYLOAD_ID_B',
            'deepLink': 'xumm://payload/TEST_PAYLOAD_ID_B',
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
            res = {
              'opened': true,
              'signed': false,
              'rejected': false,
            };
          } else {
            // Bパス: tx_blobのみ返す（txHashは無し）
            res = {
              'opened': true,
              'signed': true,
              'rejected': false,
              'tx_blob': 'DEADBEEF',
            };
          }
          final text = jsonEncode(res);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(text);
          await req.response.close();
          return;
        }

        req.response.statusCode = 404;
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('signAndSubmit submits via client when tx_blob is returned', () async {
      final config = WalletConnectorConfig(
        xamanProxyBaseUrl: Uri.parse('http://localhost:$port/xumm/v1/'),
        signingTimeout: const Duration(seconds: 5),
        pollingInterval: const Duration(milliseconds: 100),
        jwtBearerToken: 'dev-secret',
      );
      final connector = WalletConnector(config: config, client: FakeXRPLClient());
      final events = <SignProgressEvent>[];
      final sub = connector.progressStream.listen(events.add);

      await connector.connect(provider: WalletProvider.xaman);

      final result = await connector.signAndSubmit(txJson: {
        'TransactionType': 'NFTokenMint',
        'Account': 'rTEST',
        'URI': 'https://example.com/nft',
      });

      await Future.delayed(const Duration(milliseconds: 150));
      await sub.cancel();

      expect(result['result']['hash'], equals('FAKE_HASH_456'));

      final states = events.map((e) => e.state).toList();
      expect(states.first, equals(SignProgressState.created));
      expect(states.contains(SignProgressState.opened), isTrue);
      expect(states.contains(SignProgressState.signed), isTrue);
      expect(states.contains(SignProgressState.submitted), isTrue);
    });
  });
}
