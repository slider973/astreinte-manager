#!/usr/bin/env bash
# Rend l'image de partage (Open Graph) depuis site/sources/partage.html avec le Chrome du poste,
# puis la réduit en PNG optimisé (≤ 120 Ko, vérifié par site/scripts/verifier.py).
set -euo pipefail
ici="$(cd "$(dirname "$0")/.." && pwd)"
chrome="${CHROME_EXECUTABLE:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
port="${PORT:-8765}"
tmp="$(mktemp -d)"
# Servi en HTTP : en file://, Chrome refuse les fontes et la page retombe sur une fonte serif.
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$ici" >/dev/null 2>&1 &
serveur=$!
trap 'kill "$serveur" 2>/dev/null; rm -rf "$tmp"' EXIT
sleep 1
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1200,630 --virtual-time-budget=5000 \
  --screenshot="$tmp/partage.png" "http://127.0.0.1:$port/sources/partage.html" >/dev/null 2>&1
magick "$tmp/partage.png" -crop 1200x630+0+0 +repage -strip -colors 128 -define png:compression-level=9 \
  "$ici/public/images/partage.png"
magick identify -format '%wx%h %b\n' "$ici/public/images/partage.png"
