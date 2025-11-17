// -------------------------------------------------------
// 目的・役割: Web拡張（Crossmark/GemWallet）の存在検出を行うためのスタブ（非Web環境向け）。
// 作成日: 2025/11/09
// 
// 更新履歴:
// 2025/11/09 15:37 追記: getAddressCrossmark/getAddressGemWallet/getNetwork を追加（IF整合）。
// 理由: テスト/非Web環境でも同一インターフェースでコンパイル可能にするため。
// 2025/11/09 15:50 変更: requestSignCrossmark/requestSignGemWallet に options 引数（任意）を追加。
// 理由: Web拡張側submitの有無など挙動差を呼び出し側から制御するため（IF整合）。
// -------------------------------------------------------

/// 非Web環境でのフォールバック。常に拡張は未検出となる。
class BrowserWalletInterop {
  BrowserWalletInterop._();
  static final BrowserWalletInterop instance = BrowserWalletInterop._();

  bool get isAvailableCrossmark => false;
  bool get isAvailableGemWallet => false;

  /// 非Web環境では常に拡張未検出扱い。署名要求は未対応を返す。
  Future<Map<String, dynamic>> requestSignCrossmark(Map<String, dynamic> txJson, {Map<String, dynamic>? options}) async {
    return {
      'signed': false,
      'rejected': false,
      'error': 'Web extension not available (stub)',
    };
  }

  /// 非Web環境では常に拡張未検出扱い。署名要求は未対応を返す。
  Future<Map<String, dynamic>> requestSignGemWallet(Map<String, dynamic> txJson, {Map<String, dynamic>? options}) async {
    return {
      'signed': false,
      'rejected': false,
      'error': 'Web extension not available (stub)',
    };
  }

  Future<String?> getAddressCrossmark() async => null;
  Future<String?> getAddressGemWallet() async => null;
  Future<String?> getNetwork() async => null;
}