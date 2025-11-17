<!--
目的・役割: XRPLutter NFT Kit SDKの技術仕様書。公開API、内部構成、データモデル、フロー、セキュリティ、テスト方針を定義する最新版の設計情報。
作成日: 2025/11/08
 
 更新履歴:
 2025/11/08 23:58 変更: mintNftにminterAddress/sbt/transferableを追記。Metadata/StorageProvider/SBTポリシーの記述を追加。
 理由: ユーザー要望（ミンター切替・SBT導入・柔軟ストレージ/メタデータ）への仕様反映。
 2025/11/08 23:59 変更: SBTの定義を更新。XRPLチェーンの非転送フラグ（tfTransferable）による"Hard SBT/NTT"を明記し、mintNft.transferableの意味を「チェーンフラグ制御」に更新。Soft SBT（メタデータ/SDKポリシー）との両立を追記。
 理由: XRPL公式仕様（XLS-20/NFTokenMint）でtfTransferableフラグが提供されているため、誤解を排し正確な仕様に修正。
 2025/11/08 23:59 追記: 便利API（mintRegularNft/mintNtt）を追加し、アプリ内の使い分けを容易化。非カストディアル運用で受取側の毎回署名が必要である旨を明記。
 理由: 議事録の合意（通常NFT主体＋SBTも発行可能、毎回署名）を仕様へ反映。
 2025/11/09 00:12 追記: Soft SBTは初期リリースでは「保留」とする旨を明記。NFTokenMintのtfBurnable設定時のみ発行者バーン許可である点を明記。NftServiceで署名前tx_jsonを構築する開始実装（URIのHex化等）を反映。
 理由: ユーザー要望（Soft SBT保留、tfBurnableの重要性）とSDK内部の着手状況を最新化するため。
 2025/11/09 12:00 追記: NftServiceにbuildCreateOfferTxJson/buildAcceptOfferTxJson、buildBurnTxJsonを追加し、XRPLutter.transferNft/burnNftがWalletConnector.signAndSubmitで非カストディアル署名・送信を行う設計を明文化。isTransferable（nft_infoによるlsfTransferable判定）を仕様に追加。
 理由: 実装の進捗（オーケストレーションのリファクタリングと事前チェックの導入）を最新仕様へ反映するため。
 2025/11/09 12:37 追記: Soft SBTの最小サポート（メタデータ補助: custom.sbt=true付与、判定ヘルパー）を追加。UI/SDKによる転送抑止は非強制（任意）とし、将来拡張で検討。
 理由: アプリ内限定の非転送ポリシーを柔軟に付与できるようにするため（チェーン非転送と両立）。
