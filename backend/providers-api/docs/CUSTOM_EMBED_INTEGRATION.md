# Integrating third-party embeds (VidSrc embed, 2Embed, AutoEmbed, CinePro)

Veil’s Android app only talks to **`providers-api`** (`ORACLE_URL`). That service calls **`@p-stream/providers`** `runAll({ media, sourceOrder? })`. **New sites are not configured in Flutter or in this Express file alone** — each one needs a **sourcerer** (TypeScript) in the providers library that returns the shape `normalizeRunOutput` already expects (stream and/or embeds).

Your Oracle **`/sources`** JSON is the source of truth for which **source** `id` values exist (e.g. `vidlink`, `fedapi`, …) and which **embed** ids exist (e.g. `autoembed-english`). `SCRAPE_SOURCE_ORDER` uses **source** ids only.

---

## 1. VidSrc embed (`vidsrc-embed.ru`) — API reference for implementers

Public embed base (documented by operator):

- **Host:** `https://vidsrc-embed.ru`

These URLs are **iframe embed pages**, not guaranteed direct HLS files. A sourcerer usually returns them as **`embeds: [{ embedId, url }]`** so an embed resolver can extract playback, unless you parse the player and emit a **`stream`** object.

### 1.1 Movie embed

**Path / query:** `https://vidsrc-embed.ru/embed/movie`

| Parameter | Required | Notes |
|-----------|------------|--------|
| `imdb` or path `…/movie/{tt…}` | one of imdb / tmdb | IMDb `tt…` |
| `tmdb` or path `…/movie/{id}` | one of imdb / tmdb | TMDB numeric id |
| `sub_url` | no | URL-encoded `.srt` or `.vtt`; must be **CORS**-reachable from the embed |
| `ds_lang` | no | Default subtitle language, ISO 639 code |
| `autoplay` | no | `1` or `0` (default on) |

**Examples**

```http
https://vidsrc-embed.ru/embed/movie/tt5433140
https://vidsrc-embed.ru/embed/movie?imdb=tt5433140
https://vidsrc-embed.ru/embed/movie?imdb=tt5433140&ds_lang=de
https://vidsrc-embed.ru/embed/movie?imdb=tt5433140&sub_url=https%3A%2F%2Fvidsrc.me%2Fsample.srt&autoplay=1
https://vidsrc-embed.ru/embed/movie/385687
https://vidsrc-embed.ru/embed/movie?tmdb=385687
https://vidsrc-embed.ru/embed/movie?tmdb=385687&ds_lang=de
https://vidsrc-embed.ru/embed/movie?tmdb=385687&sub_url=https%3A%2F%2Fvidsrc.me%2Fsample.srt&autoplay=1
```

### 1.2 TV show (series) vs episode embed

**Base:** `https://vidsrc-embed.ru/embed/tv`

| Parameter | Required | Notes |
|-----------|------------|--------|
| `imdb` or path `…/tv/{tt…}` | one of imdb / tmdb | Series-level |
| `tmdb` or path `…/tv/{id}` | one of imdb / tmdb | Series TMDB id |
| `season` | **yes** for a specific episode | Episode context |
| `episode` | **yes** for a specific episode | Episode context |
| `sub_url` | no | Same CORS rules as movie |
| `ds_lang` | no | ISO 639 |
| `autoplay` | no | `1` / `0` |
| `autonext` | no | `1` / `0` (default **off**) |

**Examples (note `&` between query params)**

```http
https://vidsrc-embed.ru/embed/tv/tt0944947
https://vidsrc-embed.ru/embed/tv?imdb=tt0944947
https://vidsrc-embed.ru/embed/tv?imdb=tt0944947&ds_lang=de
https://vidsrc-embed.ru/embed/tv/1399
https://vidsrc-embed.ru/embed/tv?tmdb=1399&ds_lang=de
https://vidsrc-embed.ru/embed/tv/tt0944947/1-1
https://vidsrc-embed.ru/embed/tv?imdb=tt0944947&season=1&episode=1
https://vidsrc-embed.ru/embed/tv?imdb=tt0944947&season=1&episode=1&ds_lang=de
https://vidsrc-embed.ru/embed/tv?imdb=tt0944947&season=1&episode=1&sub_url=https%3A%2F%2Fvidsrc.me%2Fsample.srt&autoplay=1&autonext=1
https://vidsrc-embed.ru/embed/tv/1399/1-1
https://vidsrc-embed.ru/embed/tv?tmdb=1399&season=1&episode=1
https://vidsrc-embed.ru/embed/tv?tmdb=1399&season=1&episode=1&ds_lang=de
https://vidsrc-embed.ru/embed/tv?tmdb=1399&season=1&episode=1&sub_url=https%3A%2F%2Fvidsrc.me%2Fsample.srt&autoplay=1&autonext=1
```

### 1.3 JSON discovery feeds (optional for catalog UIs, not required for Veil scrape)

Replace `PAGE_NUMBER` with an integer ≥ 1.

```http
https://vidsrc-embed.ru/movies/latest/page-1.json
https://vidsrc-embed.ru/tvshows/latest/page-1.json
https://vidsrc-embed.ru/episodes/latest/page-1.json
```

### 1.4 Adding this in `@p-stream/providers`

