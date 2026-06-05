# providers-api — **LEGACY**

> **This folder is no longer the deployed resolver.** The active resolver on the Oracle VM is **`cinepro-org/core`** (OMSS v1.0). The folder is kept for history and as a reference for the legacy SSE / blocking scrape shape. See the project `README.md` and `HANDOFF.md` for the current architecture.

`providers-api` was an Express service on **port 3001** that wrapped **`@p-stream/providers`** (`targets.NATIVE`). The Flutter app pointed **`ORACLE_URL`** at this service. It exposed:

- `GET /health` — health check
- `GET /sources` — catalog of `sources[]` and `embeds[]` (Sourcerer ids from `@p-stream/providers`)
- `GET /scrape?…` — blocking single-shot scrape with `sourceOrder` / `embedOrder` / `selectedId` / `selectedType` / `parentSourceId` query params
- `GET /scrape/stream?…` — SSE scrape with `init` / `start` / `update` / `done` / `error` events, anti-buffering keepalives

## Why we moved off it

- The user is now running a single self-hosted **`cinepro-org/core`** resolver (OMSS v1.0) on the same port (`:3001`) that returns the full `sources[]` in one HTTP GET.
- The 14 cinepro providers (CineSu, FshareTV, Icefy, Peachify, Popr, MafiaEmbed, Tulnex, VidApi, Videasy, VidNest, VidRock, VidSrc, VidZee, VixSrc) replace the per-source @p-stream/providers list.
- `source.url` from cinepro is already an absolute proxy URL — the Flutter app no longer needs to inject `Referer` / `Origin` / `User-Agent`, no longer needs to fetch HLS m3u8 through a separate `simple-proxy` hop, and no longer needs an SSE pipeline.

## New contract (what the Flutter app talks to now)

```
GET {ORACLE_URL}/v1/movies/{tmdbId}
GET {ORACLE_URL}/v1/tv/{tmdbId}/seasons/{s}/episodes/{e}
GET {ORACLE_URL}/v1/proxy?data={base64url_encoded_json}
GET {ORACLE_URL}/v1/health
```

Response shape (OMSS v1.0):

```json
{
  "responseId": "uuid",
  "expiresAt": "2026-06-05T18:30:00Z",
  "sources": [
    {
      "url": "http://VM_IP:3001/v1/proxy?data=…",
      "type": "hls" | "mp4",
      "quality": "1080p",
      "audioTracks": [{ "language": "en", "label": "English" }],
      "provider": { "id": "vidsrc", "name": "VidSrc" }
    }
  ],
  "subtitles": [
    { "url": "http://VM_IP:3001/v1/proxy?data=…", "label": "English", "format": "vtt" }
  ],
  "diagnostics": []
}
```

## Files in this folder

- `src/server.js` — Express entry; `/health`, `/sources`, `/scrape`, `/scrape/stream`
- `src/providers.js` — wraps `makeProviders({ target: targets.NATIVE })`
- `src/normalize.js` — normalizes a `@p-stream/providers` `runAll` output into the JSON shape the Flutter app consumed
- `src/config.js` — reads `PORT`, `REQUEST_TIMEOUT_MS`, `SIMPLE_PROXY_URL`
- `docs/CUSTOM_EMBED_INTEGRATION.md` — notes on third-party embed integration (most of it predates cinepro; the CinePro section in §4 is the only part that still applies, and is superseded by this README + `HANDOFF.md`)

## When to delete

Once the OMSS migration in the Flutter app ships and there are no more references to `StreamService.scrapeStream`, `StreamService.scrapeBlocking`, `StreamService.scrapeSingleSource`, `StreamService.fetchCatalog`, `ScrapeEvent`, or `ScrapeSourceDefinition`, this folder (and `backend/providers-lib/`) can be deleted.