2025/11/09 12:45 変更: XRPLutter.transferNftにSoft SBT運用補助を追加（`metadataJson`, `warnIfSoftSbt`, `blockIfSoftSbt`）。
理由: メタデータ方針に基づき、アプリ内での送付時に警告/ブロックを可能にするため（任意設定、デフォルトは警告有効・ブロック無効）。
2025/11/09 12:58 変更: WalletConnectorにマルチプロバイダ対応のアダプタ構造を導入（Xaman/Crossmark/GemWallet/WalletConnect）。Xaman連携はバックエンドプロキシ方式を推奨。
理由: 普及率の高いウォレットから順次対応し、秘密鍵非保持と安全なキー管理を両立するため。
2025/11/09 13:03 追記: 公開エントリポイント（`lib/xrplutter.dart`）が主要型をexportする方針を明記（WalletConnector, WalletConnectorConfig, WalletProvider 等）。
理由: READMEのコード例をライブラリ単一importで完結させ、開発者体験を改善するため。
2025/11/09 13:28 追記: WalletConnectorの進捗イベントAPI（SignProgressEvent/State）とキャンセル制御（CancelToken）を追加。WalletConnectorConfigにCrossmark/GemWallet/WalletConnectのベースURLを拡張。
理由: 進捗ステート/キャンセル/タイムアウトのイベントAPI要求への対応と、BYOS設計でウォレット別URLを任意設定できるようにするため。
2025/11/09 13:42 追記: マネージドプロキシ・オプション（有料）の概要と、ウォレット別URLフォルダ＋v1のエンドポイント設計を章として追加。
理由: 議事録の合意事項（BYOS前提＋オプション提供）とURL設計ルール（/xumm/v1/ 等）を仕様に明記して整合性を担保するため。
2025/11/09 15:50 追記: WalletConnectorConfigに `webSubmitByExtension` と `verifyAddressBeforeSign` を追加。Crossmark/GemWallet連携における送信方式（拡張側submit/SDK側submit）と事前アドレス検証の挙動を明文化。
理由: 実拡張APIの差異に柔軟対応し、検証を任意化するための設定を仕様へ反映。
2025/11/10 12:25 追記: CrossmarkのWebインタロップ呼び出し優先順位（async.signAndWait→sync.sign+api.awaitRequest/sync.getResponse→api.request+awaitRequest）と、結果の正規化（txHash/hash/txid/tx_blob/uuid等の代表キー抽出）を明記。
理由: 実機観測に基づく正しい入口の確立と、SDK側の安定動作のため。
2025/11/10 11:10 変更: Crossmark/GemWalletのWebインタロップ待機タイムアウトを `WalletConnectorConfig.signingTimeout` に統一。
理由: 固定30秒ではユーザー操作時間により早期タイムアウトが発生し得るため、設定値で柔軟に制御できるよう仕様へ反映。
2025/11/10 16:20 追記: GemWalletのWebインタロップ呼び出し優先順位をCrossmark同等のパターンへ統一（async/sync/api/旧来/xrpl名前空間の多段フォールバック）。戻り値正規化（txHash/hash/txid/tx_blob/signed/rejected/error/payloadId/uuid等）を仕様へ明示。
理由: 拡張ごとのAPI配置差異に強耐性で対応し、SDKの相互運用性を高めるため。
2025/11/10 16:22 追記: デモアプリ（WalletConnector Demo）にSigning Timeoutスライダーを追加し、`WalletConnectorConfig.signingTimeout` をUIから動的変更可能にした（初期値45秒推奨、既定値90秒）。
理由: 実環境の署名所要時間に合わせたチューニングと、再現性の高い検証を行うため。
2025/11/10 16:35 追記: タイムアウト時の拡張UI挙動を明記（SDKのタイムアウトは拡張ウィンドウを閉じない）。推奨運用（手動で閉じる/無視して次の署名要求へ進む/スライダーでタイムアウト延長）を追記。
理由: 実機でタイムアウト後も拡張側UIが残るケースがあり、正しい運用手順を仕様に明示するため。
2025/11/10 19:26 追記: デモUIに WalletConnect Proxy Base URL 入力欄を追加し、SDKへ設定を渡せるようにした。SDK側はベースURL連結を Uri.resolve へ統一し、末尾スラッシュ有無に依存しない安全なURL組み立てに改善。
理由: マネージド/自前プロキシの検証利便性を高め、設定記述揺れによるURL不整合を防ぐため。
2025/11/13 20:45 追記: クリエイター導入チェックリストを追加（Proxy環境変数、JWT運用、SDK設定、検証・トラブルシュート）。
理由: SDK公開後に迷わず本番フローを構築できるよう手順を整備。
2025/11/13 21:10 追記: JWT必須化と短寿命exp検証、URLスキーム検証（http/httpsのみ）、進捗イベントopenedの重複抑制、例外型一覧（概念）を明記。
理由: 提出前の最終仕上げとして、安定性とセキュリティ、ドキュメント整合性を高めるため。
2025/11/16 12:30 変更: XamanフローのSignIn対応を仕様へ反映。送信を伴わない署名時は`payload/details/{payloadId}`から`response.account`等を抽出してアドレス確定し、進捗`signed | account=`を出力、戻り値へ`result.account`を含める。
理由: Xaman/BYOS差異により`txHash/tx_blob`が存在しないケースでアドレス未確定となる問題の解消と診断性向上。
2025/11/16 12:31 変更: ステータスからのアカウント抽出順序（`status.account → status.response.account → status.meta.account`）を仕様に明記。検出時は`session.address`へ反映し、進捗`signed`に`account=`を出力する。
理由: 環境差でトップレベルに`account`が存在しないケースへの耐性強化。
2025/11/16 12:32 変更: ペイロード作成失敗時の進捗通知（`SignProgressState.error`で`Create failed: HTTP ...`または`Create request failed: ...`）を仕様へ追加。
理由: 作成失敗時にUIが待機継続しないよう明確化。
2025/11/16 12:35 変更: バーン仕様の誤記を修正。所有者は常時バーン可能、発行者/認可ミンターはミント時`tfBurnable`設定済みのNFTに限り`Owner`指定でバーン可能。SDKの`buildBurnTxJson`は現状所有者向け（`Owner`未指定）であり、将来`ownerAddress`オプションを追加して発行者バーンをサポート予定。
理由: XRPL公式仕様（NFTokenBurn/lsfBurnable）へ整合。
2025/11/16 12:50 追記: WalletConnectorConfigに`disallowPrivateProxyHosts`を追加し、プライベート/リンクローカルホスト（10.x/192.168.x/172.16–31.x/169.254.x/localhost/127.0.0.1）を拒否可能（既定false）。
理由: SSRF耐性・本番運用の安全性向上のため。
2025/11/16 12:51 変更: WalletConnectの返却オブジェクトでも`deepLink`をサニタイズ（許可スキームのみ）。
理由: UI取り扱い時の不正スキーム混入回避の強化。
2025/11/16 13:16 変更: HTTPタイムアウトを構成値（httpTimeout）へ統一。観測キー（keys=）の計算は設定（logObservedKeys）で制御可能とした。
理由: 高頻度ポーリング時の効率化と運用制御性の向上。
-->

