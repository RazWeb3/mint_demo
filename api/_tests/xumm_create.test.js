// -------------------------------------------------------
// 目的・役割: XUMM/Xaman ペイロード作成APIの基本バリデーションテスト
// 作成日: 2025/11/18
// -------------------------------------------------------

const test = require('node:test');
const assert = require('node:assert');

const create = require('../xumm/v1/payload/create');

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

test('create: method must be POST', async () => {
  const req = { method: 'GET', headers: {} };
  const res = mockRes();
  await create(req, res);
  assert.strictEqual(res.statusCode, 405);
});

test('create: content-type must be application/json', async () => {
  const req = { method: 'POST', headers: { 'content-type': 'text/plain' } };
  const res = mockRes();
  await create(req, res);
  assert.strictEqual(res.statusCode, 400);
});

test('create: missing xumm credentials yields 500', async () => {
  process.env.AUTH_DISABLED = 'true';
  delete process.env.XUMM_API_KEY;
  delete process.env.XUMM_API_SECRET;
  const req = { method: 'POST', headers: { 'content-type': 'application/json' }, body: { tx_json: { TransactionType: 'SignIn' } } };
  const res = mockRes();
  await create(req, res);
  assert.strictEqual(res.statusCode, 500);
  const j = JSON.parse(res.body);
  assert.strictEqual(j.error, 'missing xumm api credentials');
});