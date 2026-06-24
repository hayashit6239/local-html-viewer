#!/bin/bash
# HTMLViewer — .app バンドル組み立て・ad-hoc 署名・インストール・Launch Services 登録
#
# 手順の順序に意味がある(docs/03-implementation.md §3):
#   1. swift build -c release
#   2. .app 組み立て(Info.plist は plutil -lint で検証)
#   3. codesign は組み立ての最終ステップ(署名後に plist を触ると arm64 では起動時 SIGKILL)
#   4. 旧インスタンスを quit してから ~/Applications へ配置
#      (起動中のままだとオープンイベントが旧プロセスに配送される)
#   5. lsregister はインストール先のみに実行(dist/ を登録すると古いコピーが掴まれる)
set -euo pipefail

APP_NAME="HTMLViewer"
BUNDLE_ID="com.hayashi.htmlviewer"
DIST_DIR="dist"
APP="$DIST_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release
# 生成物パスは --show-bin-path で取得する。.build/release は実体
# (.build/<triple>/release)へのシンボリックリンクで、SwiftPM の内部構造変更や
# マルチアーキ時にハードコード(.build/release 直書き)だと壊れうるため。
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

# .icns コピー。アイコン名は Info.plist の CFBundleIconFile から導出し、plist を single source
# として契約一致を機械的に保証する(build.sh に名前を二重定義しない)。Info.plist が icon を
# 参照する以上、.icns 欠落は Dock/Finder で generic アイコンに化けるだけで CI/build に検知
# シグナルが出ないため、fail-loud にする。再生成は `make icon`(scripts/build-icon.sh)。
ICON_NAME="$(plutil -extract CFBundleIconFile raw Support/Info.plist 2>/dev/null || true)"
if [ -n "$ICON_NAME" ]; then
	ICON_SRC="Support/icon/$ICON_NAME.icns"
	if [ -f "$ICON_SRC" ]; then
		cp "$ICON_SRC" "$APP/Contents/Resources/$ICON_NAME.icns"
	else
		echo "ERROR: $ICON_SRC が見つかりません(Info.plist の CFBundleIconFile=$ICON_NAME と不一致)。'make icon' で生成してください" >&2
		exit 1
	fi
fi

echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP"

if pgrep -x "$APP_NAME" >/dev/null; then
	echo "==> quit running instance"
	osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
	sleep 1
	pgrep -x "$APP_NAME" >/dev/null && pkill -x "$APP_NAME" && sleep 1 || true
fi

echo "==> install to $INSTALLED_APP"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto "$APP" "$INSTALLED_APP"

echo "==> register with Launch Services"
if [ -x "$LSREGISTER" ]; then
	"$LSREGISTER" -f "$INSTALLED_APP"
else
	echo "warn: lsregister が見つからないため、フルパス起動で代替登録します" >&2
	open -g "$INSTALLED_APP" || true
fi

echo "==> done: $INSTALLED_APP"
