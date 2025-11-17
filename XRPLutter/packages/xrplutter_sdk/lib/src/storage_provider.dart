// -------------------------------------------------------
// 目的・役割: 画像やメタデータJSONを外部ストレージへアップロードするための抽象インターフェース。
// 作成日: 2025/11/08
// -------------------------------------------------------

abstract class StorageProvider {
  Future<String> uploadAsset(List<int> bytes, {String? filename, String? mimeType});
  Future<String> uploadJson(Map<String, dynamic> json, {String? filename});
}

class IpfsStorageProvider implements StorageProvider {
  IpfsStorageProvider({required this.gateway});
  final String gateway;

  @override
  Future<String> uploadAsset(List<int> bytes, {String? filename, String? mimeType}) async {
    return 'ipfs://bafy.../${filename ?? 'asset.bin'}';
  }

  @override
  Future<String> uploadJson(Map<String, dynamic> json, {String? filename}) async {
    return 'ipfs://bafy.../${filename ?? 'metadata.json'}';
  }
}