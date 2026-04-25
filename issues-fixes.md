# Issues and Fixes

## App launch and packaging
- Added `media_kit_video` and `media_kit_libs_video` to support Android video playback dependencies.
- Kept the existing `media_kit` stack instead of swapping player libraries.

## Branding and release setup
- Rebranded the app/repo to `Veil`.
- Updated release workflow naming and APK asset naming for GitHub releases.
- Added `logo.png` usage for app/repo branding and launcher icon generation.

## TMDB configuration and data flow
- Normalized `ORACLE_URL` handling so a host-only value resolves correctly to the providers API port.
- Switched TMDB auth handling back to read-token flow only.
- Increased TMDB request timeout and added a retry on timeout.
- Improved TMDB error reporting for auth and timeout failures.
- Hardened TV runtime parsing so empty `episode_run_time` lists do not crash detail parsing.

## Home, search, and history screens
- Added explicit loading, error, and empty states to Home and Search instead of blank/grey surfaces.
- Replaced the History placeholder with a real history screen backed by stored watch history.

## Series/detail flow
- Added protection for shows with missing season data.
- Added safe empty/error states in the episode picker sheet.
- Added a detail-screen error state instead of falling into a blank/white screen on TMDB detail failures.

## Scraping/source selection flow
- Started scraping immediately instead of waiting on the catalog fetch first.
- Reworked the scrape screen from a long provider list to a centered active-source flow with lighter animation.
- Kept recent attempts visible as a small summary instead of rendering the entire source tree.
- Retained manual source selection.

## Player fixes
- Mounted a real `Video` widget so playback is not audio-only.
- Added stream URL fallback resolution across proxied playlist, playlist, playback URL, and quality URLs.
- Added in-player source switching with a source picker and auto-selection fallback.
- Updated subtitle handling so the subtitle button tries available caption tracks first, then embedded subtitle tracks.
- Added source-switch loading state in the player.

## Build/debug fixes during this chat
- Added missing `dart:async` import for `TimeoutException`.
- Restored the `ScrapeStatus` import path after refactoring the scrape screen.
- Restored the `ScrapeSourceDefinition` import for the player source picker.
