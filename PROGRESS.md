# Progress

## Current Status
MVP is complete and released as `v0.1.0-mvp`. Flutter Android scaffold, Oracle VM backend stack, routed app bootstrap, Riverpod provider wiring, scraping/player flow, MVP code-review checklist pass, GitHub Actions APK build, and GitHub Release publishing are complete. The release APK is attached to the GitHub Release. Canonical GitHub repository: `dikshadamahe/veil-android` (replaces the earlier `pstream-android` repo name). `code-review-graph` is built, but `get_minimal_context_tool` is broken in this project environment, so shallow `get_review_context_tool` is the required fallback.

## MVP Checklist

### Dev 1 (Pracheer) - Infra + Player
- [x] Oracle VM: Node 20, pnpm, PM2 installed
- [x] 1GB swap added
- [x] simple-proxy deployed and running :3000
- [x] providers-api deployed and running :3001
- [x] Test: /scrape returns stream URL for Fight Club (tmdbId=550)
- [x] OCI Console + iptables ports open
- [x] stream_service.dart (SSE + fallback)
- [x] player_screen.dart (media_kit + headers + progress save)
- [x] player_controls.dart (seek bar + overlay)
- [x] scraping_screen.dart (SSE -> animated cards)
- [x] adaptive_nav.dart
- [x] GitHub Actions APK build workflow

### Dev 2 (Diksha) - UI + Data
- [x] flutter create + pubspec.yaml
- [x] main.dart (MediaKit.init + Hive + ProviderScope)
- [x] app_theme.dart (all AppColors from themes/default.ts)
- [x] breakpoints.dart
- [x] MediaItem model
- [x] tmdb_service.dart
- [x] local_storage.dart
- [x] router.dart
- [x] home_screen.dart
- [x] media_card.dart
- [x] search_screen.dart
- [x] detail_screen.dart

### Integration
- [x] Full MVP code review checklist pass
- [x] End-to-end: Search -> Detail -> Play -> Video plays
- [x] Resume works
- [x] Bookmark works
- [x] Tested on physical Android device
- [x] APK builds successfully
- [x] GitHub Release v0.1.0-mvp published

## V1 Checklist
[leave blank - add when MVP ships]

## V2 Checklist
[leave blank - add when V1 ships]

## Session Log
| Date | Dev | What was done |
|------|-----|---------------|
| 2026-04-21 | Diksha/Pracheer | Created `AGENTS.md` and `PROGRESS.md` to establish project brain, ownership, workflow, and MVP tracking. |
| 2026-04-21 | Diksha/Pracheer | Added `switch-dev.sh`, `.gitignore`, and `.gitattributes` for git identity switching and repo hygiene. |
| 2026-04-21 | Diksha/Pracheer | Created GitHub repo `dikshadamahe/veil-android` (initially published as `pstream-android`) and prepared local docs for initial sync. |
| 2026-04-21 | Diksha/Pracheer | Initialized git, committed the bootstrap files, and pushed `main` to GitHub with repo description and topics configured. |
| 2026-04-21 | Diksha | Ran `flutter create`, added the agreed dependencies in `pubspec.yaml`, created the planned `lib/` directories, enabled Android internet plus MVP cleartext traffic, set Android min SDK 23, and confirmed `flutter pub get` succeeds. |
| 2026-04-22 | Pracheer | Verified Oracle VM baseline: Ubuntu 22.04, Node 20, pnpm, PM2, 1 GB swap, and public `simple-proxy` on `:3000` are working. |
| 2026-04-22 | Pracheer | Added local `backend/providers-api` scaffolding with `health`, blocking `/scrape`, and basic SSE `/scrape/stream` endpoints for the next VM deploy step. |
| 2026-04-22 | Pracheer | Fixed public repo hygiene, pushed the Flutter scaffold plus `backend/providers-api`, and corrected the providers Git source to `xp-technologies-dev/providers`. |
| 2026-04-22 | Pracheer | Added pnpm build allowlisting for `@p-stream/providers`, deployed `providers-api` on Oracle VM `:3001`, and verified public `/health` plus `/scrape` with Fight Club (`tmdbId=550`). |
| 2026-04-22 | Pracheer | Added first-pass Flutter scraping flow files: `stream_service.dart`, `scraping_screen.dart`, `scrape_source_card.dart`, plus minimal support models/config and a temporary `player_screen.dart` placeholder to unblock route navigation. |
| 2026-04-22 | Diksha/Pracheer | Moved GitHub MCP auth to a project-local wrapper reading `.codex/.env`, so other Codex projects will not inherit Diksha's PAT. |
| 2026-04-22 | Diksha/Pracheer | Clarified repo workflow in `AGENTS.md`: Codex must not run `dart` or `flutter` CLI commands here and must hand exact commands to the user when CLI execution is needed. |
| 2026-04-22 | Diksha | Added `breakpoints.dart` and `adaptive_nav.dart`, then verified both files with `flutter analyze` and no issues. |
| 2026-04-22 | Diksha/Pracheer | Initialized `code-review-graph`, confirmed the graph builds, and documented that `get_minimal_context_tool` is unusable here; use shallow `get_review_context_tool` instead. |
| 2026-04-22 | Diksha | Added `app_config.dart`, TMDB-backed media models (`media_item.dart`, `season.dart`, `episode.dart`), `stream_result.dart`/`scrape_event.dart` data shapes, and `tmdb_service.dart`, then verified the touched Dart files with Dart MCP format + analyze. |
| 2026-04-22 | Diksha | Added `local_storage.dart` with Hive-backed bookmarks, progress, continue-watching, and watch-history maps, plus minimal `main.dart` initialization and watched-ratio config support. |
| 2026-04-22 | Diksha | Added `search_screen.dart` with debounced TMDB search and trending suggestions, upgraded `detail_screen.dart` to fetch rich metadata with hero/backdrop/resume/bookmark flows, and expanded `MediaItem` storage support for genres and cast. |
| 2026-04-22 | Pracheer | Hardened Dev 1 scraping flow: SSE `stream_service.dart` timeout/fallback behavior, `scraping_screen.dart` source state + manual retry handling, and animated `scrape_source_card.dart` status UI with `RepaintBoundary` around each animated status circle. |
| 2026-04-22 | Pracheer | Added Dev 1 player bootstrap: `player_screen.dart` now opens streams with headers through `media_kit`, applies immersive landscape playback chrome, restores progress to Hive, and routes to re-scrape or next-episode flows; `player_controls.dart` adds the glass overlay, custom seek bar, subtitle toggle, source sheet entry, and next-episode CTA. |
| 2026-04-22 | Diksha/Pracheer | Wired app bootstrap and routing: replaced scaffold `main.dart` with Hive + `MediaKit` startup, added `go_router` config in `router.dart`, created Riverpod provider files, routed detail/scrape/player flows with typed extras and resume handoff, and added minimal `settings_screen.dart` plus `history_screen.dart` stub. |
| 2026-04-22 | Pracheer | Completed full MVP code-review checklist pass on changed files: moved UI service/storage access behind Riverpod providers, verified direct-import context with `code-review-graph`, fixed repaint/touch/SafeArea/network-image checks, and confirmed `flutter analyze` has no issues. |
| 2026-04-22 | Diksha | Added missing GitHub Actions APK release workflow, published tag `v0.1.0-mvp`, confirmed Actions run `24795274441` succeeded, and verified GitHub Release `v0.1.0-mvp` has `app-release.apk` attached. |
