
# XRPLutter NFT Kit SDK

## プロジェクト概要
XRPL（XRP Ledger）上でNFTのミント／送付／バーンをFlutter/Dartから安全かつ簡潔に扱えるSDKです。`docs/sdk_concept_summary.md` に記載の通り、以下を目的とします。
- XRPLの複雑性の抽象化と開発効率の向上
- 秘密鍵の非保持と外部ウォレット委任によるセキュリティ確保
- AI駆動開発の安定化（明確なインターフェースでAIを補助ツールとして活用）
- ノーコード/ローコード「NFTアプリビルダー」基盤としての拡張性

主要機能:
- NFTの発行（ミント）／送付／バーンの高レベルAPI
- BYOS（Bring Your Own Server）構成の最小プロキシテンプレート（Vercel向け）
- 失敗しづらいパラメタ設計とエラーフィードバック

## WebアプリケーションURL
- デモWebアプリ: 準備中（Vercelデプロイ予定）
- ローカル実行ガイド: `packages/xrplutter_sdk/README.md` と `templates/byos_proxy_minimal_vercel/README.md` を参照

## 審査基準を満たしていることがわかる内容
- テーマ適合: 「XRPL × AI開発」。SDKが提供する安定APIを介して補助的に活用（目的の「AI駆動開発の安定化」に準拠）。
- オープンソース提出: リポジトリは公開かつ `MIT` ライセンス。提出後もオープンソースを維持。
- 既存コードの使用と出典開示: 再利用部分はREADMEおよび各ファイル冒頭コメントで出典と範囲を開示（未開示利用は行いません）。
- 誠実性: AIツール使用時は適切な引用・帰属・著作権表示を実施。
- 技術面の健全性: 下記セキュリティ/運用ポリシーに準拠（秘密鍵非保持、短寿命JWT、CORSホワイトリスト、機密情報の除外）。
- コミュニティ行動規範: リスペクト／協力／安全／責任の原則を遵守。

## リポジトリ構成（主要）
- `packages/xrplutter_sdk/` — SDK本体（導入ガイドは `packages/xrplutter_sdk/README.md`）
- `templates/byos_proxy_minimal_vercel/` — Vercel向け最小プロキシテンプレ（導入ガイドは `templates/byos_proxy_minimal_vercel/README.md`）
- `docs/specification.md` — 技術仕様書（最新版）
- `docs/onboarding_template.md` — 本番導入ガイド（簡易テンプレ）

## クイックスタート
- SDKの利用方法と実行例は `packages/xrplutter_sdk/README.md` を参照（`--dart-define` 例あり）。
- プロキシ環境の変数設定・エンドポイントは `templates/byos_proxy_minimal_vercel/README.md` を参照。

## セキュリティ/運用の要点
- 秘密鍵は保持しません。署名は常に外部ウォレットで行います。
- JWTは短寿命でバックエンド発行し、`Authorization: Bearer` を利用します。
- CORSはホワイトリストで厳格管理し、ワイルドカード許可は避けます。
- 機密情報（`.env`、鍵ファイル、非公開ドキュメント）は `.gitignore` で除外します。

## ライセンス
- 本リポジトリは MIT ライセンスです（`LICENSE` 参照）。

## 現在のステータス
- 非本番/PoC向けの公開。APIや仕様は変更される可能性があります。