# XRPLutter NFT Kit SDK 仕様書

本仕様書は、Flutter向け「XRPLutter NFT Kit SDK」の最新の技術設計を示します。用語や設計は一般公開を前提としており、広く再利用可能なコンポーネントとして提供します。

## 1. アーキテクチャ概要
- レイヤ構成:
  - WalletConnector層: 外部ウォレット（例:Xumm）と接続/署名連携を担う
  - XRPLClient層: XRPLノード（JSON-RPC/WebSocket/API）へのリクエスト送信を担う
  - NftService層: ミント/送付/バーン等のNFT操作を高レベルAPIとして提供
  - Model層: トランザクション/結果/エラーなどの型定義

## 2. 公開API（Dart）
名前や型は初期案であり、実装時にDartの慣用表現に合わせ微調整します。

```dart
class XRPLutter {
  // セッション/接続
  Future<WalletSession> connectWallet({required WalletProvider provider});
  Future<void> disconnectWallet();
  Future<AccountInfo> getAccountInfo();

  // NFT操作
  Future<MintResult> mintNft({
    required String metadataUri,
    int? taxon,
    int? transferFeeBps,
    Map<String, dynamic>? flags,
    String? minterAddress, // 署名主体の明示指定（要権限）
    bool? sbt,             // Soft SBT（アプリ/SDKポリシー）の意図。メタデータにsbt=trueを付与し、UI/SDKで転送操作を抑止。
    bool? transferable,    // チェーンレベル転送可否。true=通常NFT（tfTransferable有効）、false=NTT（非転送: tfTransferable無効）
  });

  // 便利API: 通常NFTをミント（転送可能）
  Future<MintResult> mintRegularNft({
    required String metadataUri,
    int? taxon,
    int? transferFeeBps,
    Map<String, dynamic>? flags,
    String? minterAddress,
  });

  // 便利API: 非転送トークン（NTT/Hard SBT）をミント（転送不可）
  Future<MintResult> mintNtt({
    required String metadataUri,
    int? taxon,
    Map<String, dynamic>? flags,
    String? minterAddress,
  });

  /// 所有権移転の抽象API（内部ではOffer系トランザクションを使用）
  Future<TransferResult> transferNft({
    required String nftId,
    required String destinationAddress,
    String? amountDrops, // ギフトはnull/"0"、価格管理はアプリ側で
    Map<String, dynamic>? metadataJson, // Soft SBT判定のためのメタデータ（custom.sbt=true等）
    bool warnIfSoftSbt = true,          // Soft SBT時に警告ログ出力（デフォルト有効）
    bool blockIfSoftSbt = false,        // Soft SBT時に送付をブロック（デフォルト無効）
  });

  Future<BurnResult> burnNft({
    required String nftId,
  });
}
```

### 2.1 戻り値モデル（例）
```dart
class WalletSession { String address; String provider; }
class AccountInfo { String address; int sequence; int reserve; }
class MintResult { String nftId; String txHash; }
class TransferResult { String offerId; String txHash; }
class BurnResult { String txHash; }
```

補足（公開エントリポイントのexport）:
- `lib/xrplutter.dart` は、`WalletConnector`, `WalletConnectorConfig`, `WalletProvider` など主要型を再エクスポートします。これにより、利用者は `import 'package:xrplutter_sdk/xrplutter.dart';` の単一importでSDKの公開型を利用できます。

## 3. 内部仕様
### 3.1 XRPLClient
- JSON-RPC/WebSocketにて以下のメソッドを利用（例）:
  - submit, tx, account_info, nft_info など
- HTTP(S)通信時はタイムアウト/リトライを実装（指数バックオフ）

### 3.2 NftService
- ミント: NFTokenMintを生成
  - 必須: metadataUri
  - 任意: taxon, transferFee（bps）, flags
  - フラグ: transferable=true の場合 tfTransferable を設定。transferable=false（NTT）の場合は tfTransferable 未設定。
  - 注意: TransferFeeを設定する場合は tfTransferable が必須（仕様）。NTTでは TransferFee を設定できない。
  - flagsのキー例: `burnable`（tfBurnable）, `onlyXrp`（tfOnlyXRP）, `mutable`（tfMutable）
  - 署名前のtx_json構築: URIはHexへエンコードして`URI`に設定。`Issuer`は「代理発行」時に指定（NFTokenMinter設定が必要）。
  - 公開ビルダーAPI: `buildMintTxJson({...})` を提供し、外部ウォレットでの署名前にtx_jsonを構築・検証（TransferFee範囲とtfTransferable整合）する。
