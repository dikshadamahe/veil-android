# Backend Stream Context

## Purpose

This file is the full handoff for the current Oracle VM streaming backend state after the stream-service refactor.

Use this document in a new chat when you need exact context on:

- what changed in `/stream`
- which provider paths were removed
- which provider paths still work
- how cache behaves
- how client-supplied worker URLs are handled
- what the Flutter app should expect from the backend now

This document reflects the backend state validated on **2026-05-06**.

---

## High-Level Outcome

The old experimental backend integrations for:

- `FedAPI`
- `XPrime / Finger`
- static turnstile token replay

were removed from the active stream path because they were not viable server-side.

The backend now uses a **stable minimal model**:

1. If the client provides a valid `workerUrl`, the backend uses that first.
2. Otherwise the backend falls back to working public providers.
3. The `/stream` response is simplified to a single playable URL payload.

Current result:

- worker-assisted flow works
- `vidlink` fallback works
- cache no longer breaks worker override flow
- stream output is simpler for app integration

---

## Why FedAPI / XPrime Were Abandoned

### FedAPI

FedAPI was tested using Febbox-style UI tokens. The token path was partially valid, but the backend did not reliably return playable streams. In observed tests, responses often contained subtitles but empty `streams`.

That meant:

- token acceptance was not the main issue
- stream extraction was still unreliable
- backend-only integration was not production-safe

### XPrime / Finger

The backend path:

- `https://backend.xprime.tv/finger`

was discovered to be protected by Cloudflare turnstile.

Important findings:

- turnstile token is short-lived
- token is browser-bound
- token is likely IP-bound or session-bound
- replaying it from the Oracle VM returned `403`
- browser-captured worker URLs did work

Conclusion:

- direct backend calls to XPrime / Finger were **not viable**
- browser-assisted worker URL ingestion **was viable**

That is why the system now accepts browser-provided worker URLs instead of trying to solve Finger/XPrime from the VM.

---

## Current Active Stream Design

### Priority order

The active movie-provider order is now:

1. `worker`
2. `vidlink`
3. `vidrock`

`vixsrc` still exists in code but is disabled by config.

### What each provider means

#### `worker`

This is not a scraper. It is a pass-through provider that accepts a client-provided `workers.dev` URL and returns it as the playable stream.

Use case:

- browser captures a working worker URL from XPrime/Finger flow
- app passes it into backend
- backend prioritizes it over normal fallback providers

#### `vidlink`

Current main fallback provider. This is the default path when no worker URL is supplied.

#### `vidrock`

Secondary fallback provider after `vidlink`.

---

## Current `/stream` API

### Request

```http
GET /stream?tmdbId=<id>
GET /stream?tmdbId=<id>&workerUrl=<encoded workers.dev url>
```

### Current response shape

```json
{
  "url": "https://playable-url-or-workers-dev-url",
  "provider": "vidlink",
  "latency": 1259
}
```

Only these fields are returned now:

- `url`
- `provider`
- `latency`

This was intentionally simplified from the older richer response shape.

---

## Worker URL Validation Rules

The backend validates `workerUrl` before using it.

Rules:

- must be a valid URL
- hostname must include `workers.dev`
- query string must contain `v=`

If validation fails, the request is rejected.

This prevents random unsafe URLs from being treated as stream inputs.

---

## Cache Behavior

### Old problem

Originally, `/stream?tmdbId=550` would cache a normal provider result, such as `vidlink`.

Then if the client later called:

```http
GET /stream?tmdbId=550&workerUrl=<...>
```

the backend could still return the cached `vidlink` result because the cache key only used `tmdbId`.

That broke worker override behavior.

### Current fix

When `workerUrl` is present:

- cache is bypassed
- Redis is not read
- Redis is not written

This ensures:

- normal `tmdbId` flow still benefits from caching
- worker-assisted flow always uses the caller’s explicit worker URL

### Current cache rule summary

#### No `workerUrl`

- normal provider selection
- normal Redis read/write

#### With `workerUrl`

- `worker` provider is eligible
- cache bypass is forced
- no cached `vidlink` result can override worker path

---

## Current Response Selection Logic

The backend normalizes provider results internally, then `/stream` simplifies the final output.

Selection logic:

1. If `stream.url` exists, use that.
2. Else if `stream.qualities` exists, choose the best numeric quality URL.
3. Else fail with no playable URL.

This means the final `/stream` contract returns only one chosen playable URL.

---

## Tradeoff: Quality Options

### Current state

The backend currently does **not** expose a proper quality-picker payload to the app.

Why:

- `/stream` now returns one final URL only
- if a provider had multiple quality options, the backend chooses one best candidate
- the UI does not receive the full quality map from `/stream`

### Impact

- autoplay is simpler
- `media_kit` integration is easier
- manual quality switching is not fully supported yet

### If quality picker is needed later

Add one of these:

1. enrich `/stream` to return `qualities` and optional `headers`
2. add a separate `/stream/full` endpoint

Current minimal design favors reliability over richness.

