// -------------------------------------------------------
// 目的・役割: 共通ユーティリティ（CORS, JWT検証, JSON応答）を提供する
// 作成日: 2025/11/10
// -------------------------------------------------------

const jwt = require('jsonwebtoken');
const { getStore } = require('./store');

function getClientId(req) {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.length > 0) return xf.split(',')[0].trim();
  try {
    return req.socket && req.socket.remoteAddress ? String(req.socket.remoteAddress) : 'unknown';
  } catch (_) {
    return 'unknown';
  }
}

async function rateLimit(req, res) {
  try {
    const store = getStore();
    const id = getClientId(req);
    const windowSec = parseInt(process.env.RL_WINDOW_SECONDS || '10', 10);
    const maxReq = parseInt(process.env.RL_MAX_REQUESTS || '20', 10);
    const key = `rl:${Math.floor(Date.now() / (windowSec * 1000))}:${id}`;
    const current = (await store.getWcSession(key)) || { count: 0 };
    current.count = (current.count || 0) + 1;
    await store.setWcSession(key, current);
    if (current.count > maxReq) {
      res.statusCode = 429;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ error: 'rate limit exceeded' }));
      return false;
    }
    return true;
  } catch (_) {
    // ストア未構成時はレート制限をスキップ（最小構成）
    return true;
  }
}

function getAllowedOrigins() {
  return (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function allowCors(origin, res) {
  const allowed = getAllowedOrigins();
  if (origin && allowed.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }
  // 厳格化: ワイルドカード許可は行わない
  res.setHeader('Access-Control-Allow-Credentials', 'false');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Vary', 'Origin');
}

function handleCorsPreflight(req, res) {
  allowCors(req.headers.origin, res);
  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    res.end();
    return true;
  }
  return false;
}

function verifyJwt(req, res) {
  const auth = req.headers.authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.substring(7) : null;
  if (!token) {
    res.statusCode = 401;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ error: 'missing token' }));
    return false;
  }
  try {
    const secret = process.env.JWT_SECRET;
    if (!secret) {
      res.statusCode = 500;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ error: 'server misconfigured: JWT_SECRET missing' }));
      return false;
    }
    const decoded = jwt.verify(token, secret);
    const nowSec = Math.floor(Date.now() / 1000);
    const maxTtl = parseInt(process.env.JWT_MAX_TTL_SECONDS || '300', 10);
    if (typeof decoded === 'object' && decoded && typeof decoded.exp === 'number') {
      const ttl = decoded.exp - nowSec;
      if (ttl > maxTtl) {
        res.statusCode = 401;
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify({ error: 'invalid token: exp too far' }));
        return false;
      }
    }
    return true;
  } catch (e) {
    res.statusCode = 401;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ error: 'invalid token' }));
    return false;
  }
}

function sendJson(res, obj) {
  res.statusCode = 200;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(obj));
}

module.exports = {
  allowCors,
  handleCorsPreflight,
  rateLimit,
  verifyJwt,
  sendJson,
};
