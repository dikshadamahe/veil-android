## Session Context - 2026-04-25

This file is a local agent handoff for the work completed in this chat. It is not intended for push unless explicitly requested.

### Docs and setup reviewed

- Read `AGENTS.md`
- Read `PROGRESS.md`
- Read `issues-fixes.md` (`issues-fixed.md` did not exist; this was the matching file)
- Used `code-review-graph` earlier in the session with shallow review context only

### Repo and workflow notes

- Repo workspace: `C:\Users\Pracheer\Documents\P-Stream`
- Canonical GitHub repo being operated on in practice: `dikshadamahe/veil-android`
- Do not run `dart` or `flutter` commands from Codex in this repo
- There are unrelated dirty files in the worktree; do not mass-stage
- Do not push local agent docs by default: `AGENTS.md`, `PROGRESS.md`, `.codex/`, `.planning/`, and this handoff file should stay local unless explicitly requested

### GitHub issue triage completed

Reviewed and assigned the original issues based on ownership:

- `#1` Diksha
- `#2` Pracheer
- `#3` Pracheer
- `#4` Diksha
- `#5` Pracheer
- `#6` Diksha
- `#7` Diksha
- `#8` Diksha

Added and assigned new issues:

- `#9` cast-related feature issue, assigned to Diksha
- `#10` playback parity: slower streams and possibly quieter audio, assigned to Pracheer
- `#11` player brightness and volume controls, assigned to Pracheer
- `#12` subtitles broken / provider-backed subtitle integration needed, assigned to Pracheer
- `#13` player UI parity redesign for settings/source/quality/subtitle sheets, assigned to Diksha
- `#14` blank white screen on resume/background + stale history, assigned to Pracheer

### Issue grouping decisions made

Recommended bundles discussed:

- `#2 + #5`
- `#6 + #7`

Later lifecycle-focused next bundle recommended:

- `#5 + #6 + #14`
- optionally include `#7`

### Code changes completed

#### 1. Search improvements for issue `#1`

Files changed:

- `lib/services/tmdb_service.dart`
- `lib/screens/search_screen.dart`

Behavior changed:

- TMDB person hits are no longer dropped during search
- person search results expand through `known_for` items
- search debounce reduced from `400ms` to `250ms`
- search hint updated to mention actors/directors support

Commit pushed:

- `1b6ac67` `fix(search): improve people search results`

GitHub follow-up:

- issue `#1` closed with reference to commit

#### 2. Initial navigation/history fix for issues `#6` and `#7`

Files changed:

- `lib/config/router.dart`
- `lib/storage/local_storage.dart`

Behavior changed:

- routing shell switched to `StatefulShellRoute.indexedStack`
- history persistence threshold reduced to `3%`

Commit pushed:

- `36b7234` `fix(nav): preserve home state and history writes`

#### 3. Lifecycle / resume / history / autorotate fix for issues `#5`, `#6`, `#7`, `#14`

Files changed:

- `lib/main.dart`
- `lib/screens/player_screen.dart`

Behavior changed:

- app now observes lifecycle in `main.dart`
- on resume, several Riverpod providers are invalidated:
  - `continueWatchingProvider`
  - `bookmarksProvider`
  - `historyProvider`
  - `trendingMoviesProvider`
  - `trendingTVProvider`
  - `popularMoviesProvider`
- player screen now observes lifecycle
- player persists progress on background/back/source-switch/next-episode flows
- player attempts stream recovery on resume if backgrounded
- player stops forcing landscape-only and allows normal orientation behavior

Commit pushed:

- `e80a22d` `fix(player): recover on resume and refresh app state`

#### 4. Analyzer cleanup after user-ran `flutter analyze`

User ran `flutter analyze` and reported these infos in `lib/screens/player_screen.dart`:

- async `BuildContext` usage after await
- deprecated `WillPopScope`

Fixes applied:

- replaced `WillPopScope` with `PopScope`
- captured `NavigatorState` before async gaps where needed

Commit pushed:

- `de7dab4` `fix(player): address analyzer lifecycle warnings`

