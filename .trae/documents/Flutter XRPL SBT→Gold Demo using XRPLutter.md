## 概要
- Flutter WebでXRPLデモを実装し、Xamanテストネットでの署名・実行をQRワークフローで行う
- XRPLutter SDKを必ず利用して、SBT 2枚ミント→2枚バーン→ゴールドチケット1枚ミント→送付の一連の動作を検証
- 成果物はVercelへデプロイし、画像は`images/`、メタデータはVercel上の`/metadata/`に静的配置

## SDK検証方針
- 手順0: XRPLutterの利用可否と機能確認（`NFTokenMint`/`NFTokenBurn`/`account_nfts`/Offer関連）
- 成功条件: SDKで上記トランザクションの生成・送信が可能かつXaman署名QRとの連携が可能
- 失敗時: 開発中止し、理由を詳細報告（代替案として`xrpl_dart`やサーバー側`xrpl.js`を提示）

## アーキテクチャ
- フロント: Flutter Web（Vercelに静的ホスト）。UIは「ミント」「合成（バーン＋ゴールドミント）」「送付」3画面
- バックエンド: Vercel Functions（サーバーレス）。Xaman APIキーはVercel環境変数に設定してもらう
- 署名フロー: バックエンドがXamanペイロードを作成→フロントでQR表示→ユーザーがXamanで署名→結果ポーリング→完了で自動クローズ

## バックエンドAPI（Vercel Functions）
- `POST /api/mint-sbt`: SBTミント用`NFTokenMint`ペイロード生成（Flags: 非転送、`URI`は`ticket.json`）。Xaman QRの`webhook/payloadId`返却
- `POST /api/burn-compose`: 選択SBT2枚の`NFTokenBurn`を順次ペイロード化→成功後にゴールド`NFTokenMint`（Flags: `tfTransferable`、`URI`は`gold.json`）をペイロード化
- `GET /api/account-nfts?account=...`: `account_nfts`で一覧取得し、`URI`が当該ドメインの`ticket.json`/`gold.json`に一致するもののみ返却
- `POST /api/send-gold`: ゴールドチケット送付のため`NFTokenCreateOffer`（XRP額は0または微小、`Destination`指定）→受領者側`NFTokenAcceptOffer`ペイロード生成
- 共通: Xamanペイロード作成・ステータス取得・完了判定、失敗時の詳細レスポンス

## フロントエンド画面とフロー
- **ミント画面**
  - チケット画像`images/ticket.png`表示、`Mint`ボタン
  - クリックでQRポップアップ表示→署名完了で自動クローズ→トーストで成功表示
- **合成画面**
  - 「ウォレットを読み込み」ボタンで署名（軽い認証ペイロード）→アドレス取得
  - `GET /api/account-nfts`で取得したSBTのみをグリッド表示（`URI==ticket.json`かつ非転送Flags）
  - 2枚選択で`合成`ボタン有効→`POST /api/burn-compose`→バーン2枚成功後にゴールドミント→完了でウォレットへ付与
- **送付画面**
  - 保有ゴールドのみ表示（`URI==gold.json`かつ転送可能Flags）
  - 送付先クラシックアドレス入力→`POST /api/send-gold`→QR署名→相手側受領もQRで実施できるUI（受領フローのリンク/QR）

## XRPLトランザクション仕様
- SBTミント: `NFTokenMint` with `Flags`に`tfTransferable`未設定（非転送）、`NFTokenTaxon`固定値、`URI`=`https://<vercel-host>/metadata/ticket.json`
- バーン: `NFTokenBurn`（所有者署名）。2枚を順次実行
- ゴールドミント: `NFTokenMint` with `tfTransferable=true`、`URI`=`https://<vercel-host>/metadata/gold.json`
- 送付: 所有者が`NFTokenCreateOffer`（`Destination`=受領者、`Amount`はXRP 0または微小）、受領者が`NFTokenAcceptOffer`
- 参考: NFTokenのFlagsと挙動はXRPL公式に準拠（`tfTransferable`/`tfBurnable`など）

## メタデータ
- `ticket.json`: `{ name: "Ticket", description, image: "/images/ticket.png", attributes: [...] }`
- `gold.json`: `{ name: "Gold Ticket", description, image: "/images/gold_ticket.png", attributes: [...] }`
- 2種のみ用意し、複数枚ミント時も同じURIを使用

## データフィルタリング
- `account_nfts`結果から以下でフィルタ:
  - `Issuer`がユーザーアカウント（または当該プロジェクトの想定発行者）
  - `URI`が`/metadata/ticket.json`または`/metadata/gold.json`
  - SBT表示は`tfTransferable`未設定のもののみ

## セキュリティ・環境
- 署名はすべてXamanで実施（秘密鍵はフロント/バックに保持しない）
- Vercel環境変数にXaman APIキー（テストネット）を設定（ユーザー側で準備）
- テストネット接続は`wss://s.altnet.rippletest.net:51233`等を使用

## デプロイ
- Flutter Webを`build/web`生成→Vercelへアップロード
- `public/metadata/`と`public/images/`を配置、`vercel.json`でAPIルートと静的配信設定
- ユーザーはVercelログイン済みのため、環境変数設定後にデプロイ実行

## 検証手順（機能証明）
- ミント2枚→`account_nfts`で2枚確認（非転送Flags、`ticket.json`）
- 合成→2枚バーン成功→ゴールド1枚ミント確認（転送Flags、`gold.json`）
- 送付→指定アドレスへOffer作成→受領者がAccept→保有者移転を確認
- すべてQR署名完了時にUIが自動クローズすることを確認

## ファイル運用ルール対応
- すべての新規ファイル冒頭に「目的・役割」「作成日」をコメント記載
- 既存ファイル更新時は冒頭コメントの更新履歴に追記（日時・内容・理由）
- 仕様書更新有無を各実装終了時に必ず報告

## タイムライン（約3時間）
- 0:30 SDK検証・雛形生成（Flutter Web）
- 1:00 バックエンドAPI（Xaman連携）
- 0:45 フロントUI（3画面＋QRフロー）
- 0:30 総合検証・Vercelデプロイ
- 0:15 予備・報告

## リスクと中止条件
- XRPLutterがXLS-20（NFToken）未対応または公開入手不可→即時中止し報告
- Xaman APIキー未設定・テストネット障害→設定/ネット復旧後に再試行
