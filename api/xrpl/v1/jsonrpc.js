// -------------------------------------------------------
// 目的・役割: XRPL JSON-RPCプロキシ（ブラウザCORS回避のための同一オリジン転送）
// 作成日: 2025/11/18
// -------------------------------------------------------

const { handleCorsPreflight, allowCors, rateLimit, sendJson } = require('../../_utils/common');

module.exports = async (req, res) => {
  allowCors(req.headers.origin, res);
  if (handleCorsPreflight(req, res)) return;
  if (!(await rateLimit(req, res))) return;

  if (req.method !== 'POST') {
    res.statusCode = 405;
    return sendJson(res, { error: 'method not allowed' });
  }
  const ct = (req.headers['content-type'] || '').toLowerCase();
  if (!ct.includes('application/json')) {
    res.statusCode = 400;
    return sendJson(res, { error: 'content-type must be application/json' });
  }

  const endpoint = process.env.XRPL_ENDPOINT || 'https://s.altnet.rippletest.net:51234';
  let url;
  try {
    url = new URL(endpoint);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new Error('invalid scheme');
  } catch (_) {
    res.statusCode = 500;
    return sendJson(res, { error: 'server misconfigured: invalid XRPL_ENDPOINT' });
  }

  try {
    const r = await fetch(url.toString(), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(req.body || {}),
    });
    const text = await r.text();
    res.statusCode = r.status;
    res.setHeader('content-type', 'application/json');
    res.end(text);
  } catch (e) {
    res.statusCode = 502;
    return sendJson(res, { error: 'bad gateway', message: String(e && e.message || e) });
  }
};