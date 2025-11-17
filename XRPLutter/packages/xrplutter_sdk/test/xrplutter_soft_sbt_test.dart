// -------------------------------------------------------
// 目的・役割: XRPLutter.transferNftのSoft SBT運用補助（警告/ブロック）挙動の単体テスト。
// 作成日: 2025/11/09
//
// 更新履歴:
// 2025/11/09 11:30 初版作成。metadataJson経由でSoft SBT判定し、blockIfSoftSbt=trueで例外送出することを検証。
// 理由: README/仕様書の更新に伴い、警告/ブロックの最小実装がコードに反映されていることを担保するため。
// -------------------------------------------------------

import 'package:test/test.dart';
import 'package:xrplutter_sdk/xrplutter.dart';

class _FakeWalletConnector extends WalletConnector {
  @override
  Future<AccountInfo> getAccountInfo() async {
    return AccountInfo(address: 'rTEST', sequence: 1);
  }

  @override
  Future<Map<String, dynamic>> signAndSubmit({required Map<String, dynamic> txJson}) async {
    return {
      'result': {
        'tx_json': txJson,
        'hash': 'dummyHash',
      }
    };
  }
}

class _FakeNftService extends NftService {
  @override
  Future<bool> isTransferable({required String nftId}) async {
    // テストではチェーン非転送（Hard SBT）ではない前提とする
    return true;
  }
}

void main() {
  group('XRPLutter Soft SBT warnings/blocks', () {
    test('blockIfSoftSbt=true でSoft SBT送付を例外にする', () async {
      final sdk = XRPLutter(walletConnector: _FakeWalletConnector(), nftService: _FakeNftService());
      final softSbtMeta = {
        'name': 'Test',
        'custom': {'sbt': true}
      };
      expect(
        () => sdk.transferNft(
          nftId: '0001',
          destinationAddress: 'rDEST',
          amountDrops: '0',
          metadataJson: softSbtMeta,
          blockIfSoftSbt: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('warnIfSoftSbt=true でSoft SBT送付は許可（ブロックなし）', () async {
      final sdk = XRPLutter(walletConnector: _FakeWalletConnector(), nftService: _FakeNftService());
      final softSbtMeta = {
        'name': 'Test',
        'custom': {'sbt': true}
      };
      final result = await sdk.transferNft(
        nftId: '0001',
        destinationAddress: 'rDEST',
        amountDrops: '0',
        metadataJson: softSbtMeta,
        warnIfSoftSbt: true,
        blockIfSoftSbt: false,
      );
      expect(result.transactionHash, isNotEmpty);
    });
  });
}