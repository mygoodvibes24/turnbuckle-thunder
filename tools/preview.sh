#!/usr/bin/env bash
# Screenshot a web build of the game with headless Chromium (Playwright).
#   tools/preview.sh <web-build-dir-or-url> <out-dir> [seconds]
# A directory is served on localhost:8060 first. Writes PNGs + console.log to out-dir.
set -euo pipefail
src="$1"; out="$2"; secs="${3:-20}"
mkdir -p "$out"
here="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$src" ]]; then
  (cd "$src" && python3 -m http.server 8060 >/dev/null 2>&1) &
  srv=$!; trap 'kill $srv 2>/dev/null || true' EXIT
  sleep 1
  url="http://localhost:8060/index.html"
else
  url="$src"
fi
node "$here/shoot.js" "$url" "$out" "$secs"
ls "$out"