- 送付（所有権移転）:
  - NFTokenCreateOfferで目的地（destination）を指定
  - ギフト: 価格0（amount=0）
  - 売買: 価格あり（amount>0）だが価格管理/通貨はアプリ側ロジック
  - NFTokenAcceptOfferは受取側が署名して実行（受取UXはサンプルアプリで提示）
  - 非カストディアル運用では、受取のたびに受取側の署名が必要（毎回）。
  - 公開ビルダーAPI: `buildCreateOfferTxJson({...})`（送付側）, `buildAcceptOfferTxJson({...})`（受取側）を提供。
  - 事前チェック: `isTransferable(nftId)` を提供。`nft_info`からNFTokenのFlagsを取得し、`lsfTransferable`有無でユーザー間移転可否を判定。
  - Soft SBT運用補助: `XRPLutter.transferNft` に `metadataJson` を渡すと `MetadataUtils.isSoftSbtJson` により判定し、`warnIfSoftSbt`（ログ警告）/`blockIfSoftSbt`（例外で送付抑止）を選択可能（任意設定、デフォルトは警告有効・ブロック無効）。
  - バーン: NFTokenBurnを生成
    - 所有者は常時バーン可能。
    - 発行者/認可ミンターは、当該NFTがミント時に`tfBurnable`フラグで作成されている場合のみバーン可能。その際はNFTokenBurnに`Owner`（現在の所有者アドレス）を明示指定する。
    - 注意: `tfBurnable`はミント時のトランザクションフラグで、NFTオブジェクトの`lsfBurnable`プロパティに反映される（不変）。
  - 公開ビルダーAPI: `buildBurnTxJson({...})` を提供（外部署名前のtx_json）。所有者向け（`Owner`省略）のほか、発行者/認可ミンター向けに`ownerAddress`オプション（NFTokenBurn.Owner）で現在の所有者アドレスを指定可能。
  - デバッグ/確認用プレビュー: 直近構築tx_jsonを`lastMintTxPreview`/`lastBurnTxPreview`として参照可能（SDK内部フィールド）。

### 3.3 WalletConnector
- 外部ウォレットへ署名要求を送る（Deep Link/QR等）
- SDKは秘密鍵を保持しない
- 署名拒否/タイムアウトをハンドリング
  - 署名API:
    - `Future<Map<String, dynamic>> signAndSubmit({required Map<String, dynamic> txJson})`
    - 署名前のtx_jsonを受け取り、外部ウォレットで署名→`tx_blob`送信までを仲介。
  - オーケストレーション: XRPLutterの`mintNft/transferNft/burnNft`は、各NftServiceビルダーでtx_jsonを構築し、WalletConnectorの`signAndSubmit`へ渡す流れ。

#### マルチプロバイダ対応（アダプタ構造）
- 対応方針（優先順）: Xaman（旧XUMM）→ Crossmark → GemWallet → WalletConnect v2（可否調査）
- アダプタIF（概念）:
  - `WalletAdapter.signAndSubmit({txJson, session, config, client})`
  - `config`: `WalletConnectorConfig`（XamanプロキシURL、署名タイムアウト、ポーリング間隔）
  - `client`: `XRPLClient`（submitやtx取得に利用）

#### 進捗イベントAPI（SignProgressEvent）とキャンセル
- WalletConnectorは進捗イベントをStreamで公開: `Stream<SignProgressEvent> progressStream`
- 主要ステート（SignProgressState）:
  - created（ペイロード生成）
  - opened（ユーザーが署名画面を開いた）
  - signed（署名完了）
  - submitted（XRPL送信完了）
  - rejected（拒否）
  - timeout（タイムアウト）
  - canceled（クライアント側キャンセル）
  - error（エラー）
- キャンセル制御: `CancelToken` を内部管理。`cancelSigning()` を呼ぶと、進行中フローを停止し `canceled` イベントを発火。
- 推奨ポーリング: 初期2秒、opened以降は3〜5秒のバックオフ。レート制限とSLOに応じて調整可。
 - 重複抑制: `opened`は一度のみ通知する（SDK側で重複発火を抑止）

#### Xaman（旧XUMM）連携（推奨: バックエンドプロキシ方式）
- 目的: XUMMのAPIキー/シークレットをクライアントへ置かない
- フロー（UX最適案）:
  1) プロキシへペイロード作成（tx_json渡し）
  2) 戻り値のdeeplink/QR URLでユーザーへ署名提示（UIはアプリ側）
  3) プロキシ経由で署名結果をポーリング（accepted/rejected/timeout）
  4) 署名済みならtxHash返却（プロキシがsubmit済み）／未送信なら`tx_blob`を受領し`XRPLClient.submit`で送信

イベント発火例（Xamanアダプタ）
- created: payloadId, deepLink/qrUrl を含む
- opened: ステータスに基づき検出可能な場合
- signed: 署名完了時（`account=`を含める）。SignIn時は送信なしのため、`payload/details/{payloadId}`から`response.account`等でアドレス確定し、戻り値へ`result.account`を返す。
- submitted: txHash確定時（プロキシsubmit／クライアントsubmit）
- rejected/timeout/error: 各条件で発火

