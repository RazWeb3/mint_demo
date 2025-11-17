<!--
目的・役割: クリエイターがVercelへワンクリックでデプロイできる最小BYOSプロキシのテンプレート。KV有無の切り替え対応。
作成日: 2025/11/10
-->

# BYOS Proxy Minimal (Vercel)

このテンプレートは、WalletConnect v2 と XUMM/Xaman 連携のための最小プロキシを Vercel に即デプロイできる形で提供します。

特徴
- KV有無切り替え: STORAGE_BACKEND=memory | upstash（Upstash Redis利用）
- エンドポイント:
  - POST /api/walletconnect/v1/session/create
  - GET  /api/walletconnect/v1/session/status/:id
  - POST /api/xumm/v1/payload/create
  - GET  /api/xumm/v1/payload/status/:payloadId
- セキュリティ最低限: 短命JWT検証、厳格CORS（ホワイトリスト）
 - セキュリティ最低限: 短命JWT検証（`exp`必須＋TTL上限）、簡易レート制限、厳格CORS（ホワイトリスト）

導入手順（最短）
1) Vercelで「新規プロジェクト」を作成し、本テンプレートフォルダ（templates/byos_proxy_minimal_vercel）をリポジトリとしてインポート
2) 環境変数を設定
   - JWT_SECRET: 任意の強固な秘密鍵
   - CORS_ORIGINS: 許可するオリジン（例: http://localhost:53210, https://your-frontend.example）
   - STORAGE_BACKEND: memory または upstash（省略時は memory）
   - TTL_SECONDS: セッション保持TTL（秒）。例: 600
   - （KV利用時）UPSTASH_REDIS_REST_URL, UPSTASH_REDIS_REST_TOKEN
3) Deploy ボタンを押す
4) 付与されたURL（例: https://your-app.vercel.app/）をSDK設定に貼り付け
   - WalletConnect: https://your-app.vercel.app/api/walletconnect/v1/
   - XUMM/Xaman: https://your-app.vercel.app/api/xumm/v1/

注意
- KVなし（memory）はサーバレスのインスタンス切替で状態が揮発する可能性があります。少人数の検証やPoCでは成立しますが、本番ではKV/DB利用を推奨します。
- KVありはUpstashの無料枠で開始可能ですが、レートや容量超過時は有料となります。最新の料金はUpstash/Vercelの公式を参照してください。

JWT運用メモ
- 開発: `JWT_SECRET=dev-secret` として、クライアントは簡易Bearerを使用可能
- 本番: HS256のJWTをバックエンドで短寿命（例: 2–5分）発行し、`Authorization: Bearer <JWT>` を検証
- TTL上限: `JWT_MAX_TTL_SECONDS`（例: 300）で`exp`が過度に先のトークンを拒否

レート制限（最小）
- 変数: `RL_WINDOW_SECONDS`（既定10秒）、`RL_MAX_REQUESTS`（既定20リクエスト）
- 単位: IP/クライアントごとの固定窓カウント

ライセンス/運用
- 公開前にCORSのホワイトリストを最小にし、JWTを短命化してください。
- 実連携（XUMM APIキーやWC v2ハンドシェイク）はこの最小スタブの上に拡張してください。
