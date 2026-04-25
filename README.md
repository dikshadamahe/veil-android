# Veil

![Veil logo](logo.png)

**Veil** is a minimal Android streaming client: browse TMDB metadata, resolve streams through your own small backend, and play in-app with **media_kit**. It is **aggregator-only**—it does not host media, store video files, or operate as a CDN.

**Repository:** [github.com/dikshadamahe/veil-android](https://github.com/dikshadamahe/veil-android)

---

## What you get

| Area | Behavior |
|------|----------|
| **Discovery** | Trending and search (movies & TV), detail pages, posters from TMDB |
| **Playback** | HLS/DASH-style streams via **media_kit**, headers from your resolver, resume & bookmarks (Hive) |
| **Resolver** | SSE or blocking scrape against **providers-api**; optional **simple-proxy** for CDN-friendly fetches |
| **History** | Watch history grid on device; continue-watching style flows where implemented |

Design and behavior are aligned with the **xp-technologies-dev/p-stream** web reference where the team maps widgets to the original `.tsx` sources.

---

## Architecture

```text
┌─────────────────────┐
│   Veil (Flutter)    │
│   Android client    │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
┌────────────┐  ┌──────────────┐
│ providers- │  │ TMDB API     │
│ api :3001  │  │ (read token) │
└─────┬──────┘  └──────────────┘
      │
      ▼
┌────────────┐
│ simple-    │
│ proxy :3000
└─────┬──────┘
      ▼
┌────────────┐
│ Streaming   │
│ CDNs        │
└────────────┘
```

- **providers-api** — Node + Express wrapper around `@p-stream/providers`; lives in this repo under `backend/providers-api`.
- **simple-proxy** — Run separately (e.g. on the same VM) for CORS/header-sensitive fetches. Reference: [xp-technologies-dev/simple-proxy](https://github.com/xp-technologies-dev/simple-proxy).
- **Providers package** — Install from [xp-technologies-dev/providers](https://github.com/xp-technologies-dev/providers); the npm name remains `@p-stream/providers`.
- **Scraper ids / Oracle** — See [`backend/providers-api/README.md`](backend/providers-api/README.md) and [`backend/providers-api/docs/CUSTOM_EMBED_INTEGRATION.md`](backend/providers-api/docs/CUSTOM_EMBED_INTEGRATION.md) (vidsrc-embed.ru, 2Embed.cc, AutoEmbed unchanged, CinePro Core OMSS).

---

## Tech stack

| Layer | Choice |
|-------|--------|
| App | Flutter 3.x, Dart |
| State & routing | Riverpod, go_router |
| Local data | Hive |
| Player | media_kit, media_kit_video |
| Backend | Node.js 20, pnpm, Express |

---

## Repo layout

```text
backend/providers-api/   Health, /scrape, /scrape/stream (SSE) + README for operators
android/                 Android embedding, Gradle, manifests
lib/                     Flutter app (screens, services, widgets)
test/                    Widget / unit tests
logo.png                 Brand mark (README + icon pipeline)
```

---

## Backend: local run

From `backend/providers-api`:

```bash
pnpm install
pnpm start
```

Default listen port: **3001**.

```bash
curl http://127.0.0.1:3001/health
```

Example movie scrape:

```bash
curl "http://127.0.0.1:3001/scrape?type=movie&tmdbId=550&title=Fight%20Club&year=1999"
```

Point the app at your deployed host with `--dart-define=ORACLE_URL=...` (see below).

---

## Android: build & run

The app reads **runtime** configuration (no secrets in source):

| Define | Purpose |
|--------|---------|
| `ORACLE_URL` | Base URL of **providers-api** (e.g. `http://YOUR_VM_IP:3001`) |
| `SCRAPE_SOURCE_ORDER` | Optional — comma-separated **source** `id`s from your Oracle `GET /sources` (see `backend/providers-api/README.md` and `docs/CUSTOM_EMBED_INTEGRATION.md`). Default: `vidlink,fedapi,fedapidb,ridomovies,rgshows,vidrock`. Empty define → library default order. |
| `TMDB_TOKEN` | TMDB **read** access token |
| `WYZIE_API_KEY` | Optional — [Wyzie Subs](https://sub.wyzie.io/redeem) key for **Search online…** subtitles in the player |
| `OPENSUBTITLES_API_KEY` | Optional — [OpenSubtitles.com](https://www.opensubtitles.com/en/consumers) REST **Api-Key** (search + download) |
| `OPENSUBTITLES_USERNAME` / `OPENSUBTITLES_PASSWORD` | Optional — OpenSubtitles **account**; improves `/download` success when API key alone is not enough |
| `SUBTITLE_HTTP_USER_AGENT` | Optional override for subtitle HTTP requests (default `Veil 1.0.0`) |

**Release APK example:**

```bash
flutter pub get
flutter build apk --release \
  --dart-define=ORACLE_URL=http://YOUR_VM_IP:3001 \
  --dart-define=TMDB_TOKEN=YOUR_TMDB_READ_ACCESS_TOKEN \
  --dart-define=WYZIE_API_KEY=YOUR_WYZIE_KEY \
  --dart-define=OPENSUBTITLES_API_KEY=YOUR_OS_API_KEY
```

Store subtitle keys in **GitHub Actions secrets** (or local env only); do not commit them. Release workflow passes them through when `WYZIE_API_KEY` / `OPENSUBTITLES_*` secrets are set.

Use **HTTPS** in production when your infrastructure supports it; cleartext is only appropriate for controlled lab/VPN setups.

---

## Development notes

- **Upstream code** for providers and proxy: prefer `xp-technologies-dev/*` on GitHub over legacy `p-stream/*` naming in old docs.
- **Git identity / remotes** for collaborators: see `switch-dev.sh` (when not gitignored locally) or your team’s SSH host aliases for `github-diksha` / `github-pracheer`.
- **Flutter analyze** should stay clean before merge; CI may run `flutter analyze` on `main` and PRs.

---

## Disclaimer

Veil is a **metadata and playback orchestration** tool. You are responsible for how you configure backends, respect TMDB and provider terms, and comply with applicable law.
