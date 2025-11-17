// -------------------------------------------------------
// 目的・役割: XRPLutter SDKの基本的な読み込みとスタブAPIの存在を検証するテスト。
// 作成日: 2025/11/08
//
// 更新履歴:
// -------------------------------------------------------

import 'package:test/test.dart';
import 'package:xrplutter_sdk/xrplutter.dart';

void main() {
  test('XRPLutter can be instantiated', () {
    final sdk = XRPLutter();
    expect(sdk, isNotNull);
  });
}