#### Crossmark/GemWallet（Web拡張）連携
- Flutter WebのJS interopで拡張へ署名要求→結果受領→XRPL送信
- 未インストール/拒否/互換性エラーのハンドリング
 - 送信方式の選択（`WalletConnectorConfig.webSubmitByExtension`）:
  - `true`（デフォルト）: 拡張が署名後にXRPLへsubmit。SDKは結果から`txHash`を受領して `submitted` を発火。
  - `false`: 拡張は `tx_blob` を返却する想定。SDK側で `XRPLClient.submit` を実行し、成功時に `submitted` を発火。
- 事前アドレス検証（`WalletConnectorConfig.verifyAddressBeforeSign`）:
  - `true`: 署名前に拡張から現在アドレスを取得し、セッションの`address`と一致しない場合は `error` を発火して中断。
  - `false`（デフォルト）: アドレス検証をスキップ（拡張がアドレス取得APIを提供しない場合や、複数アカウント運用時に適する）。
 - 待機タイムアウト: Crossmark/GemWalletの署名待機は `WalletConnectorConfig.signingTimeout` を用いて制御する（デフォルト90秒）。
   - ユーザーがUIで承認しない／拡張が応答しない場合は `timeout` イベントを発火し、内部的に `SignTimeout` 例外をスロー。
   - デモアプリの実装では、`SignTimeout` を catch した際に `canceled` イベント（messageに `Error: Bad state: SignTimeout`）も追加で発火するため、`timeout` と `canceled` の両方がログに並ぶことがある。これはUI伝達のための重複通知であり、仕様上の不整合ではない。
   - 補足（拡張UIの扱い）: SDKのタイムアウトは拡張のウィンドウ/パネルを強制的に閉じません。拡張UIが残っている場合は、ユーザーが手動で閉じるか、そのUIを無視して次の署名要求へ進んでも問題ありません（次の要求は新しいペイロード/UUIDで処理されます）。
     - 推奨運用: 1) 手動で拡張UIを閉じる、2) デモの「Cancel Signing」を押してローカル状態を整理、3) Signing timeoutスライダーで必要に応じて値を延長（例: 60〜90秒）、4) 署名を再試行。
     - 留意点: 「Cancel Signing」はSDK側の待機を停止するだけで、拡張にキャンセル要求を送るわけではありません。拡張側にキャンセルAPIがある場合でも、互換性のため現状は呼び出していません。
 - Crossmark呼び出しの優先順位（実機準拠）:
   1) `window.crossmark.async.signAndWait(txJson, {submit})` を最優先で試行（存在しない場合は `async.signAndSubmit` も許容）。
   2) `window.crossmark.sync.sign(txJson, {submit})` の返すID/UUIDに対して、`window.crossmark.api.awaitRequest(id)` または `window.crossmark.sync.getResponse(id)` で結果取得。
   3) `window.crossmark.api.request(...)` を複数のシグネチャで試行し、取得した `request.uuid`（または `uuid`/文字列）に対して `api.awaitRequest(uuid)` で結果を待機。
   4) 旧来のトップレベル `sign/signAndSubmit` や `xrpl.*` 名前空間は最終フォールバックとして試行。
 - 戻り値の正規化: 結果オブジェクトから代表キーを抽出（トップレベル/ネスト）し、`txHash/hash/txid/tx_blob/txBlob/signedTransaction/rejected/error/payloadId/uuid/opened/accepted/submitted` をSDK側で解釈可能にする。

 - GemWallet呼び出しの優先順位（Crossmark同等の統一パターン）:
   1) `window.gemWallet.async.signAndWait(txJson, {submit})` を最優先で試行（存在しない場合は `async.signAndSubmit` も許容）。
   2) `window.gemWallet.sync.sign(txJson, {submit})` の返すID/UUIDに対して、`window.gemWallet.api.awaitRequest(id)` または `window.gemWallet.sync.getResponse(id)` で結果取得。
   3) `window.gemWallet.api.request(...)` を複数のシグネチャで試行し、取得した `request.uuid`（または `uuid`/文字列）に対して `api.awaitRequest(uuid)` で結果を待機。
   4) 旧来のトップレベル `sign/signAndSubmit` や `gemwallet.xrpl.*` 名前空間は最終フォールバックとして試行（`window.gemWallet.xrpl.request(...)` などのXRPL名前空間も許容）。
   5) 戻り値の正規化はCrossmarkと同様の規則を適用し、`txHash/hash/txid/tx_blob/signed/rejected/error/payloadId/uuid` 等の代表キーを抽出する。ネスト（`result/response/request`）も吸収する。

 - デモアプリ（WalletConnector Demo）のUI:
   - 署名タイムアウトはスライダーで動的調整可能。`WalletConnectorConfig.signingTimeout` に即時反映され、拡張の署名待機に適用される。
   - 推奨初期値は45秒。検証環境やユーザー操作に応じて増減させる。
    - WalletConnect Proxy Base URL を入力可能（任意）。例: `http://localhost:53211/walletconnect/v1/`。末尾スラッシュ有無はどちらでも可（SDKが `Uri.resolve` で安全に連結）。

