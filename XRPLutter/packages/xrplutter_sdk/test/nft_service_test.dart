// -------------------------------------------------------
// 目的・役割: NftServiceのtx_jsonビルダーと事前チェックロジックの単体テスト。
// 作成日: 2025/11/09
//
// 更新履歴:
// 2025/11/09 12:10 初版: Mint/Transfer/Burnのビルダー検証とisTransferableのモック検証を追加。
// 理由: 仕様に基づくフラグ整合性（TransferFeeとtfTransferable）とOffer/Accept生成の正しさを確認するため。
// -------------------------------------------------------

import 'package:test/test.dart';
import 'package:xrplutter_sdk/src/nft_service.dart';
import 'package:xrplutter_sdk/src/xrpl_client.dart';

class _FakeXRPLClientTrue extends XRPLClient {
  _FakeXRPLClientTrue();
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params) async {
    return {
      'result': {
        'nft': {
          'Flags': 0x00000008, // lsfTransferable 想定
        }
      }
    };
  }
}

class _FakeXRPLClientFalse extends XRPLClient {
  _FakeXRPLClientFalse();
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params) async {
    return {
      'result': {
        'nft': {
          'Flags': 0x00000000, // 非転送
        }
      }
    };
  }
}

void main() {
  group('NftService.buildMintTxJson', () {
    test('transferable=trueでtfTransferableフラグが立つ', () {
      final service = NftService();
      final tx = service.buildMintTxJson(
        accountAddress: 'rTEST',
        metadataUri: 'ipfs://metadata.json',
        taxon: 0,
        transferFeeBps: null,
        flags: const {},
        minterAddress: null,
        sbt: null,
        transferable: true,
      );
      final flags = tx['Flags'] as int;
      expect((flags & 0x00000008) != 0, isTrue);
    });

    test('transferable=falseでTransferFee指定はArgumentError', () {
      final service = NftService();
      expect(
        () => service.buildMintTxJson(
          accountAddress: 'rTEST',
          metadataUri: 'ipfs://metadata.json',
          taxon: 0,
          transferFeeBps: 100,
          flags: const {},
          minterAddress: null,
          sbt: null,
          transferable: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('NftService.buildCreateOfferTxJson', () {
    test('DestinationとAmount(デフォルト0)が設定される', () {
      final service = NftService();
      final tx = service.buildCreateOfferTxJson(
        accountAddress: 'rSENDER',
        nftId: 'NFTID',
        destinationAddress: 'rDEST',
        amountDrops: null,
      );
      expect(tx['Destination'], equals('rDEST'));
      expect(tx['Amount'], equals('0'));
    });
  });

  group('NftService.buildAcceptOfferTxJson', () {
    test('SellOfferにofferIdがセットされる', () {
      final service = NftService();
      final tx = service.buildAcceptOfferTxJson(
        accountAddress: 'rRECEIVER',
        offerId: 'OFFER123',
      );
      expect(tx['SellOffer'], equals('OFFER123'));
    });
  });

  group('NftService.isTransferable', () {
    test('lsfTransferableありでtrueを返す', () async {
      final service = NftService(client: _FakeXRPLClientTrue());
      final result = await service.isTransferable(nftId: 'ANY');
      expect(result, isTrue);
    });

    test('lsfTransferableなしでfalseを返す', () async {
      final service = NftService(client: _FakeXRPLClientFalse());
      final result = await service.isTransferable(nftId: 'ANY');
      expect(result, isFalse);
    });
  });
}