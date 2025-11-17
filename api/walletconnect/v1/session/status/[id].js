// -------------------------------------------------------
// 目的・役割: WalletConnect v2 セッションステータス取得スタブ
// 作成日: 2025/11/10
// 更新履歴:
// 2025/11/13 15:25 追記: idの形式検証（UUID v4）を追加し、不正入力を拒否。
// 理由: 入力検証不足によるストレージ走査や将来的な外部連携の誤呼出しを防止するため。
// -------------------------------------------------------

const { handleCorsPreflight, allowCors, verifyJwt, sendJson } = require('../../../../_utils/common');
const { getStore } = require('../../../../_utils/store');

module.exports = async (req, res) => {
  allowCors(req.headers.origin, res);
  if (handleCorsPreflight(req, res)) return;
  if (!verifyJwt(req, res)) return;

  const id = req.query.id;
  const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!id || !uuidV4.test(String(id))) {
    res.statusCode = 400;
    return sendJson(res, { error: 'invalid id' });
  }
  const store = getStore();
  const s = await store.getWcSession(id);
  if (!s) {
    res.statusCode = 404;
    return sendJson(res, { error: 'not found' });
  }
  sendJson(res, { opened: s.state.opened, signed: s.state.signed, rejected: s.state.rejected });
};