#### WalletConnect v2（調査→最小骨子／スケルトン）
- XRPL対応ウォレットのサポート状況に依存。可能ならセッション確立→署名→送信のひな形を提供。
- 2025/11/10 追記（スケルトン実装）:
  - SDKの WalletConnectAdapter に、以下のイベントフローを持つスタブ実装を追加。
    - created: WalletConnect v2 のペアリングURI（`wc:<topic>@2?relay-protocol=irn&symKey=<key>`）を生成して、イベントに deepLink として通知。デモUIのDeepLinkパネルでQR表示・コピーが可能。
    - opened: ユーザーがウォレットアプリを開いた想定でイベント通知（スタブ）。
    - signed: 署名完了のイベント通知（スタブ）。
    - submitted: XRPL送信完了のイベント通知（スタブ）。戻り値には `dummyHash` を格納。
  - 今後の拡張: `walletConnectProxyBaseUrl` を用いるバックエンド連携（セッション生成・リクエスト・ステータス取得・tx_blob/tx_hash受領）を実装予定。
  - 制約: 本段階はスタブであり、実ウォレットとのハンドシェイクは行わない。UI/UXの確認用。

プロキシ連携（BYOS）骨子（WalletConnect v2）:
- ベースURL例: `/walletconnect/v1/`
- セッション生成: `POST session/create`
  - 入力: `{ tx_json: {...} }`
  - 出力: `{ payloadId|sessionId|topic, pairingUri, qrUrl? }`
  - 説明: WalletConnect v2のペアリングURIを生成し、UIでQR/DeepLink表示可能とする。
- ステータス取得: `GET session/status/{payloadId|sessionId|topic}`
  - 出力（例）: `{ opened: boolean, signed: boolean, rejected: boolean, txHash?: string, tx_blob?: string }`
  - 説明: 署名進捗をポーリング。`txHash`があればプロキシ送信済み、`tx_blob`があればSDK側で`submit`実行。
- エラー方針: HTTP非200はリトライ（pollingInterval）／タイムアウトは `signingTimeout` 満了で SignTimeout。
- フォールバック: プロキシ未設定/失敗時はローカルで wc: ペアリングURIを生成し、スタブイベントでUI/UXを確認できるようにする。
  - 仕様補足（URL連結）: SDKは `WalletConnectorConfig.walletConnectProxyBaseUrl` をベースとして、`Uri.resolve('session/create')` 等の相対連結でエンドポイントを呼び出す。`http://.../walletconnect/v1` と `http://.../walletconnect/v1/` のどちらでも同等に動作する。

#### 設定: WalletConnectorConfig（例）
```dart
class WalletConnectorConfig {
  final Uri? xamanProxyBaseUrl; // バックエンドプロキシのURL（Xaman）
  final Uri? crossmarkProxyBaseUrl; // Crossmark（必要時）
  final Uri? gemWalletProxyBaseUrl; // GemWallet（必要時）
  final Uri? walletConnectProxyBaseUrl; // WalletConnect（必要時）
  final Duration httpTimeout; // HTTP呼び出しのタイムアウト（作成/ステータス/詳細取得に適用）
  final Duration signingTimeout; // 署名待機のタイムアウト
  final Duration pollingInterval; // ステータス取得の間隔
  final bool webSubmitByExtension; // Web拡張が署名後にsubmitするか（true）/SDK側でsubmitするか（false）
  final bool verifyAddressBeforeSign; // 署名前に拡張の現在アドレスとセッションアドレスを照合するか
  final bool disallowPrivateProxyHosts; // プライベート/リンクローカルホストのプロキシを拒否するか（既定false）
  final bool logObservedKeys; // ステータス/詳細の観測キー(keys=)ログ出力を有効にするか（既定true）
}

### 3.6 マネージドプロキシ・オプション（有料）
- 目的: 自サーバ準備が難しい利用者向けに、短期イベント／月次サブスク／従量課金のいずれかでプロキシを提供。
- 提供範囲: `POST /payload/create` と `GET /payload/status/{payloadId}` を基本とし、送信責務はA/Bを選択可能。
  - A案: サーバ側でsubmit実行→`txHash`返却（推奨。クライアント側はハッシュ確定まで待機）
  - B案: `tx_blob`返却→クライアントが`XRPLClient.submit`実行（アプリ側で送信責務を持つ）
- セキュリティ/認証: 短命JWT（数分）＋スコープ（create/status）、CORSホワイトリスト、レート制限、WAF を推奨。
- レート制限と計測: `create`/`status`/`submit`の呼出数、同時セッション数、ポーリング間隔を計測し課金・SLO管理に活用。

### 3.7 エンドポイント設計（ウォレット別フォルダ＋v1）
- ルール: ウォレット別にURLフォルダを分け、APIのバージョンを付与する。
  - 例: `/xumm/v1/`, `/crossmark/v1/`, `/gemwallet/v1/`, `/walletconnect/v1/`
- 代表エンドポイント（Xaman/XUMM）:
  - `POST /xumm/v1/payload/create` （body: `{ tx_json: {...} }`）
  - `GET  /xumm/v1/payload/status/{payloadId}` （返却: `{ opened?, signed?, rejected?, txHash? | tx_blob? }`）
- BYOS: SDKの`WalletConnectorConfig`はベースURL（例: `http://your.domain/xumm/v1/`）を受け取り、`payload/*` を相対で叩く。

