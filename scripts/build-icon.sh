#!/bin/bash
# Support/icon/AppIcon.svg から各解像度 PNG を `sips` 経由で生成し、`iconutil -c icns` で
# Support/icon/AppIcon.icns を作る(M9)。SVG → PNG はまず Quick Look 経由で 1024×1024 を
# 焼き、以降は sips で派生。`qlmanage`/`sips`/`iconutil` は macOS 標準(依存ゼロ)。
#
# ⚠️ AppIcon.svg を編集したら必ず本スクリプト(または `make icon`)を実行して .icns を
#    再生成すること。.icns は checked-in binary のため、再生成を忘れると SVG ソースと
#    .icns バイナリがドリフトする(M9 review #6)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Support/icon/AppIcon.svg"
ICNS="$ROOT/Support/icon/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# iconset は WORK 配下に作る(リポジトリ内に残骸 `Support/icon/AppIcon.iconset/` を残さない — M9 review #5)。
ICONSET="$WORK/AppIcon.iconset"

# 1) SVG → 1024 PNG(Quick Look の thumbnail 機能を使う)。
# stdout のみ捨て stderr は残す: SVG renderer 不在 / QuickLook 生成エラーの原因を握りつぶさない(M9 review #4)。
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null
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
# 1024: qlmanage 出力は SVG renderer 不在時に非 1024 を返しうるため、raw コピーせず
# sips でサイズを保証する(iconutil の dimensions reject を防ぐ — M9 review #5)。
gen 1024 icon_512x512@2x.png

# 3) .icns 生成。先に既存 .icns を消してから生成する。iconutil が失敗(dimensions reject /
# ディスク満杯等)したら set -e で停止し $ICNS は**消えたまま**になる → 次回 make install の
# fail-loud(build.sh)で「再生成したのに古い .icns が残る」サイレント不整合を検知できる(M9 review #2)。
rm -f "$ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "built: $ICNS"
