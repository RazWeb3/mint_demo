// -------------------------------------------------------
// 目的・役割: WalletConnectorの設定値（プロバイダ別の連携設定、タイムアウト、ポーリング間隔など）を管理する。
// 作成日: 2025/11/09
//
// 更新履歴:
// 2025/11/09 13:24 変更: Crossmark/GemWallet/WalletConnectのベースURL設定項目を追加。
// 理由: クリエイターが使いたいウォレットだけ個別URLを設定できるBYOS設計を明確化するため。
// 2025/11/09 15:45 追記: Web拡張の送信方式制御（webSubmitByExtension）と署名前のアドレス整合チェック（verifyAddressBeforeSign）を追加。
// 理由: 実拡張の仕様差（拡張側送信かSDK側送信か）に柔軟対応し、事前のアカウント一致検証を任意で行えるようにするため。
// 2025/11/16 13:15 追記: 観測キーのログ出力制御（logObservedKeys）を追加。HTTPタイムアウトは構成値（httpTimeout）を統一使用。
// 理由: 高頻度ポーリング時の軽量化と運用制御を可能にするため。
// -------------------------------------------------------

class WalletConnectorConfig {
  const WalletConnectorConfig({
    this.xamanProxyBaseUrl,
    this.crossmarkProxyBaseUrl,
    this.gemWalletProxyBaseUrl,
    this.walletConnectProxyBaseUrl,
    this.jwtBearerToken,
    this.signingTimeout = const Duration(seconds: 90),
    this.pollingInterval = const Duration(seconds: 2),
    this.httpTimeout = const Duration(seconds: 10),
    this.webSubmitByExtension = true,
    this.verifyAddressBeforeSign = false,
    this.disallowPrivateProxyHosts = false,
    this.logObservedKeys = true,
  });

  /// Xaman/XUMM連携用のバックエンドプロキシのベースURL
  /// - 推奨: XUMMのAPIキー/シークレットはバックエンド管理とし、SDKはこのプロキシを呼び出す
  final Uri? xamanProxyBaseUrl;

  /// Crossmark連携用のベースURL（必要な場合に設定）
  final Uri? crossmarkProxyBaseUrl;

  /// GemWallet連携用のベースURL（必要な場合に設定）
  final Uri? gemWalletProxyBaseUrl;

  /// WalletConnect連携用のベースURL（必要な場合に設定）
  final Uri? walletConnectProxyBaseUrl;

  final String? jwtBearerToken;

  /// 署名待機のタイムアウト（ユーザー操作含む）
  final Duration signingTimeout;

  /// 署名結果ポーリングの間隔（XUMMペイロードステータス取得など）
  final Duration pollingInterval;

  /// プロキシへのHTTP呼び出しのタイムアウト
  final Duration httpTimeout;

  /// Web拡張が署名後にそのままXRPLへsubmitするか（true）、SDK側でsubmitするか（false）を制御
  /// - true: 拡張からtxHashが返りやすい。false: tx_blobが返る想定でSDK側がsubmitする
  final bool webSubmitByExtension;

  /// 署名前にウォレット拡張からアドレスを取得して、セッションアドレスと一致するか検証するか
  /// - true: 不一致なら SignProgressState.error を通知して中断
  /// - false: 検証をスキップ（拡張がアドレス取得を提供しない場合や、複数アカウント運用時に有効）
  final bool verifyAddressBeforeSign;

  /// プライベート/リンクローカルなプロキシホストを拒否するか（10.x, 192.168.x, 172.16-31.x, 169.254.x, localhost, 127.0.0.1）
  /// - false: 開発用途で許可（既定）
  /// - true: 本番想定で拒否（安全性向上）
  final bool disallowPrivateProxyHosts;

  /// ステータス/詳細の観測キー（keys=）ログ出力を有効にするか（既定true）
  final bool logObservedKeys;
}
