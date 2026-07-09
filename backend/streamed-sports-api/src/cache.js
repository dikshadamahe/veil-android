/**
 * Tiny in-memory TTL cache. Process-local only — fine for a single PM2 fork.
 */
class TtlCache {
  constructor() {
    /** @type {Map<string, { expiresAt: number, value: unknown }>} */
    this._store = new Map();
    this.hits = 0;
    this.misses = 0;
  }

  get(key) {
    const entry = this._store.get(key);
    if (!entry) {
      this.misses += 1;
      return undefined;
    }
    if (Date.now() >= entry.expiresAt) {
      this._store.delete(key);
      this.misses += 1;
      return undefined;
    }
    this.hits += 1;
    return entry.value;
  }

  set(key, value, ttlMs) {
    if (!Number.isFinite(ttlMs) || ttlMs <= 0) {
      return;
    }
    this._store.set(key, {
      expiresAt: Date.now() + ttlMs,
      value,
    });
  }

  stats() {
    return {
      size: this._store.size,
      hits: this.hits,
      misses: this.misses,
    };
  }

  clear() {
    this._store.clear();
    this.hits = 0;
    this.misses = 0;
  }
}

module.exports = { TtlCache };
