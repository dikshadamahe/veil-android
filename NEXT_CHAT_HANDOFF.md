# Next chat — Veil (`veil-android`) handoff

Use this file as **context** for the following session. Attach it or `@`-reference `NEXT_CHAT_HANDOFF.md` when you start the next chat.

---

## Repository & product


| Item                                 | Value                                                                                                                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Workspace                            | `C:\Users\Pracheer\Documents\P-Stream` (Flutter package name `pstream_android`)                                                                                     |
| GitHub app repo                      | **[https://github.com/dikshadamahe/veil-android](https://github.com/dikshadamahe/veil-android)**                                                                    |
| Product name                         | **Veil**                                                                                                                                                            |
| Recent `main` commits (newest first) | `e28e262` analyzer cleanups · `091e393` TV scrape `ShowMedia` + Wyzie/OpenSubtitles + release secrets · `a2b462b` history/scrape UX · `4fc9139` player (#10 #11 #3) |


---

## GitHub issues (verify when you start)

- **Open issues:** At last check the API returned **no open issues** — confirm on [Issues](https://github.com/dikshadamahe/veil-android/issues). New bugs should be filed or pasted below.
- **Recently closed (context only):** #2 (TV scraper / nested `ShowMedia`), #12 (external subtitles), #3 / #10 / #11 (player).

### Paste new work here (fill in before next chat)



1. **Issue / symptom:**
2. **Repro steps:**
3. **Expected vs actual:**
4. **Logs / CI:** (attach or paste)

---

## What was implemented (so the next agent does not redo it)

### TV scraping (#2)

- **Root cause:** `@p-stream/providers` expects `ShowMedia` with **nested** `season` / `episode` objects; `providers-api` previously sent flat strings.
- **Fix:** `backend/providers-api/src/server.js` — `buildMediaFromQuery` builds nested `media` for show + `season` + `episode` query params; optional `imdbId`, `seasonTmdbId`, `episodeTmdbId`, `seasonTitle`.
- **Flutter:** `MediaItem.toScrapeQueryParameters`, `StreamService`, `ScrapingScreenArgs` / `PlayerScreenArgs`, `EpisodeSelection`, `detail_screen`, `router`, `episode_list_sheet`.
- **Deploy:** Oracle VM must run an updated `**providers-api`** build for TV fixes to apply in production.

### External subtitles (#12)

- **Keys:** Only via `--dart-define` or GitHub Actions **secrets** (never in source). See `README.md` table.
- **Defines:** `WYZIE_API_KEY`, `OPENSUBTITLES_API_KEY`, optional `OPENSUBTITLES_USERNAME` / `OPENSUBTITLES_PASSWORD`, optional `SUBTITLE_HTTP_USER_AGENT`.
- **Code:** `lib/config/app_config.dart`, `lib/services/external_subtitle_service.dart`, `lib/models/external_subtitle_offer.dart`, player **Subtitles → Search online…** in `lib/screens/player_screen.dart`.
- **CI:** `.github/workflows/release.yml` forwards optional subtitle secrets when set.
- **Caveats:** OpenSubtitles `**/download`** often needs **username + password** defines, not API key alone. TV **online** subtitles need **season + episode** on `PlayerScreenArgs`.

### Analyzer / CI

- `e28e262` — `use_null_aware_elements` on scrape `imdbId` map entry, remove unnecessary casts in `external_subtitle_service.dart`, `ListView.separated` separator signature in `player_screen.dart`.

---

## Rules the next agent must follow

Read `**AGENTS.md`** in the repo. Short list:

- **No `flutter` / `dart` CLI** from the agent in this repo — the human runs `flutter analyze`, `flutter build`, etc., and pastes output if something fails.
- **GitHub:** Prefer **project-local** GitHub MCP + PAT from `.codex/.env` (see `AGENTS.md`). MCP actions may appear under the PAT owner’s GitHub user, not necessarily the contributor who wrote the code.
- **Ownership:** Pracheer — Oracle VM, proxy, scraping, player, playback infra. Diksha — UI, screens, theme, TMDB layout. Avoid mixing scopes without reason.
- **Docs / pushes:** Do not commit `AGENTS.md`, `PROGRESS.md`, `.codex/`, or scratch handoffs unless the user explicitly wants them on GitHub.
- **code-review-graph:** Shallow `get_review_context` only; do not use `get_minimal_context` (broken here).

---

## Files most likely touched for “more issues”


| Area                     | Paths                                                                                                                                   |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Player / subtitles       | `lib/screens/player_screen.dart`, `lib/services/external_subtitle_service.dart`, `lib/config/app_config.dart`                           |
| Scrape / Oracle          | `lib/services/stream_service.dart`, `lib/screens/scraping_screen.dart`, `backend/providers-api/src/server.js`                           |
| TMDB / detail / episodes | `lib/services/tmdb_service.dart`, `lib/screens/detail_screen.dart`, `lib/widgets/episode_list_sheet.dart`, `lib/models/media_item.dart` |
| CI / release             | `.github/workflows/release.yml`, `.github/workflows/ci.yml`                                                                             |
| Design parity (web)      | Reference `xp-technologies-dev/p-stream` `.tsx` sources per `AGENTS.md`                                                                 |


---

## Prompt to paste into the **next** chat

Copy everything inside the fence below.

```text
Workspace: C:\Users\Pracheer\Documents\P-Stream — Flutter app “Veil”, GitHub dikshadamahe/veil-android.

I attached NEXT_CHAT_HANDOFF.md — use it as authoritative context (recent commits, TV scrape + subtitles work, AGENTS.md rules).

Current goal: [DESCRIBE YOUR NEW ISSUES HERE — paste GitHub issue #s, CI failure logs, or repro steps]

Constraints:
- Follow AGENTS.md (I run flutter/dart CLI; you do not run them in this repo).
- Use project-local GitHub MCP for GitHub if needed.
- Pracheer owns infra/player/scraping; avoid Dev2 UI scope unless the issue requires it.

Start by: [e.g. confirm open GitHub issues vs handoff / reproduce from pasted logs / read failing CI step] then implement the smallest fix.
```

Replace the bracketed lines with your real goal and how you want the agent to start.

---

## Quick commands (human runs)

```bash
cd C:\Users\Pracheer\Documents\P-Stream
flutter analyze
flutter build apk --release ^
  --dart-define=ORACLE_URL=http://YOUR_VM_IP:3001 ^
  --dart-define=TMDB_TOKEN=YOUR_TMDB_TOKEN ^
  --dart-define=WYZIE_API_KEY=... ^
  --dart-define=OPENSUBTITLES_API_KEY=...
```

Oracle health check (from docs): `curl http://$ORACLE_VM_IP:3001/health`

---

*End of handoff — update the “Paste new work here” section before your next session so the agent has concrete targets.*