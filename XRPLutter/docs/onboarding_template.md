# 本番導入ガイド（簡易テンプレ）

## 概要
- 目的: WalletConnect v2/Xaman をプロキシ経由で安全に連携する最小セット
- 対象: XRPLutter デモ/本番アプリの初期導入

## 手順概要
1. プロキシをデプロイ（Vercel最小テンプレ）
2. プロキシ環境変数を設定
3. クライアント側で JWT を用意
4. Flutter アプリへ最小設定を適用

## 1. プロキシのデプロイ
- テンプレート: `templates/byos_proxy_minimal_vercel/`
- Vercel へインポート後、以下の環境変数を設定

## 2. プロキシ環境変数（Vercel）
- `JWT_SECRET`: クライアントからの `Authorization: Bearer` 検証用の共有シークレット
- `CORS_ORIGINS`: 許可するオリジン（例: `http://localhost:53210,https://yourapp.example.com`）
- `XUMM_API_KEY`/`XUMM_API_SECRET`: Xaman 連携用（必要な場合のみ）

## 3. JWT の用意（簡易）
- 開発: `JWT_SECRET=dev-secret` とした上で、クライアントも `Authorization: Bearer dev-secret` を使用
- 本番: 短寿命の HMAC-SHA256 JWT をバックエンドで発行し、クライアントへ配布

例（Node.js/Express 断片）
```js
import jwt from 'jsonwebtoken';

// 短寿命トークン発行（例: 2分）
const token = jwt.sign({ sub: 'xrplutter-app' }, process.env.JWT_SECRET, { expiresIn: '2m' });
// クライアントへ返却して Bearer で使用
```

## 4. Flutter アプリ設定（最短）
- 実行時引数でプロキシのベースURLとJWTを渡す

例（開発）
```
flutter run -d web-server --web-port 53210 \
  --dart-define=WC_PROXY_BASE_URL=http://localhost:53211/walletconnect/v1/ \
  --dart-define=XAMAN_PROXY_BASE_URL=http://localhost:53211/xumm/v1/ \
  --dart-define=JWT_BEARER_TOKEN=dev-secret
```

- アプリ内で `String.fromEnvironment` が読み込まれ、UIの入力欄へ初期値が反映

## 5. SDK設定（短縮版）
```dart
final connector = WalletConnector(
  config: WalletConnectorConfig(
    walletConnectProxyBaseUrl: Uri.parse('http://localhost:53211/walletconnect/v1/'),
    xamanProxyBaseUrl: Uri.parse('http://localhost:53211/xumm/v1/'),
    jwtBearerToken: 'dev-secret',
    signingTimeout: const Duration(seconds: 45),
    webSubmitByExtension: true,
    verifyAddressBeforeSign: false,
  ),
);
await connector.connect(provider: WalletProvider.walletconnect);
```

## 6. エンドポイント（参考）
- WalletConnect v2
  - `POST /walletconnect/v1/session/create`
  - `GET  /walletconnect/v1/session/status/:id`
- Xaman (XUMM)
  - `POST /xumm/v1/payload/create`
  - `GET  /xumm/v1/payload/status/:payloadId`

## トラブルシューティング（要点）
- 401/403: JWT 不一致。`JWT_SECRET` と Bearer の整合を確認
- CORS: `CORS_ORIGINS` にクライアントのオリジンを追加
- 画像QR失敗: `qrUrl` 参照先の公開可否を確認
