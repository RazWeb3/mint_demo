// -------------------------------------------------------
// 目的・役割: ステージング/PoC向けのメモリストア（揮発性）
// 作成日: 2025/11/10
// -------------------------------------------------------

function create(ttlSeconds) {
  const wcMap = new Map();
  const xummMap = new Map();

  function setWithTtl(map, key, value) {
    map.set(key, { value, expiresAt: Date.now() + ttlSeconds * 1000 });
  }

  function getWithTtl(map, key) {
    const item = map.get(key);
    if (!item) return null;
    if (item.expiresAt < Date.now()) {
      map.delete(key);
      return null;
    }
    return item.value;
  }

  return {
    async setWcSession(id, obj) {
      setWithTtl(wcMap, `wc:${id}`, obj);
    },
    async getWcSession(id) {
      return getWithTtl(wcMap, `wc:${id}`);
    },
    async setXummPayload(id, obj) {
      setWithTtl(xummMap, `xumm:${id}`, obj);
    },
    async getXummPayload(id) {
      return getWithTtl(xummMap, `xumm:${id}`);
    },
  };
}

module.exports = { create };
