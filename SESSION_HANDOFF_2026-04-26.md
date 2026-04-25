# Session handoff — Veil / P-Stream — 2026-04-26

## Workspace
- Local: `C:\Users\Pracheer\Documents\P-Stream` (Flutter package name still `pstream_android` in code)
- GitHub canonical app repo: **https://github.com/dikshadamahe/veil-android** (renamed from `pstream-android`; treat `veil-android` as source of truth for issues/releases)

## Rules the agent must follow (read in repo if not attached)
- `AGENTS.md`: ownership (Dev1 Pracheer vs Dev2 Diksha), no `dart`/`flutter` CLI from Codex in this repo (user runs analyze/build), project-local GitHub MCP + PAT, shallow `code-review-graph` `get_review_context_tool` only (not `get_minimal_context`), don’t push `AGENTS.md` / `PROGRESS.md` / `.codex/` / agent scratch unless user asks
- User identity for pushes: **Pracheer** — `user.name` = `pracheersrivastava`, `user.email` = `pracheer2023@gmail.com`, remote `origin` = `git@github-pracheer:dikshadamahe/veil-android.git` (SSH host `github-pracheer` in `~/.ssh/config`)

## Commits pushed to `main` this session
1. **4fc9139** — `fix(player): parity buffer/readahead, boosted volume, brightness controls (#10 #11 #3)`
   - Removes dim overlays on top of `Video` (fixes “dark playback” / #3)
   - Larger demuxer cache (64 MiB); `lib/utils/player_native_tune.dart` sets mpv `volume-max` + `demuxer-readahead-secs`; explicit `setVolume` after open
   - Brightness: `screen_brightness`, left-edge vertical drag + sheet; volume: right-edge drag + sheet (0–150); toolbar icons; reset brightness on dispose
   - Files: `lib/screens/player_screen.dart`, `lib/widgets/player_controls.dart`, `lib/utils/player_native_tune.dart`, `pubspec.yaml`, `pubspec.lock`
2. **a2b462b** — `feat(ui): history grid, scrape flow UX, episode sheet resilience; docs: README`
   - History grid from `historyProvider`; scraping starts SSE immediately, catalog in parallel, new “Finding stream” UI; safer `MediaItem` runtime parsing; episode sheet empty/error states; README overhaul
   - Files: `README.md`, `lib/screens/history_screen.dart`, `lib/screens/scraping_screen.dart`, `lib/models/media_item.dart`, `lib/widgets/episode_list_sheet.dart`

## GitHub issues
- **Closed** (with comments referencing **4fc9139**): **#10** (playback parity), **#11** (brightness/volume), **#3** (dark playback)
- **Not closed in this session** (still verify on repo): **#2** (TV scraper), **#12** (subtitles), others per issue list

## Intentionally not pushed
- `PROGRESS.md`, `CHAT_CONTEXT_2026-04-25.md`, `issues-fixes.md` (per user request)
- `switch-dev.sh` was edited locally to use `veil-android` URL but may be **gitignored** — confirm in `.gitignore` if team needs that script in the repo

## What to run locally after pulls
- `flutter pub get` / `flutter analyze` / device smoke: player (gestures, brightness reset on exit), scraping, history, episode sheet edge cases