// -------------------------------------------------------
// 目的・役割: XRPLutter SDKの内部/公開モデル定義。Walletセッション、アカウント情報、NFT操作の結果型などを保持する。
// 作成日: 2025/11/08
//
// 更新履歴:
// 2025/11/08 23:55 NftMetadataモデルを追加。
// 理由: メタデータの標準スキーマと柔軟拡張（custom）をサポートするため。
// 2025/11/08 23:59 追記: Hard SBT（NTT）採用に伴い、結果型・ドキュメントのコメントを補足（転送可否の扱い）。
// 理由: 仕様の明確化。
// 2025/11/09 12:58 変更: WalletProviderに主要プロバイダの定数（xumm/xaman/crossmark/gemwallet/walletconnect）を追加。
// 理由: README/仕様書のコード例と整合し、利用者が文字列を意識せずに標準プロバイダを指定できるようにするため。
// 2025/11/09 13:22 追加: 署名進捗イベント（SignProgressEvent/State）とキャンセル用トークン（CancelToken）。
// 理由: 進捗ステート/キャンセル/タイムアウトのイベントAPIをWalletConnectorレベルで扱うためのモデルを提供する。
// 2025/11/16 12:33 変更: WalletSession.addressを可変化。
// 理由: 署名承認後に確定したアドレスをセッションへ反映し、後続API（getAccountInfo等）が最新アドレスを返すようにするため。
// -------------------------------------------------------

class WalletProvider {
  const WalletProvider(this.name);
  final String name;

  // 主要プロバイダの定数
  static const xumm = WalletProvider('xumm');
  static const xaman = WalletProvider('xaman');
  static const crossmark = WalletProvider('crossmark');
  static const gemwallet = WalletProvider('gemwallet');
  static const walletconnect = WalletProvider('walletconnect');
}

class WalletSession {
  WalletSession({required this.address});
  String address;
}

class AccountInfo {
  AccountInfo({required this.address, required this.sequence});
  final String address;
  final int sequence;
}

class MintResult {
  MintResult({required this.transactionHash, required this.nftId});
  final String transactionHash;
  final String nftId;
}

class TransferResult {
  TransferResult({required this.transactionHash});
  final String transactionHash;
}

class BurnResult {
  BurnResult({required this.transactionHash});
  final String transactionHash;
}

class AccountNftsPage {
  AccountNftsPage({required this.items, this.marker});
  final List<Map<String, dynamic>> items;
  final String? marker;
}

class NftOfferList {
  NftOfferList({required this.sellOffers, required this.buyOffers});
  final List<Map<String, dynamic>> sellOffers;
  final List<Map<String, dynamic>> buyOffers;
}

class NftMetadata {
  NftMetadata({
    required this.name,
    required this.description,
    required this.image,
    this.externalUrl,
    this.animationUrl,
    this.attributes,
    this.custom,
  });

  final String name;
  final String description;
  final String image;
  final String? externalUrl;
  final String? animationUrl;
  final List<Map<String, dynamic>>? attributes;
  final Map<String, dynamic>? custom;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'name': name,
      'description': description,
      'image': image,
    };
    if (externalUrl != null) json['external_url'] = externalUrl;
    if (animationUrl != null) json['animation_url'] = animationUrl;
    if (attributes != null) json['attributes'] = attributes;
    if (custom != null) json['custom'] = custom;
    return json;
  }
}

/// 署名進捗の状態
enum SignProgressState {
  created,   // ペイロード生成済み（deeplink/QR提示可能）
  opened,    // ユーザーが署名画面を開いた（検出可能な場合）
  signed,    // 署名完了（tx_blob受領、またはtxHashの提供あり）
  submitted, // XRPLへ送信完了（txHash確定）
  rejected,  // ユーザーが拒否
  timeout,   // 署名がタイムアウト
  canceled,  // クライアント側でキャンセル
  error,     // エラー（詳細はmessage参照）
}

/// 署名進捗イベント（WalletConnectorがStreamで公開）
class SignProgressEvent {
  SignProgressEvent({
    required this.state,
    this.payloadId,
    this.deepLink,
    this.qrUrl,
    this.txHash,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final SignProgressState state;
  final String? payloadId;
  final String? deepLink;
  final String? qrUrl;
  final String? txHash;
  final String? message;
  final DateTime timestamp;
}

/// キャンセル用トークン（進行中の署名フローを停止）
class CancelToken {
  bool _canceled = false;
  bool get canceled => _canceled;
  void cancel() => _canceled = true;
}