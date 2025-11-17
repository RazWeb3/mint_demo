// -------------------------------------------------------
// 目的・役割: XRPLutter SDKの公開エントリポイント。ウォレット接続とNFT操作の高レベルAPIを提供する。
// 作成日: 2025/11/08
//
// 更新履歴:
// 2025/11/08 23:55 mintNftにminterAddressおよびsbt/transferableオプションを追加。
// 理由: 署名主体の明示指定とSBT（非転送）表現の柔軟性を高めるため。
// 2025/11/08 23:59 追記: Hard SBT（NTT）/通常NFTの使い分けを容易にするラッパーAPIを追加（mintRegularNft, mintNtt）。
// 理由: アプリ側での呼び出し簡便化と誤利用防止のため。
// 2025/11/09 00:12 mintNftでWalletConnectorからアカウントアドレスを取得し、NftService.mintへ受け渡すように変更。
// 理由: 非カストディアル運用での署名前トランザクション構築のため、署名者アドレスの明示が必要なため。
// 2025/11/09 00:25 変更: XRPLutter.mintNftがNftService.buildMintTxJsonでtx_jsonを構築し、WalletConnector.signAndSubmitで署名・送信するオーケストレーションに刷新。
// 理由: 非カストディアル運用の標準フロー（外部署名→submit）に合わせるため。
// 2025/11/09 11:22 変更: transferNftにSoft SBT運用補助（metadataJsonによる判定、warnIfSoftSbt/blockIfSoftSbt）を追加。
// 理由: メタデータベースのSoft SBT方針に基づき、アプリ内での送付時に警告/ブロックを可能にするため。
// 2025/11/09 12:58 追記: 公開APIの利便性向上のため、主要型のexportを追加（WalletConnector, WalletConnectorConfig, WalletProvider 等）。
// 理由: READMEのクイックスタート/プロキシ設定例でライブラリ単一importで完結するようにするため。
// 2025/11/13 15:40 追記: XRPLClientを公開exportに追加。
// 理由: デモ/アプリ側でXRPLClientを直接注入して接続再利用・性能調整できるようにするため。
// -------------------------------------------------------

library xrplutter;

import 'src/models.dart';
import 'src/wallet_connector.dart';
import 'src/nft_service.dart';
import 'src/metadata_utils.dart';
import 'src/xrpl_client.dart';
import 'src/xrpl_ws_client.dart';

// re-export public types for SDK consumers
export 'src/models.dart';
export 'src/wallet_connector.dart';
export 'src/nft_service.dart';
export 'src/metadata_utils.dart';
export 'src/wallet_config.dart';
export 'src/xrpl_client.dart';
export 'src/xrpl_ws_client.dart';

class XRPLutter {
  factory XRPLutter({WalletConnector? walletConnector, NftService? nftService, XRPLClient? client}) {
    final c = client ?? XRPLClient();
    final w = walletConnector ?? WalletConnector(client: c);
    final n = nftService ?? NftService(client: c);
    return XRPLutter._(c, w, n);
  }

  XRPLutter._(this._client, this._wallet, this._nft);

  final XRPLClient _client;
  final WalletConnector _wallet;
  final NftService _nft;

  // セッション/接続
  Future<WalletSession> connectWallet({required WalletProvider provider}) async {
    return _wallet.connect(provider: provider);
  }

  Future<void> disconnectWallet() async {
    await _wallet.disconnect();
  }

  Future<AccountInfo> getAccountInfo() async {
    return _wallet.getAccountInfo();
  }

  // NFT操作
  Future<MintResult> mintNft({
    required String metadataUri,
    int? taxon,
    int? transferFeeBps,
    Map<String, dynamic>? flags,
    String? minterAddress,
    bool? sbt,
    bool? transferable,
  }) async {
    final account = await _wallet.getAccountInfo();
    final txJson = _nft.buildMintTxJson(
      accountAddress: account.address,
      metadataUri: metadataUri,
      taxon: taxon,
      transferFeeBps: transferFeeBps,
      flags: flags,
      minterAddress: minterAddress,
      sbt: sbt,
      transferable: transferable,
    );
    final submit = await _wallet.signAndSubmit(txJson: txJson);
    final hash = submit['result']?['hash'] ?? 'dummyHash';
    return MintResult(transactionHash: hash, nftId: 'unknown');
  }

