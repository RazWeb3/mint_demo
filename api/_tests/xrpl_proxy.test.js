// -------------------------------------------------------
// 目的・役割: XRPL JSON-RPCプロキシの基本バリデーションテスト
// 作成日: 2025/11/18
// -------------------------------------------------------

const test = require('node:test');
const assert = require('node:assert');

const proxy = require('../xrpl/v1/jsonrpc');

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

test('proxy: method must be POST', async () => {
  const req = { method: 'GET', headers: {} };
  const res = mockRes();
  await proxy(req, res);
  assert.strictEqual(res.statusCode, 405);
});

test('proxy: invalid endpoint yields 500', async () => {
  process.env.XRPL_ENDPOINT = 'not-a-url';
  const req = { method: 'POST', headers: { 'content-type': 'application/json' }, body: { method: 'fee', params: [{}] } };
  const res = mockRes();
  await proxy(req, res);
  assert.strictEqual(res.statusCode, 500);
  const j = JSON.parse(res.body);
  assert.strictEqual(j.error, 'server misconfigured: invalid XRPL_ENDPOINT');
});