仕様書更新有無: 更新しました（WalletConnect v2 スケルトン、プロキシ連携骨子、デモUIの「Connect WalletConnect」ボタン追加を反映、非破壊改善の反映）。
補足更新: デモUIの WalletConnect Proxy Base URL 入力欄追加、SDKのURL連結方式（Uri.resolve）に加え、`disallowPrivateProxyHosts`（既定false）とWalletConnect返却`deepLink`のサニタイズ適用を追記しました。
```

### 3.4 メタデータとストレージ（Metadata/StorageProvider）
- メタデータは推奨スキーマ（`name`, `description`, `image`, `external_url`, `attributes`, `animation_url`, `custom`）を示しつつ、自由拡張を許容。
- 型付きモデル `NftMetadata` を提供（`custom`で任意拡張）。同時に `Map<String, dynamic>` をそのまま渡せる柔軟APIも許可。
- ストレージは抽象インターフェース `StorageProvider` を介して扱う。
  - `uploadAsset(bytes, filename?, mimeType?) -> imageUri`
  - `uploadJson(json, filename?) -> metadataUri`
  - 実装例: `IpfsStorageProvider`, `HttpStorageProvider`（自社サーバー対応）
- SDKはURIをNFTokenMintの`URI`に設定（バイト列へエンコード）。

### 3.5 SBT（Soulbound Token）/ 非転送トークン（NTT）

- 用語整理:
  - Hard SBT（NTT: Non-Transferable Token）: チェーンレベルで転送不可。XRPLのNFTokenMintでtfTransferableフラグを無効（未設定）としてミントすることで達成。ミント後はNFTokenオブジェクトにlsfTransferableが付与されず、ユーザー間の転送ができません（ただし「発行者⇔所有者」間の直接移転は制限の対象外）。
  - Soft SBT: メタデータやSDK/UIポリシーにより転送を抑止。外部ツールでは転送できてしまう可能性があるため、アプリ内限定の運用に適します。

- SDKの挙動:
  - `mintNft.transferable`: チェーンフラグを制御。`true`=通常NFT（tfTransferable設定）、`false`=NTT（tfTransferable未設定）。
  - Soft SBT（最小サポート）: メタデータ補助として `MetadataUtils.addSoftSbtFlag(json)` を提供し、`custom.sbt=true`（トップレベル `sbt=true` も許容）を付与可能。UI/SDKによる転送抑止はデフォルト非強制（任意）。
  - 併用例: `MetadataUtils.addSoftSbtFlag(json)` でSoft SBT意図を付与しつつ、`transferable=false`でHard SBT（チェーン制御）を採用可能。

- 解除ポリシー:
  - Soft SBTのみの場合: メタデータとアプリ設定の更新で解除可能（URIがHTTP/IPNS等の可変参照であることを推奨）。
  - Hard SBT（NTT）の場合: チェーンフラグは不変のため、解除には burn→re-mint が必要（新たなNFTIDになります）。

- 参考（XRPL公式仕様）:
  - NFTokenMintのFlagsに`tfTransferable`（0x00000008）。未設定でミントすると非転送トークン（NTT）になり、ユーザー間では転送不可。発行者へ／からの移転のみ許容。
  - TransferFeeを設定する場合は`tfTransferable`が必須（XRPLライブラリ仕様による）。
  - `tfBurnable`（0x00000001）を設定した場合、発行者がNFTokenBurnを実行可能（誤発行・不正利用時の是正が可能）。未設定の場合、発行者はバーンできず、所有者のみがバーン可能。

（注意）所有権移転はXRPLのオファー方式に基づき、受取側による`NFTokenAcceptOffer`署名が必要です（非カストディアル運用）。

## 4. エラー設計
- エラー分類（概念）:
  - WalletNotConnected
  - SignRejected / SignTimeout
  - ProxyError（バックエンドからの異常応答）
  - NetworkError (timeout, unreachable)
  - InvalidParameter (metadataUri, nftId 等)
  - XRPLSubmitError (insufficient reserve, sequence mismatch 等)
- 実装注記: 現行はDart標準の`StateError`/`ArgumentError`等で送出し、概念型へマッピング（READMEに一覧）

## 5. セキュリティ
- 秘密鍵非保持（必須）
- 入力検証の徹底（アドレス形式、URI、数値範囲）
- 署名は常に外部ウォレットで実行
- ネットワーク通信のTLS、署名要求のオリジン情報提示
- プロキシの認証はJWT必須。`CORS_ORIGINS`でオリジンホワイトリストを管理（ワイルドカード不可）。
- レート制限（最小）: 固定窓＋上限によりDoSを緩和。
- URLスキーム検証: プロキシ/ノードのURLは`http/https`のみ許可（その他は拒否）。

## 6. 設定
- ネットワーク: mainnet/testnetの切替
- エンドポイント: 優先/フォールバックノードの設定
- タイムアウト/リトライ/レート制限
- ログレベル/イベントフック

## 7. サンプルコード（案）
```dart
final sdk = XRPLutter();
await sdk.connectWallet(provider: WalletProvider.xumm);

