<p align="center">
  <img src="logo.png" alt="Veil" width="112" height="112" />
</p>

<h1 align="center">Veil</h1>

<p align="center">
  <strong>Browse. Resolve. Watch — on your Android device.</strong>
</p>

<p align="center">
  <a href="https://github.com/dikshadamahe/veil-android"><img src="https://img.shields.io/badge/Veil-android-0A0613?style=flat-square&logo=github&logoColor=white&labelColor=1a1a2e" alt="Veil on GitHub" /></a>
  &nbsp;
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
  &nbsp;
  <img src="https://img.shields.io/badge/release-3.0.0-7C3AED?style=flat-square&labelColor=1a1a2e" alt="Version" />
</p>

---

> **Aggregator only.** Veil does not host video, store media, or act as a CDN. It connects your TMDB catalog to in-app playback by asking a self-hosted **[cinepro-org/core](https://github.com/cinepro-org/core)** resolver for playable sources — then opens each `source.url` in **`video_player`** (ExoPlayer on Android).

---

## At a glance

| | |
|:---|:---|
| **Discover** | Trending, search, detail pages — posters and metadata from **TMDB** (direct from the app). |
| **Resolve** | One HTTP GET to **cinepro-org/core** returns every provider that has the title, with proxy URLs already absolute. No client-side scraping, WebView hooks, or SSE pipeline. |
| **Play** | The player fetches sources inline, auto-fallbacks on failure, and exposes provider-grouped source switching, quality variants, resume, continue watching, and optional online subtitles. |

UI follows the **[xp-technologies-dev/p-stream](https://github.com/xp-technologies-dev/p-stream)** web reference — Flutter widgets mapped from the original `.tsx` sources.

---

## Architecture

```mermaid
flowchart TB
  subgraph client["Veil · Flutter Android"]
    UI["Screens\nHome · Search · Detail · Player"]
    TMDB["TmdbService"]
    OMSS["StreamService\nOMSS v1.0 client"]
    VP["video_player · ExoPlayer"]
    UI --> TMDB
    UI --> OMSS
    UI --> VP
  end

  subgraph external["External services"]
    TAPI[("TMDB API\nmetadata")]
    CORE["cinepro-org/core\n:3001 · OMSS v1.0"]
    CDN[("Streaming CDNs")]
  end

  TMDB -->|"GET /3/*"| TAPI
  OMSS -->|"GET /v1/movies/{id}\nGET /v1/tv/{id}/seasons/{s}/episodes/{e}"| CORE
  CORE -->|"sources[] + subtitles[]\nabsolute /v1/proxy?data=… URLs"| OMSS
  VP -->|"VideoPlayerController.networkUrl(source.url)"| CORE
  CORE -->|"GET /v1/proxy?data=…\nReferer · Origin · UA set server-side"| CDN
```

| Component | Role |
|-----------|------|
| **Flutter app** | TMDB browse + OMSS resolver client + local Hive storage (progress, bookmarks, history). |
| **[cinepro-org/core](https://github.com/cinepro-org/core)** | Self-hosted **OMSS v1.0** resolver on port `3001`. Crawls 14 built-in providers and returns a populated `sources[]`. |
| **Proxy** | `GET /v1/proxy?data={base64url}` — headers injected server-side; the app never sets `Referer` / `Origin` / `User-Agent` per provider. |

**Built-in providers:** CineSu · FshareTV · Icefy · Peachify · Popr · MafiaEmbed · Tulnex · VidApi · Videasy · VidNest · VidRock · VidSrc · VidZee · VixSrc

---

## Playback flow

There is no separate “finding sources” screen. Tapping **Play** opens the player, which resolves sources and starts playback in one place — with inline loading, retry, and source switching.

```mermaid
sequenceDiagram
  actor User
  participant App as Veil Player
  participant Core as cinepro-org/core
  participant Exo as video_player / ExoPlayer

  User->>App: Play title
  App->>Core: GET /v1/movies/{tmdbId}<br/>or /v1/tv/.../episodes/{e}
  Core-->>App: OMSS JSON · sources[] · subtitles[]
  App->>Exo: initialize(source.url, formatHint from source.type)
  Exo->>Core: stream via /v1/proxy?data=…
  Core-->>Exo: HLS / MP4 bytes
  Note over App,Exo: Resume seek · auto-fallback ·<br/>provider / quality picker

  opt User switches source
    User->>App: Pick another provider
    App->>Exo: dispose + re-initialize new source.url
  end
```

---

## Stack

Flutter · Riverpod · go_router · Hive · video_player (ExoPlayer) · TMDB · cinepro-org/core (OMSS v1.0)

Adaptive shell: bottom nav on phones, navigation rail on tablets and TV-sized layouts (`windowClass` breakpoints).

---

## Backend API

The resolver is **[cinepro-org/core](https://github.com/cinepro-org/core)** (OMSS v1.0) on **port 3001**:

```bash
# Health
curl http://YOUR_HOST:3001/v1/health

# Movie sources
curl 'http://YOUR_HOST:3001/v1/movies/550'

# TV episode sources
curl 'http://YOUR_HOST:3001/v1/tv/1399/seasons/1/episodes/1'
```

Example response:

```json
{
  "responseId": "5b3e…",
  "expiresAt": "2026-06-05T18:30:00Z",
  "sources": [
    {
      "url": "http://YOUR_HOST:3001/v1/proxy?data=eyJ…",
      "type": "hls",
      "quality": "1080p",
      "audioTracks": [{ "language": "en", "label": "English" }],
      "provider": { "id": "vidsrc", "name": "VidSrc" }
    }
  ],
  "subtitles": [
    {
      "url": "http://YOUR_HOST:3001/v1/proxy?data=…",
      "label": "English",
      "format": "vtt"
    }
  ],
  "diagnostics": []
}
```

`source.url` is already an **absolute proxy URL**. The player passes it to `VideoPlayerController.networkUrl` with a **`formatHint`** derived from OMSS `source.type` (HLS/DASH/etc.) because proxy URLs have no file extension for ExoPlayer to infer. Do not prepend `ORACLE_URL` or inject playback headers in the client.

---

## Build

Secrets stay out of source: pass **`--dart-define`** at build time. Prefer **HTTPS** for production resolver URLs.

```bash
flutter pub get
dart run flutter_launcher_icons   # optional — syncs launcher from logo-circle.png
flutter analyze
flutter build apk --release \
  --dart-define=ORACLE_URL=http://YOUR_HOST:3001 \
  --dart-define=TMDB_TOKEN=YOUR_TMDB_READ_TOKEN
```

**CI / releases:** pushing a `v*` tag (or manual **Release** workflow dispatch) runs `flutter analyze`, builds a **signed** `veil.apk`, and publishes a GitHub Release with `version.json` (for in-app updates).

Required repository secrets for signed releases:

| Secret | Purpose |
|--------|---------|
| `ORACLE_URL` (or variable) | Resolver base URL baked into the APK |
| `TMDB_TOKEN` or `TMDB_READ_TOKEN` | TMDB read token |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.jks` / `.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

**In-app updates:** Settings → **App** → **Check for updates** polls `dikshadamahe/veil-android` GitHub Releases. Newer APKs install on top of older ones when they share the same `applicationId` and signing certificate and the new `versionCode` is higher. Bump `version:` in `pubspec.yaml` (e.g. `1.0.3+4`) before each tagged release.

Generate a one-time upload keystore (do not commit it):

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks   # paste into ANDROID_KEYSTORE_BASE64
```

<details>
<summary><strong>Optional defines</strong> — subtitles, watch rules</summary>

| Define | Purpose |
|--------|---------|
| `WYZIE_API_KEY` | Wyzie subs — **Search online…** in the player. |
| `OPENSUBTITLES_API_KEY` | OpenSubtitles REST key. |
| `OPENSUBTITLES_USERNAME` / `OPENSUBTITLES_PASSWORD` | Account pairing when the API key alone is not enough. |
| `SUBTITLE_HTTP_USER_AGENT` | Override UA for subtitle fetches (default `Veil 1.0.0`). |
| `WATCHED_RATIO` | `position / duration` ratio that marks a title as watched (default `0.90`). |

</details>

---

## Repo layout

| Path | Role |
|------|------|
| `lib/screens/` | Home, search, detail, player, settings, history, my list |
| `lib/services/` | `tmdb_service.dart`, `stream_service.dart` (OMSS client), `app_update_service.dart` |
| `lib/models/` | `media_item.dart`, `omss_source.dart`, `omss_response.dart` |
| `lib/config/` | `app_config.dart`, `app_theme.dart`, `router.dart`, breakpoints |
| `lib/storage/` | Hive — progress, bookmarks, continue watching |
| `android/` | Gradle, manifest, launcher assets |
| `backend/` | **Legacy** — old `providers-api` + `providers-lib` stack. The active resolver is **cinepro-org/core** on the VM, not this folder. Kept for reference. |

---

## Disclaimer

Veil is a **metadata and playback orchestration** tool. You are responsible for backend configuration, provider and TMDB terms, and compliance with applicable law.
