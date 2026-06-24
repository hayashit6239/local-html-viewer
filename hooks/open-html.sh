#!/bin/bash
# Claude Code PostToolUse hook: .html 生成 → HTMLViewer に自動表示(M8)。
#
# 仕様(docs/02 §4 / docs/05 D7):
#   - stdin から JSON ペイロードを受け、`.tool_input.file_path` を取り出す
#   - .html / .htm 以外は no-op
#   - 同一パスが前回起動から 5 秒以内なら no-op(連打抑止)
#   - `open -g -b <bundle id>`(-b: 名前衝突に強い・-g: フォーカスを奪わない)
#   - 常に exit 0(PostToolUse はブロック不能・stderr もトランスクリプトを汚すため握りつぶす)
#
# テスト容易化: 環境変数 `OPEN_CMD` で `open` を差し替え可能(scripts/test-hooks.sh で利用)。
# `set -euo pipefail` は使わない — 早期 exit で握りつぶす方針のため。
#
# デバッグ: `HTMLVIEWER_HOOK_DEBUG=1` のときのみ、open 失敗 / state 書込失敗を
# `$STATE_DIR/last-error` に 1 行残す(M8 review #5/#10)。既定は無効でトランスクリプトを汚さない。

BUNDLE_ID="${HTMLVIEWER_BUNDLE_ID:-com.hayashi.htmlviewer}"
THROTTLE_SECONDS="${HTMLVIEWER_HOOK_THROTTLE:-5}"
# THROTTLE_SECONDS が非数値(誤設定 `off` 等)だと `[ ... -lt "$THROTTLE_SECONDS" ]` が
# stderr に integer エラーを出すため、読み取り時点で既定 5 に正規化する(state 側の数値ガードと対称 — M8 review #2)。
case "$THROTTLE_SECONDS" in
    '' | *[!0-9]*) THROTTLE_SECONDS=5 ;;
esac
STATE_DIR="${HTMLVIEWER_HOOK_STATE_DIR:-$HOME/.cache/htmlviewer}"
STATE_FILE="$STATE_DIR/last-open"
OPEN_CMD="${OPEN_CMD:-open}"

# DEBUG 口(opt-in): 有効時のみ last-error に 1 行追記。常に true で返し exit 0 方針を壊さない。
dbg() {
    [ -n "${HTMLVIEWER_HOOK_DEBUG:-}" ] || return 0
    printf '%s\n' "$*" >> "$STATE_DIR/last-error" 2>/dev/null || true
}

# stdin から JSON を読む(空でも握りつぶす)。コマンド置換は exit code を伝播しないため
# `|| true` は不要(M8 review #3)。
payload="$(cat 2>/dev/null)"
[ -z "$payload" ] && exit 0

# .tool_input.file_path を抽出(jq 優先、無ければ python3)
if command -v jq >/dev/null 2>&1; then
    file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
    file_path="$(printf '%s' "$payload" | python3 -c \
        'import json,sys
try:
    d=json.load(sys.stdin)
    p=(d.get("tool_input") or {}).get("file_path") or ""
    print(p)
except Exception:
    pass' 2>/dev/null || true)"
else
    exit 0
fi

[ -z "$file_path" ] && exit 0

# .html / .htm 以外は弾く(case-insensitive)。`printf|tr` の fork を避け、case の文字クラスで
# 大文字小文字を吸収する(hot path の builtin 化 — M8 review #6。bash 3 でも動く)。
case "$file_path" in
    *.[Hh][Tt][Mm][Ll] | *.[Hh][Tt][Mm]) ;;
    *) exit 0 ;;
esac

# スロットル: 同一パスかつ前回から THROTTLE_SECONDS 以内なら no-op
mkdir -p "$STATE_DIR" 2>/dev/null || true
now=$(date +%s)
if [ -r "$STATE_FILE" ]; then
    # フォーマット: "<epoch>\t<path>"。tail の fork を避け builtin read で 1 行読む(state は単一行 — M8 review #6)。
    IFS= read -r last_line < "$STATE_FILE" 2>/dev/null || true
    # tab 必須: tab 無し(旧版 "<epoch>\n" / 部分書込破損)は壊れた state として無視する。
    # 無視しないと `${last_line#*<tab>}` が行全体を返し last_path が誤一致してスロットルが
    # 誤抜けする(M8 review #2 — 数値ガード #1 と整合させる)。
    case "$last_line" in
        *"	"*) ;;
        *) last_line="" ;;
    esac
    last_epoch="${last_line%%	*}"
    last_path="${last_line#*	}"
    # last_epoch が数値のときだけスロットル判定する。state 破損で非数値が入ると
    # `$((now - last_epoch))` が算術展開エラーを stderr に出すため、数値ガードで弾く(M8 review #1)。
    case "$last_epoch" in
        '' | *[!0-9]*) ;;  # 空 or 非数値 → スロットルせず open に進む(state 破損で詰まらせない)
        *)
            if [ "$last_path" = "$file_path" ] && [ "$((now - last_epoch))" -lt "$THROTTLE_SECONDS" ]; then
                exit 0
            fi
            ;;
    esac
fi
# state 書き込みは tmp に書いて rename(POSIX アトミック)。並走 hook の truncate+write 交錯で
# last-open が部分破損するのを防ぐ(M8 review #3)。tmp 名は PID で衝突回避。
# 書込/rename 失敗(state dir が read-only / 容量逼迫等)は DEBUG 時のみ記録(M8 review #10)。
tmp_state="$STATE_FILE.$$"
if printf '%s\t%s\n' "$now" "$file_path" > "$tmp_state" 2>/dev/null && mv -f "$tmp_state" "$STATE_FILE" 2>/dev/null; then
    :
else
    rm -f "$tmp_state" 2>/dev/null || true
    dbg "state write failed: $STATE_FILE"
fi

# 起動(失敗しても exit 0)。`-` 始まりの file_path を open(1) がオプション誤解釈しないよう
# `--`(end-of-options)を置く(M8 review #1: CONFIRMED — 例 `-W.html` で誤起動)。
# 失敗(未インストール / lsregister 未登録 / bundle id 衝突)は DEBUG 時のみ記録(M8 review #5)。
if ! "$OPEN_CMD" -g -b "$BUNDLE_ID" -- "$file_path" >/dev/null 2>&1; then
    dbg "open failed (bundle=$BUNDLE_ID): $file_path"
fi
exit 0