### GitHub issues closed

Closed after the lifecycle/player work:

- `#5`
- `#6`
- `#7`
- `#14`

Each was closed with a comment pointing to the relevant commits on `main`.

### User-reported issues captured in chat but not implemented yet

These were discussed and split by ownership:

- Slower streaming than website: Pracheer
- Missing brightness and volume controls: Pracheer
- Subtitles not working: primarily Pracheer, possible Diksha UI follow-up
- Player settings/source/quality/subtitle UI parity with website: Diksha
- App can blank/white-screen after switching away and returning: Pracheer
- History can become stale around lifecycle transitions: Pracheer
- Player still looks poor overall: Diksha
- Audio may be quieter than website: Pracheer
- Source selection screen should match website reference: Diksha

Most of those were turned into GitHub issues `#10` to `#14`.

### Screenshot references used in discussion

Website/player UI references:

- `C:\Users\Pracheer\Pictures\Screenshots\Screenshot 2026-04-25 182545.png`
- `C:\Users\Pracheer\Pictures\Screenshots\Screenshot 2026-04-25 182553.png`
- `C:\Users\Pracheer\Pictures\Screenshots\Screenshot 2026-04-25 182600.png`
- `C:\Users\Pracheer\Pictures\Screenshots\Screenshot 2026-04-25 182608.png`
- `C:\Users\Pracheer\Pictures\Screenshots\Screenshot 2026-04-25 182616.png`

App bug screenshots:

- `C:\Users\Pracheer\Pictures\Screenshot_20260425-181511_Veil.png`
- `C:\Users\Pracheer\Pictures\Screenshot_20260425-053832_Veil.png`

### Security/config note

User pasted subtitle provider keys in chat. They were deliberately not written into public GitHub issues or committed source. Keep such values in runtime config / local env only.

### Release note text drafted in chat

Suggested release title:

- `Veil v0.1.1 - Player recovery and playback stability`

Suggested release description:

- This release focuses on player stability and app recovery behavior. It improves resume/background handling, restores watch history updates more reliably, fixes autorotate behavior, hardens search behavior, and cleans up player lifecycle issues found during analysis. It also includes issue triage and groundwork for the next round of player UI, subtitle, and playback-parity fixes.

### Open follow-up items

- User asked how to run GitHub Actions to add an updated APK to the release
- That answer was not completed in the interrupted turn
- Relevant workflow file to inspect next: `.github/workflows/release.yml`

### Current caution for next agent

- The worktree has unrelated modifications; inspect `git status` carefully before any commit
- Do not assume all blank-screen/history issues are fully resolved just because the issues were closed; user has been iterating through findings quickly
- If continuing with release automation guidance, inspect `.github/workflows/release.yml` and any existing tags/releases first

### Later work completed in the same session

#### 5. Player/settings UI parity bundle for issues `#8` and `#13`

Files changed:

- `lib/main.dart`
- `lib/providers/storage_provider.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/player_screen.dart`
- `lib/widgets/player_controls.dart`

Behavior changed:

- app settings screen was redesigned from a placeholder list into a fuller settings surface
- player now uses a settings-driven sheet flow closer to the website reference
- dedicated player sheets were added for:
  - settings home
  - source picker
  - quality picker
  - subtitle picker
  - subtitle language drill-in
- player controls now surface current source / quality / subtitle state more clearly
- lifecycle refresh in `main.dart` was changed to invalidate `storageRevisionProvider` instead of directly referencing `historyProvider`

Analyzer/CI note:

- user ran `flutter analyze` locally after these changes
- result: `No issues found!`
- this fixed the earlier GitHub Actions failure caused by stale code on `v0.1.4`, but the tag itself still points to the older analyzer-warning commit

Commit pushed:

- `8fae3fc` `feat(player): redesign settings and player sheets`

#### 6. CI workflow added for normal commits

Files changed:

- `.github/workflows/ci.yml`

Behavior changed:

- GitHub Actions now runs `flutter analyze` on:
  - every push to `main`
  - every pull request

