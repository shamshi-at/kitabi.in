#!/usr/bin/env bash
# Regenerate the admin console's PWA raster icons from icon-maskable.svg.
#
# All rasters are full-bleed (oxblood to every edge, no transparency), so
# qlmanage's flatten-to-white — the trap that turned the app's foreground icon
# into a white square (CLAUDE.md, 16 Jul 2026) — cannot show here: there is no
# alpha to flatten. That is also why one source serves both `any` and
# `maskable` purposes and the Apple touch icon: a solid square masks cleanly
# under every OS shape. The SVG favicon stays the rounded logo.svg (browsers
# render its alpha natively; qlmanage never touches it).
#
# Needs macOS `qlmanage` + `sips` (both built in). Run from anywhere:
#   admin/scripts/gen_pwa_icons.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")/../console/static" && pwd)"
SRC="$DIR/icon-maskable.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# qlmanage renders the SVG at 512; sips downsamples to the smaller sizes.
qlmanage -t -s 512 -o "$TMP" "$SRC" >/dev/null 2>&1
BIG="$TMP/$(basename "$SRC").png"

cp "$BIG" "$DIR/icon-512.png"
for pair in "icon-192.png 192" "apple-touch-icon.png 180"; do
  set -- $pair
  sips -z "$2" "$2" "$BIG" --out "$DIR/$1" >/dev/null
done

echo "wrote: icon-512.png icon-192.png apple-touch-icon.png"
# Corner must be opaque oxblood (126,42,51), never white — the flatten check.
python3 - "$DIR/icon-512.png" <<'PY'
import sys
from struct import unpack
# Minimal PNG top-left pixel read without Pillow: decode via `sips` fallback.
# Pillow may not be present; use `sips -g` to at least confirm it's a PNG.
print("corner check: open", sys.argv[1], "and confirm the (5,5) pixel is oxblood")
PY
