// -------------------------------------------------------
// 目的・役割: NFTの発行・送付・バーンなどの高レベル操作を提供するサービス層。
// 作成日: 2025/11/08
//
// 更新履歴:
// 2025/11/08 23:55 mintのパラメータにminterAddress/sbt/transferableを追加。
// 理由: 指定アドレスでの発行とSBT（非転送）表現に対応するための拡張。
// 2025/11/08 23:59 追記: tfTransferable（チェーンレベル転送可否）の方針を反映。TransferFeeとtransferableの整合性チェックを追加（仕様メモ）。
// 理由: Hard SBT/NTTの採用に伴い、ミント時のフラグ生成と注意点を明確化するため。
// 2025/11/09 00:12 mintにaccountAddress必須引数を追加し、_buildMintTxJsonを実装。
// 理由: 非カストディアル運用での外部署名フローに合わせ、署名前のトランザクションJSON構築を開始するため。
// 2025/11/09 00:25 追記: buildMintTxJson/buildBurnTxJsonの公開APIを追加。transfer用CreateOffer/Acceptのtx_jsonビルダーと転送可否チェック（nft_info）を準備。
// 理由: XRPLutter側で外部署名（WalletConnector）をオーケストレーションするための下支え。
// 2025/11/16 10:20 変更: URIのHex化をUTF-16コードユニットからUTF-8バイト列へ修正。
// 理由: XLS-20互換性と相互運用性の向上（文字列エンコードの標準化）。
// 2025/11/16 13:05 変更: 発行者バーン対応のため、buildBurnTxJson/burn/_buildBurnTxJsonにownerAddressオプションを追加（NFTokenBurn.Owner）。
// 理由: tfBurnable設定済みNFTに対する発行者/認可ミンターのバーン機能をSDKビルダーで扱えるようにするため。
// -------------------------------------------------------

import 'dart:convert';
import 'models.dart';
import 'xrpl_client.dart';

class NftService {
  NftService({XRPLClient? client}) : _client = client ?? XRPLClient();
  final XRPLClient _client;
  // 直近で構築したミント用tx_jsonプレビュー（外部署名前の参考情報）
  Map<String, dynamic>? lastMintTxPreview;
  Map<String, dynamic>? get lastMintTxPreviewView => lastMintTxPreview;

  // NFTokenMint Flags（XLS-20）
  // 参考: tfBurnable=0x00000001, tfOnlyXRP=0x00000002, tfTrustLine(deprecated)=0x00000004, tfTransferable=0x00000008, tfMutable=0x00000010
  static const int _tfBurnable = 0x00000001;
  static const int _tfOnlyXRP = 0x00000002;
  static const int _tfTransferable = 0x00000008;
  static const int _tfMutable = 0x00000010;
  // NFTokenオブジェクト Flags（推定値、要検証）
  static const int _lsfTransferable = 0x00000008;

  Future<MintResult> mint({
    required String accountAddress,
    required String metadataUri,
    int? taxon,
    int? transferFeeBps,
    Map<String, dynamic>? flags,
    String? minterAddress,
    bool? sbt,
    bool? transferable,
  }) async {
    // フラグ生成（チェーンレベル転送可否）
    int mintFlags = 0;
    if (flags != null) {
      if (flags['burnable'] == true) mintFlags |= _tfBurnable;
      if (flags['onlyXrp'] == true) mintFlags |= _tfOnlyXRP;
      if (flags['mutable'] == true) mintFlags |= _tfMutable;
    }
    if (transferable == true) {
      mintFlags |= _tfTransferable;
    }
    if (transferFeeBps != null) {
      if ((mintFlags & _tfTransferable) == 0) {
        throw ArgumentError('TransferFeeを設定する場合、transferable=true（tfTransferable）である必要があります。');
      }
    }

    // トランザクションJSONの構築（署名前）
    final tx = _buildMintTxJson(
      accountAddress: accountAddress,
      metadataUri: metadataUri,
      taxon: taxon ?? 0,
      transferFeeBps: transferFeeBps,
      issuerAddress: (minterAddress != null && minterAddress != accountAddress) ? minterAddress : null,
      flagsValue: mintFlags,
    );
    // デバッグ/確認用に保持（仕様: 署名前のtx_jsonプレビュー）
    lastMintTxPreview = tx;
    return MintResult(transactionHash: 'preview', nftId: 'unknown');
  }

