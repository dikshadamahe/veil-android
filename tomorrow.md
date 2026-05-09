## Tomorrow Plan

### Current backend state

- `providers-api` is now using the correct architecture:
  - `providers-lib -> simple-proxy -> providers-api -> m3u8 proxy -> app`
- Broken direct backend integrations were removed:
  - `fedapi`
  - `fedapidb`
  - static Turnstile helper flow
- `vidlink` is confirmed working again through `providers-api`
- HLS output now includes:
  - `playlist`
  - `proxiedPlaylist`
  - `playbackUrl`
  - `captions`
- `playbackUrl` prefers `proxiedPlaylist`
- Flutter app already has support for:
  - `proxiedPlaylist`
  - `playbackUrl`
  - file-quality selection UI

### VM priorities

#### 1. Add more working providers

Goal:
- increase source diversity
- reduce no-stream cases
- improve reliability

Target providers to evaluate first:
- `vixsrc`
- `vidsrc` variants
- `embedsu`
- `consumet`-compatible providers
- working mirrors already present in `providers-lib`

What to do on VM:
- inspect current `providers-lib` source list
- enable only providers that are still alive
- test movie flow source-by-source
- test TV flow source-by-source
- keep a shortlist of actually working providers
- remove or disable providers that consistently fail

Suggested order:
1. `vidlink`
2. `vidrock`
3. `vidsrcembed`
4. `twoembed`
5. `embedsu`
6. `vixsrc` if added
7. `consumet`-based options if stable

Definition of working:
- returns a real stream through `providers-api`
- works behind `simple-proxy`
- does not require browser-only anti-bot state

#### 2. Add real source racing

Current problem:
- providers are effectively tried in sequence from the app perspective
- this increases wait time when early sources fail

Target behavior:
- run multiple providers in parallel
- first valid stream wins
- cancel or ignore slower losers

Backend work:
- patch `providers-api` route logic so selected providers run concurrently
- return first good result immediately
- optionally continue collecting diagnostics in background

Desired model:
- fast lane:
  - `vidlink`
  - `vidrock`
  - `vidsrcembed`
- optional second wave:
  - slower or less reliable providers

#### 3. Add stream health cache

Goal:
- dynamic provider ordering based on reality

Track per provider:
- `successCount`
- `failureCount`
- `avgLatencyMs`
- `lastSuccessAt`
- `lastFailureAt`

Use it for:
- dynamic source ordering
- deprioritizing failing providers
- preferring recently healthy providers

Implementation idea:
- small JSON or Redis-backed cache on VM
- update after each scrape attempt
- ranking formula combines:
  - manual base priority
  - success rate
  - recent latency
  - last success freshness

#### 4. Add HLS variant parsing

Goal:
- website-style quality picker for HLS streams

Current:
- HLS returns one `playlist`
- app can play it, but manual variant selection is limited

Target:
- parse master playlist
- expose:
  - `1080p`
  - `720p`
  - `480p`
  - audio/subtitle variant info if useful

Backend output enhancement:
- keep:
  - `playlist`
  - `proxiedPlaylist`
- add:
  - `variants`
  - `defaultVariant`

### UI priorities

#### 1. Make source choice visible

- show actual winning source in player
- optionally expose a manual source switch sheet
- mark source health:
  - fast
  - backup
  - unstable

#### 2. Improve quality selection UI

- keep current file-quality picker
- add HLS variant picker when `variants` exist
- display active quality clearly in player settings

#### 3. Improve loading UX

- show provider race state:
  - trying source A / B / C
- show first playable source quickly
- avoid blocking on dead providers

#### 4. Add fallback stream handoff UI

- preserve optional browser-assisted `workerUrl` flow
- only use for protected sources that cannot be solved on VM

### Explicit non-goals

- do not restart direct Finger backend scraping
- do not reintroduce static Turnstile token hacks
- do not make the backend depend on browser-only anti-bot state

### Recommended execution order

1. Validate and expand working providers on VM
2. Add provider racing
3. Add provider health cache
4. Add HLS variant parsing
5. Patch UI for source visibility and HLS quality selection

### Notes for next chat

- VM backend path:
  - `~/apps/pstream-android/backend/providers-lib`
  - `~/apps/pstream-android/backend/providers-api`
- local Flutter app already understands:
  - `proxiedPlaylist`
  - `playbackUrl`
  - `qualities`
- next backend chat should focus on VM changes only
