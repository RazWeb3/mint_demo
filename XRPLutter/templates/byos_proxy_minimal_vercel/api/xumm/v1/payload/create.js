// -------------------------------------------------------
// 目的・役割: XUMM/Xaman ペイロード作成スタブ（deepLink/QR返却）
// 作成日: 2025/11/10
// 更新履歴:
// 2025/11/13 15:25 変更: 入力検証を強化（メソッド/Content-Type/tx_jsonのサイズと型検証）し、過大入力や不正形式を拒否。
// 理由: 不要な負荷や予期せぬ挙動、潜在的な攻撃ベクトル（過大ペイロード）を抑止するため。
// -------------------------------------------------------

const { handleCorsPreflight, allowCors, rateLimit, verifyJwt, sendJson } = require('../../../_utils/common');

module.exports = async (req, res) => {
  allowCors(req.headers.origin, res);
  if (handleCorsPreflight(req, res)) return;
  if (!(await rateLimit(req, res))) return;
  if (!verifyJwt(req, res)) return;

  if (req.method !== 'POST') {
    res.statusCode = 405;
    return sendJson(res, { error: 'method not allowed' });
  }
  const ct = (req.headers['content-type'] || '').toLowerCase();
  if (!ct.includes('application/json')) {
    res.statusCode = 400;
    return sendJson(res, { error: 'content-type must be application/json' });
  }

  const key = process.env.XUMM_API_KEY;
  const secret = process.env.XUMM_API_SECRET;
  if (!key || !secret) {
    res.statusCode = 500;
    return sendJson(res, { error: 'missing xumm api credentials' });
  }

  const txJson = (req.body && req.body.tx_json) || { TransactionType: 'SignIn' };
  const rawLen = Buffer.byteLength(JSON.stringify(txJson || {}), 'utf8');
  if (!txJson || typeof txJson !== 'object') {
    res.statusCode = 400;
    return sendJson(res, { error: 'tx_json must be an object' });
  }
  if (rawLen > 4000) {
    res.statusCode = 413;
    return sendJson(res, { error: 'tx_json too large' });
  }
  if (typeof txJson.TransactionType !== 'string' || !txJson.TransactionType) {
    res.statusCode = 400;
    return sendJson(res, { error: 'TransactionType required' });
  }
  const r = await fetch('https://xumm.app/api/v1/platform/payload', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'X-API-Key': key,
      'X-API-Secret': secret,
    },
    body: JSON.stringify({ txjson: txJson }),
  });

  if (r.status !== 200) {
    const body = await r.text();
    res.statusCode = r.status;
    return sendJson(res, { error: 'xumm create failed', status: r.status, body });
  }

  const json = await r.json();
  const payloadId = json.uuid;
  const deepLink = json.next && (json.next.always || json.next.pushed);
  const qrUrl = json.refs && json.refs.qr_png;
  return sendJson(res, { payloadId, deepLink, qrUrl });
};
