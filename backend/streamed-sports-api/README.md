# veil-streamed-sports

Isolated Express proxy for the [Streamed.pk](https://streamed.pk/docs) sports API.

Runs on **port 3003** by default. Does **not** share process, port, or routes with cinepro (`:3001`), simple-proxy (`:3000`), or nuvio (`:7000`).

## Endpoints

| Local | Upstream |
| --- | --- |
| `GET /health` | — |
| `GET /v1/sports` | `/api/sports` |
| `GET /v1/matches/live` | `/api/matches/live` |
| `GET /v1/matches/all-today` | `/api/matches/all-today` |
| `GET /v1/matches/:sport` | `/api/matches/:sport` |
| `GET /v1/stream/:source/:id` | `/api/stream/:source/:id` |
| `GET /v1/images/*` | `/api/images/*` |

Responses from match/stream endpoints are the upstream JSON arrays unchanged. Stream objects include `embedUrl` (iframe) — not HLS.

## Cache TTLs (env)

| Key | Default |
| --- | --- |
| `CACHE_SPORTS_TTL_MS` | 1h |
| `CACHE_MATCHES_TTL_MS` | 2m |
| `CACHE_LIVE_TTL_MS` | 45s |
| `CACHE_STREAM_TTL_MS` | 20s |

## Run

```bash
cp .env.example .env
npm install
npm start
```

PM2 (VPS):

```bash
pm2 start src/server.js --name streamed-sports --cwd /home/ubuntu/apps/veil-streamed-sports
pm2 save
```
