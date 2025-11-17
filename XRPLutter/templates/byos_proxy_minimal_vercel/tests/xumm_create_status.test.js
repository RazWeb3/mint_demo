const test = require('node:test');
const assert = require('node:assert/strict');
const common = require('../api/_utils/common');
const jwt = require('jsonwebtoken');

process.env.JWT_SECRET = 'dev-secret';
process.env.CORS_ORIGINS = 'http://localhost:53210';
process.env.XUMM_API_KEY = 'test-key';
process.env.XUMM_API_SECRET = 'test-secret';

function makeReqRes({ method = 'GET', headers = {}, query = {}, body = null } = {}) {
  const resHeaders = new Map();
  let statusCode = 200;
  let ended = false;
  let data = '';
  return {
    req: { method, headers, query, body, socket: { remoteAddress: '127.0.0.1' } },
    res: {
      setHeader(k, v) { resHeaders.set(k, v); },
      get statusCode() { return statusCode; },
      set statusCode(v) { statusCode = v; },
      end(s) { data = typeof s === 'string' ? s : (s ? s.toString('utf8') : ''); ended = true; },
    },
    get result() { return { statusCode, headers: Object.fromEntries(resHeaders), body: data, ended }; },
  };
}

test('verifyJwt: missing token returns false', () => {
  const { req, res } = makeReqRes({ headers: {} });
  const ok = common.verifyJwt(req, res);
  assert.equal(ok, false);
});
