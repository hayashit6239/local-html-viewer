#!/bin/bash
# Support/icon/AppIcon.svg から各解像度 PNG を `sips` 経由で生成し、`iconutil -c icns` で
# Support/icon/AppIcon.icns を作る(M9)。SVG → PNG はまず Quick Look 経由で 1024×1024 を
# 焼き、以降は sips で派生。`qlmanage`/`sips`/`iconutil` は macOS 標準(依存ゼロ)。
#
# ⚠️ AppIcon.svg を編集したら必ず本スクリプト(または `make icon`)を実行して .icns を
#    再生成すること。.icns は checked-in binary のため、再生成を忘れると SVG ソースと
#    .icns バイナリがドリフトする。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Support/icon/AppIcon.svg"
ICNS="$ROOT/Support/icon/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# iconset は WORK 配下に作る(リポジトリ内に残骸 `Support/icon/AppIcon.iconset/` を残さない)。
ICONSET="$WORK/AppIcon.iconset"

# 1) SVG → 1024 PNG(Quick Look の thumbnail 機能を使う)。
# stdout のみ捨て stderr は残す: SVG renderer 不在 / QuickLook 生成エラーの原因を握りつぶさない。
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null
BASE="$WORK/AppIcon.svg.png"
[ -f "$BASE" ] || { echo "qlmanage で PNG を作れませんでした: $BASE"; exit 1; }
# BASE が 1024px であることを検証する。qlmanage は SVG renderer 不在 / 古い macOS で非 1024 を
# 返すことがあり、その場合 sips が silent upscale して blurry な @2x のまま .icns 化される。
# fail-loud にして品質劣化を防ぐ。
# width だけでなく height も検証する。qlmanage -s は max-dim で aspect 保持のため、非正方
# viewBox の SVG だと width=1024 / height≠1024 の PNG が guard を通り、後段 sips -z で
# letterbox(透明帯)入りアイコンになる。正方を要求する。
base_w="$(sips -g pixelWidth "$BASE" 2>/dev/null | awk '/pixelWidth/{print $2}')"
base_h="$(sips -g pixelHeight "$BASE" 2>/dev/null | awk '/pixelHeight/{print $2}')"
{ [ "$base_w" = "1024" ] && [ "$base_h" = "1024" ]; } || { echo "qlmanage 出力が 1024×1024 ではありません(got: ${base_w:-?}×${base_h:-?})。SVG の viewBox(正方)/ renderer を確認してください"; exit 1; }

# 2) iconset レイアウト。`@2x` は次サイズの `1x` とピクセル同一(例 16x16@2x = 32 = 32x32)。
# その invariant を sips の二重生成ではなく cp で構造化する(片方だけ差し替える誘惑を断つ)。
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { # $1=size(px), $2=filename
    sips -z "$1" "$1" "$BASE" --out "$ICONSET/$2" >/dev/null
}
gen 16   icon_16x16.png
gen 32   icon_32x32.png
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"    # 32 ≡ 32
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_256x256.png
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"  # 256 ≡ 256
gen 512  icon_512x512.png
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"  # 512 ≡ 512
cp "$BASE"                     "$ICONSET/icon_512x512@2x.png"  # 1024(BASE は 1024 を検証済み)

# 3) .icns 生成。先に既存 .icns を消してから生成する。iconutil が失敗(dimensions reject /
# ディスク満杯等)したら set -e で停止し $ICNS は**消えたまま**になる → 次回 make install の
# fail-loud(build.sh)で「再生成したのに古い .icns が残る」サイレント不整合を検知できる。
rm -f "$ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "built: $ICNS"
# visual asset を変えたら Launch Services の icon cache(bundle id + version でキャッシュ)を
# 無効化するため CFBundleVersion を +1 する運用(自動 bump は no-op 再生成でも version を
# 膨らませるため、リマインダに留める。docs/03 §M9 / docs/04 §5 M9 #3)。
echo "NOTE: アイコンを変更した場合は Info.plist の CFBundleVersion を +1 してください(LS icon cache 無効化)"
