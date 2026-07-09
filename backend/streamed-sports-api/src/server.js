require('dotenv').config();

const express = require('express');
const cors = require('cors');
const pino = require('pino');
const { TtlCache } = require('./cache');
const { fetchUpstream } = require('./upstream');

const PORT = Number(process.env.PORT || 3003);
const HOST = process.env.HOST || '0.0.0.0';
const UPSTREAM_BASE = (process.env.UPSTREAM_BASE || 'https://streamed.pk').replace(/\/$/, '');
const UPSTREAM_TIMEOUT_MS = Number(process.env.UPSTREAM_TIMEOUT_MS || 15000);

const TTL = {
  sports: Number(process.env.CACHE_SPORTS_TTL_MS || 3_600_000),
  matches: Number(process.env.CACHE_MATCHES_TTL_MS || 120_000),
  live: Number(process.env.CACHE_LIVE_TTL_MS || 45_000),
  stream: Number(process.env.CACHE_STREAM_TTL_MS || 20_000),
};

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const cache = new TtlCache();
const app = express();
const startedAt = new Date().toISOString();

app.disable('x-powered-by');
app.use(cors());

/** Allowed match path suffixes after /api/matches/ */
const MATCH_PATH_RE =
  /^(all|all-today|live|[a-z0-9-]+)(\/popular)?$/i;

/** Allowed stream source ids (docs + live-observed `admin`) */
const SOURCE_RE = /^[a-z0-9-]+$/i;
const SOURCE_ID_RE = /^[a-zA-Z0-9._~-]+$/;

function sendJson(res, status, body, cacheHit) {
  res.setHeader('X-Cache', cacheHit ? 'HIT' : 'MISS');
  res.status(status).json(body);
}

async function cachedJson(cacheKey, ttlMs, upstreamPath) {
  const hit = cache.get(cacheKey);
  if (hit !== undefined) {
    return { data: hit, cacheHit: true };
  }
  const result = await fetchUpstream(UPSTREAM_BASE, upstreamPath, {
    timeoutMs: UPSTREAM_TIMEOUT_MS,
  });
  if (result.json === undefined) {
    const err = new Error('Upstream returned non-JSON');
    err.status = 502;
    throw err;
  }
  cache.set(cacheKey, result.json, ttlMs);
  return { data: result.json, cacheHit: false };
}

function handleUpstreamError(res, err, logCtx) {
  const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 502;
  logger.warn({ err: err.message, ...logCtx }, 'upstream failure');
  res.status(status).json({
    ok: false,
    error: err.message,
    service: 'veil-streamed-sports',
  });
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'veil-streamed-sports',
    version: '1.0.0',
    upstream: UPSTREAM_BASE,
    port: PORT,
    startedAt,
    cache: cache.stats(),
    timestamp: new Date().toISOString(),
  });
});

app.get('/debug/cache', (_req, res) => {
  res.json({ ok: true, cache: cache.stats() });
});

app.post('/debug/cache/clear', (_req, res) => {
  cache.clear();
  res.json({ ok: true, cleared: true });
});

// --- Sports catalog ---------------------------------------------------------

app.get('/v1/sports', async (_req, res) => {
  try {
    const { data, cacheHit } = await cachedJson(
      'sports',
      TTL.sports,
      '/api/sports',
    );
    sendJson(res, 200, data, cacheHit);
  } catch (err) {
    handleUpstreamError(res, err, { path: '/v1/sports' });
  }
});

// --- Matches ----------------------------------------------------------------

async function handleMatches(req, res, rest) {
  const normalized = String(rest || '').replace(/^\/+|\/+$/g, '');
  if (!MATCH_PATH_RE.test(normalized)) {
    return res.status(400).json({
      ok: false,
      error:
        'Invalid matches path. Use all, all-today, live, or a sport id (+ optional /popular).',
    });
  }

  const isLive = normalized === 'live' || normalized === 'live/popular';
  const ttl = isLive ? TTL.live : TTL.matches;
  const cacheKey = `matches:${normalized}`;
  const upstreamPath = `/api/matches/${normalized}`;

  try {
    const { data, cacheHit } = await cachedJson(cacheKey, ttl, upstreamPath);
    sendJson(res, 200, data, cacheHit);
  } catch (err) {
    handleUpstreamError(res, err, { path: `/v1/matches/${normalized}` });
  }
}

app.get('/v1/matches/:sport/popular', (req, res) =>
  handleMatches(req, res, `${req.params.sport}/popular`),
);
app.get('/v1/matches/:sport', (req, res) =>
  handleMatches(req, res, req.params.sport),
);

// Convenience aliases matching the planning doc
app.get('/v1/matches-live', (_req, res) => res.redirect(307, '/v1/matches/live'));
app.get('/v1/matches-today', (_req, res) =>
  res.redirect(307, '/v1/matches/all-today'),
);

// --- Streams ----------------------------------------------------------------

app.get('/v1/stream/:source/:id', async (req, res) => {
  const source = String(req.params.source || '');
  const id = String(req.params.id || '');

  if (!SOURCE_RE.test(source) || !SOURCE_ID_RE.test(id)) {
    return res.status(400).json({
      ok: false,
      error: 'Invalid source or id',
    });
  }

  const cacheKey = `stream:${source}:${id}`;
  const upstreamPath = `/api/stream/${encodeURIComponent(source)}/${encodeURIComponent(id)}`;

  try {
    const { data, cacheHit } = await cachedJson(cacheKey, TTL.stream, upstreamPath);
    sendJson(res, 200, data, cacheHit);
  } catch (err) {
    handleUpstreamError(res, err, { path: `/v1/stream/${source}/${id}` });
  }
});

// --- Images (pass-through, short browser cache) -----------------------------

app.get(/^\/v1\/images\/(.+)$/, async (req, res) => {
  const sub = req.params[0];
  if (!sub || sub.includes('..')) {
    return res.status(400).json({ ok: false, error: 'Invalid image path' });
  }

  const upstreamPath = `/api/images/${sub}`;
  try {
    const result = await fetchUpstream(UPSTREAM_BASE, upstreamPath, {
      timeoutMs: UPSTREAM_TIMEOUT_MS,
      accept: 'image/webp,*/*',
    });
    if (!result.buffer) {
      return res.status(502).json({ ok: false, error: 'Empty image response' });
    }
    res.setHeader('Content-Type', result.contentType || 'image/webp');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.setHeader('X-Cache', 'BYPASS');
    res.send(result.buffer);
  } catch (err) {
    handleUpstreamError(res, err, { path: `/v1/images/${sub}` });
  }
});

app.use((_req, res) => {
  res.status(404).json({
    ok: false,
    error: 'Not found',
    service: 'veil-streamed-sports',
    endpoints: [
      'GET /health',
      'GET /v1/sports',
      'GET /v1/matches/live',
      'GET /v1/matches/live/popular',
      'GET /v1/matches/all',
      'GET /v1/matches/all-today',
      'GET /v1/matches/:sport',
      'GET /v1/matches/:sport/popular',
      'GET /v1/stream/:source/:id',
      'GET /v1/images/*',
    ],
  });
});

app.listen(PORT, HOST, () => {
  logger.info(
    { host: HOST, port: PORT, upstream: UPSTREAM_BASE },
    'veil-streamed-sports listening (isolated; does not touch cinepro)',
  );
});
