# providers-api (“pstream-backend” in deploy docs)

Express service on **port 3001** that wraps **`@p-stream/providers`** (`targets.NATIVE`). The Flutter app points **`ORACLE_URL`** here (not at `simple-proxy` :3000).

## What is *not* in this repo

There is no separate **`@pstream-backend`** package in the Android repo: Oracle runs **this folder** (or a copy of it) under PM2 as `providers-api`.

## Adding scrapers (VidSrc.me, 2Embed.cc, AutoEmbed, CinePro, …)

Step-by-step for **domains + APIs you listed** (`vidsrc-embed.ru`, 2embed.cc, AutoEmbed leave-as-is, CinePro Core): see **[docs/CUSTOM_EMBED_INTEGRATION.md](docs/CUSTOM_EMBED_INTEGRATION.md)**.

Short version:

1. **Sourcerer ids** must exist in **`xp-technologies-dev/providers`** (or a fork) as `makeSourcerer({ id: '…' })`. The app sends them as the `sourceOrder` query string (comma-separated).
2. **Your Oracle `/sources` JSON is the source of truth** for which ids exist today (e.g. `vidlink`, `fedapi`, …; embeds like `autoembed-english` are separate from top-level **source** ids).
3. **CinePro** is an **OMSS** backend ([docs](https://cinepro.mintlify.app/)) — integrate via a **new sourcerer**, a **bridge** in this repo, or a sidecar; it is not a drop-in string in `@p-stream/providers` until someone implements it.

To ship new sourcerers, the work is usually in **`xp-technologies-dev/providers`** (TypeScript + tests), then:

```bash
cd backend/providers-api
pnpm install   # or npm install
# bump @p-stream/providers to your branch/commit if forked
```

Redeploy on Oracle and restart PM2.

## What we need from you (Oracle / ops)

Send (redact secrets):

1. **Output of** `curl -sS "http://<VM_IP>:3001/sources" | head -c 4000` — confirms which sourcerer **ids** your VM actually exposes.
2. **`package.json` / lockfile** line for `@p-stream/providers` (GitHub ref or npm version) running on the VM.
3. **PM2** process name and **`pm2 logs`** snippet from a slow scrape (if any).
4. Whether you can point **`@p-stream/providers`** at a **fork** (branch URL) where we enable `disabled: false` for chosen sourcerers after testing.

## Environment

| Variable | Purpose |
|----------|---------|
| `PORT` | Listen port (default `3001`) |
| `REQUEST_TIMEOUT_MS` | Cap for `runAll` (default `90000`) |
| `SIMPLE_PROXY_URL` | Optional; forwarded in `/health` for operators |

## Health check

```bash
curl -sS "http://<VM_IP>:3001/health"
```
