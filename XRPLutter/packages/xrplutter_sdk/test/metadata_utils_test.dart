// -------------------------------------------------------
// 目的・役割: MetadataUtilsのSoft SBTフラグ付与と判定ロジックの検証。
// 作成日: 2025/11/09
//
// 更新履歴:
// 2025/11/09 12:36 初版: addSoftSbtFlag/isSoftSbtJsonのテストを追加。
// 理由: Soft SBTの最小実装が期待どおりに機能することを確認するため。
// -------------------------------------------------------

import 'package:test/test.dart';
import 'package:xrplutter_sdk/src/metadata_utils.dart';

void main() {
  group('MetadataUtils.addSoftSbtFlag', () {
    test('custom.sbt=true が付与される', () {
      final original = {
        'name': 'Item',
        'custom': {'foo': 'bar'},
      };
      final withSbt = MetadataUtils.addSoftSbtFlag(original);
      expect(withSbt['custom']['sbt'], isTrue);
      expect(withSbt['custom']['foo'], equals('bar'));
      expect(withSbt['sbt'], isTrue); // top-level sbtも付与
    });
  });

  group('MetadataUtils.isSoftSbtJson', () {
    test('custom.sbt=true で true', () {
      final json = {
        'name': 'Item',
        'custom': {'sbt': true}
      };
      expect(MetadataUtils.isSoftSbtJson(json), isTrue);
    });

    test('top-level sbt=true で true', () {
      final json = {
        'name': 'Item',
        'sbt': true,
      };
      expect(MetadataUtils.isSoftSbtJson(json), isTrue);
    });

    test('sbtフラグがない場合は false', () {
      final json = {'name': 'Item'};
      expect(MetadataUtils.isSoftSbtJson(json), isFalse);
    });
  });
}