  /// 便利API: 通常NFTをミント（チェーンレベルで転送可能）
  Future<MintResult> mintRegularNft({
    required String metadataUri,
    int? taxon,
    int? transferFeeBps,
    Map<String, dynamic>? flags,
    String? minterAddress,
  }) async {
    return mintNft(
      metadataUri: metadataUri,
      taxon: taxon,
      transferFeeBps: transferFeeBps,
      flags: flags,
      minterAddress: minterAddress,
      transferable: true,
      sbt: null,
    );
  }

  /// 便利API: 非転送トークン（NTT/Hard SBT）をミント（チェーンレベルで転送不可）
  Future<MintResult> mintNtt({
    required String metadataUri,
    int? taxon,
    Map<String, dynamic>? flags,
    String? minterAddress,
  }) async {
    // Hard SBTではtransferFeeは設定不可（仕様上）
    return mintNft(
      metadataUri: metadataUri,
      taxon: taxon,
      transferFeeBps: null,
      flags: flags,
      minterAddress: minterAddress,
      transferable: false,
      sbt: null,
    );
  }

  /// 所有権移転の抽象API（内部ではOffer系トランザクションを使用する想定）
  Future<TransferResult> transferNft({
    required String nftId,
    required String destinationAddress,
    String? amountDrops,
    Map<String, dynamic>? metadataJson,
    bool warnIfSoftSbt = true,
    bool blockIfSoftSbt = false,
  }) async {
    // 事前チェック: 非転送トークン（NTT）ならユーザー間の移転は不可
    final transferable = await _nft.isTransferable(nftId: nftId);
    if (!transferable) {
      throw StateError('このNFTは非転送（NTT/Hard SBT）としてミントされているため、ユーザー間の移転はできません。');
    }
    // 運用補助: Soft SBT（メタデータ方針）に基づく警告/ブロック
    if (metadataJson != null && MetadataUtils.isSoftSbtJson(metadataJson)) {
      if (blockIfSoftSbt) {
        throw StateError('このNFTはSoft SBTとしてマークされています。アプリポリシーにより送付をブロックします。');
      } else if (warnIfSoftSbt) {
        print('[XRPLutter] Warning: Soft SBTフラグが付与されたNFTの送付です。アプリ外では転送可能であるためご注意ください。');
      }
    }
    final account = await _wallet.getAccountInfo();
    final txJson = _nft.buildCreateOfferTxJson(
      accountAddress: account.address,
      nftId: nftId,
      destinationAddress: destinationAddress,
      amountDrops: amountDrops,
    );
    final submit = await _wallet.signAndSubmit(txJson: txJson);
    final hash = submit['result']?['hash'] ?? 'dummyHash';
    // 注意: 実際の所有権移転はDestination側でのNFTokenAcceptOffer署名が必要（別フロー）。
    return TransferResult(transactionHash: hash);
  }

  Future<BurnResult> burnNft({required String nftId}) async {
    final account = await _wallet.getAccountInfo();
    final txJson = _nft.buildBurnTxJson(accountAddress: account.address, nftId: nftId);
    final submit = await _wallet.signAndSubmit(txJson: txJson);
    final hash = submit['result']?['hash'] ?? 'dummyHash';
    return BurnResult(transactionHash: hash);
  }

  Future<AccountNftsPage> listAccountNfts({
    required String account,
    int? limit,
    String? marker,
    String? issuer,
    int? taxon,
    bool transferableOnly = false,
  }) {
    return _nft.fetchAccountNfts(
      account: account,
      limit: limit,
      marker: marker,
      issuer: issuer,
      taxon: taxon,
      transferableOnly: transferableOnly,
    );
  }

  Future<NftOfferList> listNftOffers({required String nftId}) {
    return _nft.fetchNftOffers(nftId: nftId);
  }

  Future<Map<String, dynamic>> autofillTxJson(Map<String, dynamic> txJson) {
    return _client.autofillTxJson(txJson);
  }

  Future<Map<String, dynamic>> awaitTransaction(String hash, {Duration timeout = const Duration(seconds: 20), Duration pollInterval = const Duration(milliseconds: 800)}) {
    return _client.awaitTransaction(hash, timeout: timeout, pollInterval: pollInterval);
  }

  XRPLWebSocketClient createWsClient({String? endpoint}) {
    return XRPLWebSocketClient(endpoint: endpoint);
  }
}