// Mint
final mint = await sdk.mintNft(
  metadataUri: 'ipfs://.../metadata.json',
  taxon: 10,
  transferFeeBps: null,
);

// Transfer (gift)
final tr = await sdk.transferNft(
  nftId: mint.nftId,
  destinationAddress: 'r....',
  amountDrops: '0',
);

// Burn
final br = await sdk.burnNft(nftId: mint.nftId);
```

## 8. テスト方針
- 単体テスト: 生成ペイロード、入力検証、エラーパス
- 統合テスト: WalletConnector, XRPLClientとの連携（testnet推奨）
- サンプルアプリE2E: UI操作→ウォレット署名→取引完了まで

## 9. バージョニング/互換性
- バージョン: SemVer（例: 0.x系で初期公開、将来1.0へ）
- Dart 3系、Flutter最新安定版に対応

## 10. ライセンス（案）
- OSSライセンス（例: MIT）を想定。最終決定はプロジェクトオーナーと協議。

## 11. 非機能要件（再掲）
- セキュリティ、信頼性、パフォーマンス、可観測性、互換性

## 12. 今後の拡張（例）
- NFTメタデータ支援（IPFSアップロード補助）
- Offer一覧取得/管理API
- KYC/AMLフックのための拡張ポイント

本仕様書は常に最新版を維持し、SDKの設計/実装変更が発生した場合は速やかに更新します。

---

## 13. クリエイター導入チェックリスト（BYOS／XUMM）

### 13.1 準備（XUMM）
- XUMM開発者ポータルで`XUMM_API_KEY`/`XUMM_API_SECRET`を取得
- バックエンド（例: Vercel）に環境変数を設定
  - `XUMM_API_KEY` / `XUMM_API_SECRET`
  - `JWT_SECRET`（例: 本番用の十分に長いランダム文字列）
  - `CORS_ORIGINS`（本番のWebオリジンをカンマ区切り）

### 13.2 プロキシ（BYOS）
- ベースURL例: `https://<your-app>.vercel.app/api/xumm/v1/`
- エンドポイント:
  - `POST payload/create`（入力: `{ tx_json: {...} }`）
  - `GET  payload/status/{payloadId}`（出力: `{ opened?, signed?, rejected?, txHash? | tx_blob? }`）
- 認証: `Authorization: Bearer <JWT>`（HS256で`JWT_SECRET`署名）
 - JWT要件: `exp`を含む短寿命トークン（例: 2〜5分）。サーバ側でTTL上限（例: `JWT_MAX_TTL_SECONDS=300`）を検証。

### 13.3 SDK設定
- `WalletConnectorConfig.xamanProxyBaseUrl` に上記ベースURLを設定
- `WalletConnectorConfig.jwtBearerToken` にフロント取得済みJWTを渡す
- 署名フロー例（SignIn推奨）:
  - `tx_json = { TransactionType: 'SignIn' }`
  - 生成結果の`deepLink/qrUrl`をUIで提示

### 13.4 検証
- curlで`create/status`が`200`となり、`payloadId/deepLink/qrUrl`と`opened/signed`が取れること
- ブラウザのNetworkタブで`POST create`レスポンスに`payloadId`または`next.always/pushed`/`refs.qr_png`が含まれることを確認
- UIでQR表示→XUMMで承認→`signed/submitted`と`txHash`反映

### 13.5 トラブルシュート
- `401 invalid token`: JWT未署名/失効/鍵不一致 → フロントでJWT再取得、`JWT_SECRET`整合
- `400 checksum_invalid`: 宛先アドレス不正 → 有効なXRPLクラシックアドレスへ修正
- `already resolved`: 同一`uuid`再利用 → 新規`payloadId`で再生成
- `status null`: `payloadId`未確定 → `deepLink`からUUID抽出／プロキシ実装を確認

### 13.6 運用（本番）
- JWTはバックエンド`/auth/token`で自動発行・期限前更新（15–60分の短命）
- レート制限／監視（create/status/submit呼出数）
- 送信責務: プロキシsubmit（推奨）／クライアントsubmit（`tx_blob`）の選択
