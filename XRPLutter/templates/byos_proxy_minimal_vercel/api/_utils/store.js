// -------------------------------------------------------
// 目的・役割: ストレージ抽象（memory / upstash）を選択して提供する
// 作成日: 2025/11/10
// -------------------------------------------------------

const memoryStore = require('./store_memory');
let upstashStore = null;

function getBackend() {
  const b = (process.env.STORAGE_BACKEND || 'memory').toLowerCase();
  return b;
}

function getStore() {
  const backend = getBackend();
  const ttl = parseInt(process.env.TTL_SECONDS || '600', 10);
  if (backend === 'upstash') {
    if (!upstashStore) {
      upstashStore = require('./store_upstash');
    }
    return upstashStore.create(ttl);
  }
  return memoryStore.create(ttl);
}

module.exports = {
  getStore,
};