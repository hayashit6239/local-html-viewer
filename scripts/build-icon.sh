#!/bin/bash
# Support/icon/AppIcon.svg から各解像度 PNG を `sips` 経由で生成し、`iconutil -c icns` で
# Support/icon/AppIcon.icns を作る(M9)。SVG → PNG はまず Quick Look 経由で 1024×1024 を
# 焼き、以降は sips で派生。`qlmanage`/`sips`/`iconutil` は macOS 標準(依存ゼロ)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Support/icon/AppIcon.svg"
ICONSET="$ROOT/Support/icon/AppIcon.iconset"
ICNS="$ROOT/Support/icon/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1) SVG → 1024 PNG(Quick Look の thumbnail 機能を使う)
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
BASE="$WORK/AppIcon.svg.png"
[ -f "$BASE" ] || { echo "qlmanage で PNG を作れませんでした: $BASE"; exit 1; }

# 2) iconset レイアウト
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { # $1=size(px), $2=filename
    sips -z "$1" "$1" "$BASE" --out "$ICONSET/$2" >/dev/null
}
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$BASE" "$ICONSET/icon_512x512@2x.png"  # 1024

# 3) .icns 生成
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "built: $ICNS"
