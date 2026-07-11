# Bundled uBlock Origin

Veil bundles the official Firefox uBlock Origin **1.72.2** extension, downloaded
from Mozilla Add-ons:

`https://addons.mozilla.org/firefox/downloads/file/4888680/ublock_origin-1.72.2.xpi`

The unpacked extension lives in `addons/ublock_origin/`. Its upstream
`LICENSE.txt` and third-party license files are retained unchanged.

## Updating

1. Check the stable version at
   `https://addons.mozilla.org/firefox/addon/ublock-origin/versions/`.
2. Download the official `.xpi`, verify its version/source, and unpack it over
   `addons/ublock_origin/`.
3. Confirm `manifest.json` still declares
   `uBlock0@raymondhill.net` and retains all license files.
4. Update this file, then test install logs, filter loading, sports playback,
   overlay blocking, and popup/main-frame navigation blocking on a real device.