1. Fork **[xp-technologies-dev/providers](https://github.com/xp-technologies-dev/providers)**.
2. Add a sourcerer (e.g. `vidsrcembed`) that, from `ctx.media`, builds the **movie** or **tv + season + episode** URL above (prefer TMDB when `ctx.media.tmdbId` is set; use `imdbId` with `tt` prefix when required).
3. Return **`embeds`** pointing at the iframe URL, with an `embedId` your pipeline can resolve—or implement stream extraction if you have a stable parser.
4. Register for `targets.NATIVE`, bump dependency in **`backend/providers-api`**, redeploy Oracle, verify `GET /sources` lists the new **`id`**.

---

## 2. 2Embed.cc — embed URLs + JSON API (operator spec)

### 2.1 Iframe embeds

| Mode | URL pattern |
|------|----------------|
| Movie by IMDb | `https://www.2embed.cc/embed/{imdbId}` e.g. `…/embed/tt10676048` |
| Movie by TMDB | `https://www.2embed.cc/embed/{tmdbNumericId}` e.g. `…/embed/609681` |
| TV episode by IMDb | `https://www.2embed.cc/embedtv/{imdbId}&s={season}&e={episode}` |
| TV episode by TMDB | `https://www.2embed.cc/embedtv/{tmdbId}&s={season}&e={episode}` |
| Full season by IMDb | `https://www.2embed.cc/embedtvfull/{imdbId}` |
| Full season by TMDB | `https://www.2embed.cc/embedtvfull/{tmdbId}` |

### 2.2 JSON API (`api.2embed.cc`)

Endpoints support **`imdb_id` / `tmdb_id`** where applicable (per operator docs).

| Purpose | Endpoint |
|---------|-----------|
| Movie details | `https://api.2embed.cc/movie?imdb_id={tt…}` (and/or tmdb params per their spec) |
| Trending movies | `https://api.2embed.cc/trending?time_window={day\|week\|month}&page={1…N}` |
| Search movies | `https://api.2embed.cc/search?q={keyword}&page={1…N}` |
| Similar movies | `https://api.2embed.cc/similar?imdb_id={tt…}&page={1…N}` |
| TV details | `https://api.2embed.cc/tv?imdb_id={tt…}` |
| Trending TV | `https://api.2embed.cc/trendingtv?time_window={day\|week\|month}&page={1…N}` |
| Search TV | `https://api.2embed.cc/searchtv?q={keyword}&page={1…N}` |
| Similar TV | `https://api.2embed.cc/similartv?imdb_id={tt…}&page={1…N}` |
| Season details | `https://api.2embed.cc/season?imdb_id={tt…}&season={1…N}` |

**Implementation:** same as §1 — new sourcerer id (e.g. `twoembed`), map `ctx.media` → URLs or API, return `embeds` / `stream` as supported by your embed pipeline.

---

## 3. AutoEmbed — **no change**

There is **no stable public AutoEmbed API spec** in scope here, and existing Oracle **`/sources`** / embed ids already cover typical flows (`autoembed-english`, etc.).

**Policy for this repo:** do **not** require AutoEmbed-specific app or `providers-api` changes until an upstream sourcerer + docs exist. Keep **`SCRAPE_SOURCE_ORDER`** aligned with **`GET /sources`** **source** ids only.

---

## 4. CinePro Core — docs-grounded integration notes

CinePro Core is **self-hosted** ([introduction](https://cinepro.mintlify.app/introduction.md)); there is **no fixed global base URL** in the docs.

| Topic | Docs-grounded behavior |
|-------|-------------------------|
| **Base URL** | Whatever you deploy, e.g. `http://localhost:<PORT>` (often `3000` in examples)—**you** choose host/port. |
| **Authentication** | **No mandatory API key / token** described for Core in the intro; treat as a **private local** service. You may add **your own** reverse proxy auth if exposed beyond localhost. Docs warn Core is **not secure for public hosting by default**. |
| **Movie sources** | **`GET /v1/movies/{tmdbId}`** — TMDB id in path ([Movies](https://cinepro.mintlify.app/core/api-reference/content/get-streaming-sources-for-a-movie.md)). |
| **TV episode sources** | See [TV Shows](https://cinepro.mintlify.app/core/api-reference/content/get-streaming-sources-for-a-tv-episode.md) in the docs index for the OMSS path shape. |
| **Response shape** | OMSS-style: includes **`sources`**, **`subtitles`**, **`responseId`**, **`expiresAt`**, often **proxy URLs** (`/v1/proxy?data=…`), not raw CDN links. Exact field names follow the OpenAPI spec—not reprinted here. |

**Illustrative JSON (structure only — not a verbatim doc excerpt):**

```json
{
  "responseId": "uuid",
  "expiresAt": "2026-01-15T18:00:00Z",
  "sources": [
    {
      "url": "/v1/proxy?data=…",
      "type": "hls",
      "quality": "1080p",
      "provider": { "id": "…", "name": "…" }
    }
  ],
  "subtitles": [],
  "diagnostics": []
}
```

**Integration with Veil:** same three approaches as before — **bridge in `providers-api`**, **sourcerer in `providers`**, or **sidecar** Core on the VM; map OMSS → Veil’s existing scrape result JSON.

---

## 5. Checklist before coding

- [ ] Confirm legal/ToS for each third-party API you call from the VM.
- [ ] Decide: **fork `xp-technologies-dev/providers`** vs **bridge in `providers-api` only** (CinePro‑style).
- [ ] For each site: **curl** examples (movie + TV) saved in the issue/PR.
- [ ] After deploy: `curl http://<VM>:3001/sources` includes new **`id`** values.
- [ ] Update app build: `--dart-define=SCRAPE_SOURCE_ORDER=…` listing those ids first.

---

## 6. Quick reference: Oracle `GET /sources`

Use only **source** `id` values from **your** JSON for `SCRAPE_SOURCE_ORDER` (e.g. `vidlink`, `fedapi`, `fedapidb`, …). **Embeds** (e.g. `autoembed-english`) are separate and are not passed as `sourceOrder`.