  Future<TransferResult> transfer({
    required String nftId,
    required String destinationAddress,
    String? amountDrops,
  }) async {
    return TransferResult(transactionHash: 'preview');
  }

  Future<BurnResult> burn({required String nftId, String? ownerAddress}) async {
    final preview = _buildBurnTxJson(
      accountAddress: 'rSIGNER_ADDRESS_TBD',
      nftId: nftId,
      ownerAddress: ownerAddress,
    );
    _lastBurnTxPreview = preview;
    return BurnResult(transactionHash: 'preview');
  }

  Future<AccountNftsPage> fetchAccountNfts({
    required String account,
    int? limit,
    String? marker,
    String? issuer,
    int? taxon,
    bool transferableOnly = false,
  }) async {
    final params = <String, dynamic>{
      'account': account,
      if (limit != null) 'limit': limit,
      if (marker != null) 'marker': marker,
    };
    final res = await _client.call('account_nfts', params);
    final result = res['result'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final raw = (result['account_nfts'] as List?) ?? const [];
    final items = raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    List<Map<String, dynamic>> filtered = items;
    if (issuer != null && issuer.isNotEmpty) {
      filtered = filtered.where((e) => (e['Issuer'] ?? e['issuer']) == issuer).toList();
    }
    if (taxon != null) {
      filtered = filtered.where((e) => (e['NFTokenTaxon'] ?? e['nftoken_taxon']) == taxon).toList();
    }
    if (transferableOnly) {
      filtered = filtered.where((e) {
        final flags = e['Flags'] ?? e['flags'] ?? 0;
        return flags is int ? (flags & _lsfTransferable) != 0 : true;
      }).toList();
    }
    final nextMarker = result['marker']?.toString();
    return AccountNftsPage(items: filtered, marker: nextMarker);
  }

  Future<NftOfferList> fetchNftOffers({required String nftId}) async {
    final results = await Future.wait<Map<String, dynamic>>([
      _client.call('nft_sell_offers', {'nft_id': nftId}).catchError((_) => {'result': {'offers': []}}),
      _client.call('nft_buy_offers', {'nft_id': nftId}).catchError((_) => {'result': {'offers': []}}),
    ]);
    final sellRes = results[0];
    final buyRes = results[1];
    final sell = (sellRes['result']?['offers'] as List?)?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
    final buy = (buyRes['result']?['offers'] as List?)?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
    return NftOfferList(sellOffers: sell, buyOffers: buy);
  }

  Map<String, dynamic> _buildMintTxJson({
    required String accountAddress,
    required String metadataUri,
    required int taxon,
    int? transferFeeBps,
    String? issuerAddress,
    required int flagsValue,
  }) {
    final tx = <String, dynamic>{
      'TransactionType': 'NFTokenMint',
      'Account': accountAddress,
      'NFTokenTaxon': taxon,
      'Flags': flagsValue,
      'URI': _stringToHex(metadataUri),
      'Fee': '10',
    };
    if (transferFeeBps != null) {
      // 範囲チェック（0..50000）
      if (transferFeeBps < 0 || transferFeeBps > 50000) {
        throw ArgumentError('TransferFeeは0〜50000の範囲で指定してください。');
      }
      tx['TransferFee'] = transferFeeBps;
    }
    if (issuerAddress != null) {
      tx['Issuer'] = issuerAddress;
    }
    return tx;
  }

  String _stringToHex(String input) {
    final bytes = utf8.encode(input);
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  // 公開API: Mint用tx_jsonを構築して返す（外部ウォレットでの署名前）
  Map<String, dynamic> buildMintTxJson({
    required String accountAddress,
    required String metadataUri,
    int? taxon,
    int? transferFeeBps,
    Map<String, dynamic>? flags,
    String? minterAddress,
    bool? sbt,
    bool? transferable,
  }) {
    // フラグ生成（チェーンレベル転送可否）
    int mintFlags = 0;
    if (flags != null) {
      if (flags['burnable'] == true) mintFlags |= _tfBurnable;
      if (flags['onlyXrp'] == true) mintFlags |= _tfOnlyXRP;
      if (flags['mutable'] == true) mintFlags |= _tfMutable;
    }
    if (transferable == true) {
      mintFlags |= _tfTransferable;
    }
    if (transferFeeBps != null) {
      if ((mintFlags & _tfTransferable) == 0) {
        throw ArgumentError('TransferFeeを設定する場合、transferable=true（tfTransferable）である必要があります。');
      }
    }

    final tx = _buildMintTxJson(
      accountAddress: accountAddress,
      metadataUri: metadataUri,
      taxon: (taxon ?? 0),
      transferFeeBps: transferFeeBps,
      issuerAddress: (minterAddress != null && minterAddress != accountAddress) ? minterAddress : null,
      flagsValue: mintFlags,
    );
    lastMintTxPreview = tx;
    return tx;
  }

  // 公開API: Burn用tx_jsonを構築して返す（外部ウォレットでの署名前）
  Map<String, dynamic> buildBurnTxJson({
    required String accountAddress,
    required String nftId,
    String? ownerAddress,
  }) {
    final tx = {
      'TransactionType': 'NFTokenBurn',
      'Account': accountAddress,
      'NFTokenID': nftId,
      'Fee': '10',
    };
    if (ownerAddress != null && ownerAddress.isNotEmpty) {
      tx['Owner'] = ownerAddress;
    }
    _lastBurnTxPreview = tx;
    return tx;
  }

  // 公開API: CreateOffer用tx_jsonを構築（ギフト/売買両対応）
  Map<String, dynamic> buildCreateOfferTxJson({
    required String accountAddress,
    required String nftId,
    required String destinationAddress,
    String? amountDrops, // null/"0"でギフト
  }) {
    final tx = <String, dynamic>{
      'TransactionType': 'NFTokenCreateOffer',
      'Account': accountAddress,
      'NFTokenID': nftId,
      'Destination': destinationAddress,
      'Fee': '10',
    };
    tx['Amount'] = amountDrops ?? '0';
    return tx;
  }

  // 公開API: AcceptOffer用tx_jsonを構築（受取側が署名）
  Map<String, dynamic> buildAcceptOfferTxJson({
    required String accountAddress,
    required String offerId,
  }) {
    return {
      'TransactionType': 'NFTokenAcceptOffer',
      'Account': accountAddress,
      'SellOffer': offerId,
      'Fee': '10',
    };
  }

  // チェーン上の転送可否を確認（nft_infoを利用）
  Future<bool> isTransferable({required String nftId}) async {
    final info = await _client.call('nft_info', {
      'nft_id': nftId,
    });
    final flags = info['result']?['nft']?['Flags'] ?? info['result']?['nft']?['flags'] ?? 0;
    if (flags is int) {
      return (flags & _lsfTransferable) != 0;
    }
    return true; // 不明時は許容（後続で失敗する可能性あり）
  }

  // 直近で構築したバーン用tx_jsonプレビュー
  Map<String, dynamic>? _lastBurnTxPreview;
  Map<String, dynamic>? get lastBurnTxPreview => _lastBurnTxPreview;

  Map<String, dynamic> _buildBurnTxJson({
    required String accountAddress,
    required String nftId,
    String? ownerAddress,
  }) {
    return {
      'TransactionType': 'NFTokenBurn',
      'Account': accountAddress,
      'NFTokenID': nftId,
      if (ownerAddress != null && ownerAddress.isNotEmpty) 'Owner': ownerAddress,
      'Fee': '10',
    };
  }
}