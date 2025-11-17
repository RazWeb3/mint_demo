import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:xrplutter_sdk/src/xrpl_client.dart';

void main() {
  group('XRPLClient retry/timeout behavior', () {
    late HttpServer server;
    late Uri endpoint;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri.parse('http://localhost:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('socket failure triggers retry then may fail', () async {
      int calls = 0;
      server.listen((HttpRequest req) async {
        calls += 1;
        if (calls == 1) {
          // abruptly close connection to simulate SocketException on client
          req.response.headers.contentLength = 0;
          await req.response.detachSocket();
          return;
        }
        final body = jsonEncode({
          'result': {
            'status': 'success',
            'account_data': {'Sequence': 1}
          }
        });
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });

      final client = XRPLClient(
        endpoint: endpoint.toString(),
        timeout: const Duration(seconds: 2),
        maxRetries: 1,
        retryBaseDelayMs: 10,
      );
      expect(
        () => client.call('account_info', {'account': 'rTEST'}),
        throwsA(isA<Exception>()),
      );
    });

    test('retries on timeout then succeeds', () async {
      int calls = 0;
      server.listen((HttpRequest req) async {
        calls += 1;
        if (calls == 1) {
          await Future.delayed(const Duration(seconds: 3));
          // connection will be closed by server without response
          await req.response.close();
          return;
        }
        final body = jsonEncode({
          'result': {
            'status': 'success',
            'tx_json': {'hash': 'DUMMY'}
          }
        });
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });

      final client = XRPLClient(
        endpoint: endpoint.toString(),
        timeout: const Duration(seconds: 1),
        maxRetries: 1,
        retryBaseDelayMs: 10,
      );
      final res = await client.call('submit', {'tx_blob': 'ABC'});
      expect(res['result'], isA<Map<String, dynamic>>());
    });
  });
}