Commit pushed:

- `640756c` `ci: run analyze on pushes and PRs`

#### 7. Discovery/search bundle for issues `#4` and `#9`

Files changed:

- `lib/config/router.dart`
- `lib/screens/detail_screen.dart`
- `lib/screens/search_screen.dart`
- `lib/widgets/media_card.dart`

Behavior changed:

- search result cards now use lighter TMDB poster image sizes (`w185`) for faster image loading
- cast avatars on detail use a smaller TMDB profile image size (`w92`)
- detail screen cast cards are now tappable
- tapping a cast member opens search with the actor name prefilled
- routed search now supports an initial query and optional title

Analyzer note:

- user ran `flutter analyze` locally after these changes
- result: `No issues found!`

Commit pushed:

- `78dbf6d` `fix(discovery): speed up search images and cast browsing`

#### 8. Release workflow APK naming change

Files changed:

- `.github/workflows/release.yml`

Behavior changed:

- release workflow now renames and uploads the APK as `veil.apk`
- previous workflow name `apk_release.apk` was removed from the release upload path

Commit pushed:

- `7cd3c30` `ci: rename release APK artifact to veil`

### GitHub workflow/auth lessons from this session

- The failing `APK Release` GitHub Actions run was for tag `v0.1.4`, not current `main`
- Remote tag state checked during the session:
  - `v0.1.4` -> `de7dab4`
  - current `main` at the time of checking -> `8fae3fc`
- `release.yml` checks out `RELEASE_TAG`, so tag/manual release runs build that tag, not latest `main`
- The repo-local GitHub MCP and the Codex GitHub app connector are different auth paths:
  - repo-local PAT path: `mcp__github__`
  - separate integration path: `mcp__codex_apps__github`
- A failed attempt to close issues via `mcp__codex_apps__github._update_issue` returned `403 Resource not accessible by integration`
- A failed attempt to close issues via global `gh` used the globally logged-in `dynamatixQA` account and failed with missing close permissions
- Resulting rule update made locally in `AGENTS.md`:
  - never use global `gh` auth in this repo
  - do not use `mcp__codex_apps__github` when the repo-local PAT/MCP path is intended
- Important mistake during debugging:
  - `.codex/.env` was read raw in-session, exposing secrets in chat context; do not repeat this

### Issue status after this later work

Implemented in code:

- `#4`
- `#8`
- `#9`
- `#13`

Comments drafted/added:

- closure comments were added for `#8` and `#13`
- closure comment text was drafted for `#4` and `#9`

State change caveat:

- `#8` and `#13` were not closed programmatically in-session because the correct repo-local MCP path in this session exposes `get_issue` and `add_issue_comment`, but not an issue-close tool
- user planned to close `#8` and `#13` manually

Remaining open issue groups recommended after Diksha work:

- Pracheer bundle: `#10 + #3 + #11`
- keep `#12` separate for now
- keep `#2` separate unless it proves to share root cause with `#10`

### Release text drafted later in the session

Suggested issue-close comment for `#4`:

- Closed by `78dbf6d` (`fix(discovery): speed up search images and cast browsing`). Search results now use lighter TMDB poster sizes for faster loading, search grid image payloads are smaller than heavier detail/home card assets, and local `flutter analyze` passed after the change.

Suggested issue-close comment for `#9`:

- Closed by `78dbf6d` (`fix(discovery): speed up search images and cast browsing`). Cast entries on the detail screen are now tappable, tapping a cast member opens search with that actor name prefilled, users can browse related titles from cast directly from the detail page, and local `flutter analyze` passed after the change.

Suggested release title:

- `Veil v0.1.5 - Player UI parity and discovery improvements`

Suggested release description:

- This release improves both the player experience and content discovery. Included: redesigned in-player settings flow with dedicated source/quality/subtitle sheets, improved player UI parity with the website, redesigned app settings screen, faster search result image loading through lighter TMDB image sizes, tappable cast members on detail pages opening related-title search, and a new CI workflow to run `flutter analyze` on pushes to `main` and on pull requests.
