<!--
目的・役割: WalletConnectorの進捗イベントを可視化するデモUI（Flutter Web）。依存解決や開発手順の注意点を記載。
作成日: 2025/11/09

更新履歴:
2025/11/17 10:33 追記: 依存解決の注意（Git+path指定／モノレポのdependency_overrides）と起動手順を追記。
理由: モノレポ内/外での導入方法の違いによる混乱防止。
-->

# wallet_connector_demo

XRPLutter SDKを用いたウォレット接続/署名フローの進捗可視化デモです。

## 依存解決の注意
- 外部プロジェクトから導入する場合（Git依存）:
  ```yaml
  dependencies:
    xrplutter_sdk:
      git:
        url: https://github.com/RazWeb3/XRPLutter.git
        path: packages/xrplutter_sdk
        # ref: v0.1.1  # 推奨: タグやコミットSHAで固定
  ```
- このモノレポ内の開発では、`dependency_overrides` によりローカルの `path` を優先します（本デモの`pubspec.yaml`参照）。
  ```yaml
  dependency_overrides:
    xrplutter_sdk:
      path: ../../packages/xrplutter_sdk
  ```

## 起動手順（開発）
```bash
flutter pub get
flutter run -d chrome
```

## 参考（Flutter公式）
- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)
- [Online documentation](https://docs.flutter.dev/)