---

## media_kit Integration Notes

### Current compatibility

The current backend shape is easy to plug into `media_kit`.

App flow:

1. call `/stream`
2. parse:
   - `url`
   - `provider`
   - `latency`
3. pass `url` into `media_kit`

Conceptually:

```dart
final result = await streamService.getStream(...);
await player.open(Media(result.url));
```

### Important limitation

The simplified backend response no longer exposes explicit `headers`.

That is acceptable for the current tested fallback path because the returned `vidlink` URL already embeds header hints in the query string.

However, if future providers require real player-side request headers, the backend contract may need to be expanded again.

### Recommendation

For flawless long-term playback support, consider later expanding the response to:

```json
{
  "url": "...",
  "provider": "...",
  "latency": 1234,
  "headers": {},
  "qualities": {}
}
```

But that is **not** the current contract.

---

## Files Changed in the Refactor

These files were the main parts of the stream-service refactor on the VM backend:

### Added

- `src/providers/worker.js`

### Reworked

- `src/core/providers.js`
- `src/core/aggregate.js`
- `src/server.js`
- `.env`

### Removed from active path

- `src/providers/fedapi.js`
- `src/providers/finger.js`
- old auth/token-based stream logic
- static turnstile replay logic
- direct backend calls to `backend.xprime.tv`

---

## What `src/providers/worker.js` Does

The worker provider is intentionally minimal.

Responsibilities:

1. validate the incoming worker URL
2. return it in normalized stream shape
3. mark provider as `"worker"`
4. record near-zero backend latency

It does **not**:

- scrape anything
- fetch Finger/XPrime directly
- decrypt worker payloads
- manage tokens

It is just the backend-approved ingestion path for a browser-captured worker URL.

---

## Current `.env` Shape

Current active provider config was set to:

```env
PORT=3002
ENABLED_PROVIDERS=worker,vidlink,vidrock
PROVIDER_TIMEOUT_MS=8000
REDIS_URL=redis://127.0.0.1:6379
```

This is important because:

- `worker` must be enabled for worker override flow
- `vidlink` and `vidrock` remain fallback providers
- `vixsrc` is intentionally not active

---

## Current Debug / Operational Behavior

### Verified working behavior

#### Plain fallback request

```http
GET /stream?tmdbId=550
```

Observed result:

- provider: `vidlink`
- returns playable HLS URL

#### Worker override request

```http
GET /stream?tmdbId=550&workerUrl=<encoded workers.dev url>
```

Observed result after cache bypass fix:

- provider: `worker`
- returns supplied worker URL

### Important operational detail

The worker URL itself is expected to come from the browser/client side, not from the backend.

This is now the intended architecture.

---

## Removed Complexity

The following complexity was intentionally removed to stabilize the system:

- user token store for stream flow
- auth route usage for backend stream resolution
- server-side Febbox token dependency
- static turnstile token storage/replay
- backend Finger/XPrime probing
- mixed stream selection logic that depended on browser-bound protections

The new system is much simpler:

- browser provides worker URL if available
- backend uses it
- otherwise backend falls back to stable providers

---

## Remaining Limitations

The current design is stable, but not feature-complete.

### Limitation 1: no quality picker payload

Only one final URL is returned.

### Limitation 2: no explicit response headers in `/stream`

Future providers may need headers exposed again.

### Limitation 3: worker URL is client-supplied

The backend does not generate or refresh worker URLs itself.

### Limitation 4: Finger/XPrime still not backend-integrated

That is deliberate, not accidental.

---

## Recommended Next Steps

If work resumes later, the safest next priorities are:

### 1. Flutter integration with `media_kit`

Wire app stream service to consume the simplified backend contract.

### 2. Optional contract enrichment

If needed, expand `/stream` response to include:

- `headers`
- `qualities`
- maybe `kind` or `type`

without breaking the current simple path.

### 3. Browser-assisted worker acquisition flow

If the app itself should benefit from worker URLs, define how the browser/client captures and forwards them.

### 4. Keep direct XPrime backend integration disabled

Do not reintroduce direct VM calls to XPrime/Finger unless there is a completely different viable access model.

---

## Current Mental Model

Think of the backend stream system like this:

### Normal mode

```text
App -> /stream?tmdbId=550 -> vidlink/vidrock fallback -> single URL returned
```

### Worker-assisted mode

```text
Browser/client gets working workers.dev URL
        ->
App sends /stream?tmdbId=550&workerUrl=<...>
        ->
Backend validates worker URL
        ->
Backend returns worker URL directly
```

This is the intended production model right now.

---

## Short Summary

The backend stream system was refactored from a fragile token/turnstile-driven backend scraper into a simpler hybrid model:

- direct `FedAPI` and `Finger/XPrime` backend paths were removed from active use
- client-provided `workers.dev` URLs are now accepted as a first-class provider
- `vidlink` remains the main fallback
- `/stream` now returns a simple `{ url, provider, latency }` payload
- cache bypass was added for worker-assisted requests

This is the current stable base.
