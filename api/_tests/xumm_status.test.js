// -------------------------------------------------------
// 目的・役割: XUMM/Xaman ステータスAPIの基本バリデーションテスト
// 作成日: 2025/11/18
// -------------------------------------------------------

const test = require('node:test');
const assert = require('node:assert');

const status = require('../xumm/v1/payload/status/[payloadId].js');

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: '',
    setHeader(k, v) { this.headers[k] = v; },
    end(s) { this.body = s || ''; },
  };
  return res;
}

test('status: invalid payloadId yields 400', async () => {
  process.env.XUMM_API_KEY = 'dummy';
  process.env.XUMM_API_SECRET = 'dummy';
  const req = { method: 'GET', headers: {}, query: { payloadId: 'bad-id' } };
  const res = mockRes();
  await status(req, res);
  assert.strictEqual(res.statusCode, 400);
});

test('status: missing xumm credentials yields 500', async () => {
  delete process.env.JWT_SECRET; // verifyJwt should skip when secret missing
  delete process.env.XUMM_API_KEY;
  delete process.env.XUMM_API_SECRET;
  const req = { method: 'GET', headers: {}, query: { payloadId: '00000000-0000-4000-8000-000000000000' } };
  const res = mockRes();
  await status(req, res);
  assert.strictEqual(res.statusCode, 500);
  const j = JSON.parse(res.body);
  assert.strictEqual(j.error, 'missing xumm api credentials');
});