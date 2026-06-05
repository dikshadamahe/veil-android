# Custom embed integration — **LEGACY**

> **This file predates the cinepro-org/core (OMSS v1.0) migration.** The active resolver on the Oracle VM is cinepro; this document is kept for history and to explain where the OMSS shape came from. The "CinePro Core" section in §4 is the only part that still applies and is the one this rewrite expands on.

The rest of the file (VidSrc embed, 2Embed, AutoEmbed) is **not** the source of truth for the deployed resolver anymore. It is preserved only as a reference for sourcerer / embed patterns in `@p-stream/providers`, in case someone needs to revive a Node-side provider outside cinepro.

---

## 1. CinePro Core — **ACTIVE** integration spec

CinePro Core is self-hosted: [https://cinepro.mintlify.app/introduction](https://cinepro.mintlify.app/introduction). There is no fixed global base URL — you deploy your own instance.

The Flutter app talks to CinePro over the **OMSS v1.0** contract. A single HTTP GET per playback returns every working source.

### 1.1 Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET {ORACLE_URL}/v1/health` | Health check (returns `200` if the service is up). |
| `GET {ORACLE_URL}/v1/movies/{tmdbId}` | Movie sources for a TMDB id (numeric). |
| `GET {ORACLE_URL}/v1/tv/{tmdbId}/seasons/{s}/episodes/{e}` | TV episode sources for a TMDB show id, season number, episode number. |
| `GET {ORACLE_URL}/v1/proxy?data={base64url_encoded_json}` | The actual playable stream (m3u8 / mp4). `source.url` in the OMSS response already points here. |

### 1.2 OMSS v1.0 response shape

```json
{
  "responseId": "uuid",
  "expiresAt": "2026-06-05T18:30:00Z",
  "sources": [
    {
      "url": "http://VM_IP:3001/v1/proxy?data=eyJ…",
      "type": "hls" | "mp4",
      "quality": "1080p",
      "audioTracks": [{ "language": "en", "label": "English" }],
      "provider": { "id": "vidsrc", "name": "VidSrc" }
    }
  ],
  "subtitles": [
    {
      "url": "http://VM_IP:3001/v1/proxy?data=…",
      "label": "English",
      "format": "vtt"
    }
  ],
  "diagnostics": []
}
```

Field contract:

| Field | Required | Notes |
|-------|----------|-------|
| `responseId` | yes | UUID; useful for logs and idempotency. |
| `expiresAt` | yes | ISO-8601 timestamp; the response (and the proxy URLs) is no longer valid after this. |
| `sources[]` | yes | Each source has a playable URL. Empty array means "no provider had this title" (HTTP 200, not 404). |
| `sources[].url` | yes | **Absolute** URL — the Flutter app does not prepend anything. |
| `sources[].type` | yes | `hls` or `mp4`. |
| `sources[].quality` | no | Free-form (`"1080p"`, `"720p"`, `"4K"`, etc.). |
| `sources[].audioTracks` | no | Array of `{ language, label }` pairs. |
| `sources[].provider` | yes | `{ id, name }` — what the app shows in the source picker. |
| `subtitles[]` | no | Each entry is `{ url, label, format }`. |
| `diagnostics[]` | no | Free-form diagnostic strings for operator logs. |

### 1.3 Key contract differences from the old providers-api

| Old (providers-api + @p-stream/providers) | New (cinepro-org/core, OMSS v1.0) |
|-------------------------------------------|------------------------------------|
| SSE `/scrape/stream` with `init` / `start` / `update` / `done` / `error` events | One HTTP GET, one JSON response |
| `GET /sources` catalog the app had to fetch on its own | Catalog is embedded in each response (no catalog endpoint) |
| `Referer` / `Origin` / `User-Agent` injected in the Flutter app | Headers are set by the cinepro proxy server-side; app passes none |
| `simple-proxy` (`:3000`) hop for HLS m3u8 fetches | Not needed — proxy URLs are absolute and already have the right headers |
| `sourceOrder` / `embedOrder` / `selectedId` query params | None — the server returns its full `sources[]` |
| 100s scrape timeout, 25s connect timeout | Single HTTP timeout; no SSE keepalive |

### 1.4 The 14 built-in providers

Cinepro runs the following providers server-side. The app does not choose — the server returns whatever is up.

| Provider | `provider.id` |
|----------|---------------|
| CineSu | `cinesu` |
| FshareTV | `fsharetv` |
| Icefy | `icefy` |
| Peachify | `peachify` |
| Popr | `popr` |
| MafiaEmbed | `mafiaembed` |
| Tulnex | `tulnex` |
| VidApi | `vidapi` |
| Videasy | `videasy` |
| VidNest | `vidnest` |
| VidRock | `vidrock` |
| VidSrc | `vidsrc` |
| VidZee | `vidzee` |
| VixSrc | `vixsrc` |

### 1.5 Deployment notes (carry over from the original section)

- **Base URL:** Whatever host/port you choose — the example VM uses `http://VM_IP:3001`.
- **Authentication:** No mandatory API key in the OMSS spec. Treat cinepro as a **private local** service. Add your own reverse-proxy auth if exposed beyond localhost.
- **Self-hosting warning:** Cinepro Core is not secure for public hosting by default.

### 1.6 What the Flutter app does (new contract)

```text
GET {ORACLE_URL}/v1/movies/{tmdbId}
  -> { sources: [ { url, type, quality, provider: { id, name }, audioTracks, … } ], subtitles: [ … ] }

Or for TV:
GET {ORACLE_URL}/v1/tv/{tmdbId}/seasons/{s}/episodes/{e}
  -> same shape
```

The app:
1. Renders the `sources[]` in a "Sources" sheet (each row's name comes from `source.provider.name`).
2. Picks the first `sources[0]` by default and hands `source.url` to `media_kit` via `Media(url, httpHeaders: {})`.
3. Sends `source.url` to the player; no extra headers, no `Referer`, no `Origin`.
4. Loads any `subtitles[]` URLs that match a language the user enables.

---

## 2. VidSrc embed (`vidsrc-embed.ru`) — **LEGACY reference**

This section documents the old `vidsrc-embed.ru` embed URL patterns, kept as a reference for anyone building a Node-side `@p-stream/providers` sourcerer outside cinepro. Not used by the Flutter app's current resolver.

### 2.1 Movie embed

- `https://vidsrc-embed.ru/embed/movie/{imdb|tmdb}`
- Query params: `imdb` or `tmdb` (one of), `sub_url`, `ds_lang`, `autoplay`

### 2.2 TV episode embed

- `https://vidsrc-embed.ru/embed/tv/{imdb|tmdb}/{season}-{episode}`
- Query params: `imdb` or `tmdb`, `season`, `episode`, `sub_url`, `ds_lang`, `autoplay`, `autonext`

### 2.3 JSON discovery feeds (optional)

- `https://vidsrc-embed.ru/movies/latest/page-{N}.json`
- `https://vidsrc-embed.ru/tvshows/latest/page-{N}.json`
- `https://vidsrc-embed.ru/episodes/latest/page-{N}.json`

---

## 3. 2Embed.cc — **LEGACY reference**

Same status as §2. Iframe patterns and `api.2embed.cc` JSON endpoints preserved for reference only.

| Mode | URL pattern |
|------|----------------|
| Movie by IMDb | `https://www.2embed.cc/embed/{imdbId}` |
| Movie by TMDB | `https://www.2embed.cc/embed/{tmdbNumericId}` |
| TV episode by IMDb | `https://www.2embed.cc/embedtv/{imdbId}&s={season}&e={episode}` |
| TV episode by TMDB | `https://www.2embed.cc/embedtv/{tmdbId}&s={season}&e={episode}` |
| Full season | `https://www.2embed.cc/embedtvfull/{imdbId}` (or `{tmdbId}`) |

---

## 4. AutoEmbed — **no change**

There is no stable public AutoEmbed API spec in scope. Cinepro handles it (or doesn't) on the server; nothing in the Flutter app configures AutoEmbed.
