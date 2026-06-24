#!/bin/bash
# M8: hooks/open-html.sh の入力処理・拡張子フィルタ・スロットルを JSON fixture で検証する。
# `open` は OPEN_CMD で stub に差し替え(呼び出し回数を一時ファイルにカウント)。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
HOOK="$ROOT/hooks/open-html.sh"
PASS=0; FAIL=0

# stub: 呼び出しごとに $OPEN_COUNT_FILE に追記。
# セットアップ失敗は fail-loud(set -e は run() の rc 捕捉と相性が悪いため各所に || exit 1)。
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
OPEN_COUNT_FILE="$TMP/open-calls"
STUB="$TMP/open-stub"
cat > "$STUB" <<'EOF' || exit 1
#!/bin/bash
printf '%s\n' "$*" >> "$OPEN_COUNT_FILE"
EOF
chmod +x "$STUB" || exit 1

count_calls() {
    [ -r "$OPEN_COUNT_FILE" ] && wc -l < "$OPEN_COUNT_FILE" | tr -d ' ' || echo 0
}

run() {
    # $1=case name, $2=expected open count, $3=JSON payload, $4=throttle override (sec)
    local name="$1" expected="$2" payload="$3" throttle="${4:-5}"
    rm -f "$OPEN_COUNT_FILE"
    local state_dir="$TMP/state-$RANDOM"
    HTMLVIEWER_HOOK_STATE_DIR="$state_dir" HTMLVIEWER_HOOK_THROTTLE="$throttle" \
        OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
        bash "$HOOK" <<<"$payload"
    local rc=$? actual; actual=$(count_calls)
    if [ "$rc" -eq 0 ] && [ "$actual" -eq "$expected" ]; then
        echo "✔ $name (open=$actual)"; PASS=$((PASS+1))
    else
        echo "✘ $name expected open=$expected got open=$actual rc=$rc"; FAIL=$((FAIL+1))
    fi
}

# ── 受理(.html) ──
run ".html を受信 → open 1 回" 1 '{"tool_input":{"file_path":"/tmp/a.html"}}'
run ".htm を受信 → open 1 回" 1 '{"tool_input":{"file_path":"/tmp/a.htm"}}'
run ".HTML(大文字)を受信 → open 1 回" 1 '{"tool_input":{"file_path":"/tmp/A.HTML"}}'

# ── 拒否(no-op) ──
run "非 .html は no-op" 0 '{"tool_input":{"file_path":"/tmp/a.md"}}'
run "file_path 無しは no-op" 0 '{"tool_input":{"other":"x"}}'
run "tool_input 無しは no-op" 0 '{"foo":"bar"}'
run "壊れた JSON は no-op" 0 'not-json'
run "空入力は no-op" 0 ''

# ── スロットル ──
echo "-- スロットル: 同一ファイルを 2 連発 →  open 1 回 --"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-throttle"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/dup.html"}}'
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/dup.html"}}'
calls=$(count_calls)
if [ "$calls" -eq 1 ]; then
    echo "✔ スロットル同一連発 (open=$calls)"; PASS=$((PASS+1))
else
    echo "✘ スロットル同一連発 expected=1 got=$calls"; FAIL=$((FAIL+1))
fi

echo "-- スロットル: 別ファイルは通る → open 2 回 --"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-diff"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/a.html"}}'
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/b.html"}}'
calls=$(count_calls)
if [ "$calls" -eq 2 ]; then
    echo "✔ スロットル別ファイル (open=$calls)"; PASS=$((PASS+1))
else
    echo "✘ スロットル別ファイル expected=2 got=$calls"; FAIL=$((FAIL+1))
fi

echo "-- スロットル: 0 秒設定なら同一連発でも 2 回通る --"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-zero"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=0 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/x.html"}}'
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=0 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/x.html"}}'
calls=$(count_calls)
if [ "$calls" -eq 2 ]; then
    echo "✔ throttle=0 で透過 (open=$calls)"; PASS=$((PASS+1))
else
    echo "✘ throttle=0 で透過 expected=2 got=$calls"; FAIL=$((FAIL+1))
fi

echo "-- state 破損(非数値 epoch)でも算術エラーを出さず open 1 回(M8 review #1)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-corrupt"
mkdir -p "$STATE" || exit 1
printf 'not-a-number\t/tmp/dup.html\n' > "$STATE/last-open" || exit 1
stderr_file="$TMP/corrupt-stderr"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/dup.html"}}' 2>"$stderr_file"
calls=$(count_calls); stderr_bytes=$(wc -c < "$stderr_file" | tr -d ' ')
if [ "$calls" -eq 1 ] && [ "$stderr_bytes" -eq 0 ]; then
    echo "✔ 破損 state で open=${calls} / stderr 空"; PASS=$((PASS+1))
else
    echo "✘ 破損 state expected open=1/stderr空 got open=${calls} stderr=${stderr_bytes}B"; FAIL=$((FAIL+1))
fi

echo "-- '-' 始まりの file_path でも open 1 回 + 引数に '--' セパレータ(M8 review #1)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-dash"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"-W.html"}}'
calls=$(count_calls)
if [ "$calls" -eq 1 ] && grep -q -- '-- -W.html' "$OPEN_COUNT_FILE"; then
    echo "✔ '-' 始まりパスで open=${calls} + '--' 付与"; PASS=$((PASS+1))
else
    echo "✘ '-' 始まりパス expected open=1/'--'付与 got open=${calls} args=[$(cat "$OPEN_COUNT_FILE" 2>/dev/null)]"; FAIL=$((FAIL+1))
fi

echo "-- THROTTLE 非数値(off)は既定 5 に正規化しエラーを出さない(M8 review #2)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-badthrottle"
stderr_file="$TMP/badthrottle-stderr"
for _ in 1 2; do
    HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=off \
        OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
        bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/t.html"}}' 2>>"$stderr_file"
done
calls=$(count_calls); stderr_bytes=$(wc -c < "$stderr_file" | tr -d ' ')
if [ "$calls" -eq 1 ] && [ "$stderr_bytes" -eq 0 ]; then
    echo "✔ THROTTLE=off で正規化(同一連発 open=${calls} / stderr 空)"; PASS=$((PASS+1))
else
    echo "✘ THROTTLE=off expected open=1/stderr空 got open=${calls} stderr=${stderr_bytes}B"; FAIL=$((FAIL+1))
fi

echo "-- state 書き込み後に一時ファイル(.PID)が残らない(M8 review #3 アトミック)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-atomic"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/a.html"}}'
leftover=$(find "$STATE" -name 'last-open.*' 2>/dev/null | wc -l | tr -d ' ')
if [ -r "$STATE/last-open" ] && [ "$leftover" -eq 0 ]; then
    echo "✔ state 確定 + tmp 残骸なし(leftover=${leftover})"; PASS=$((PASS+1))
else
    echo "✘ アトミック書込 expected last-open存在/tmp残骸0 got leftover=${leftover}"; FAIL=$((FAIL+1))
fi

echo "-- tab 無しの破損 state は無視され、エラーを出さず open 1 回(M8 review #2)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-notab"
mkdir -p "$STATE" || exit 1
printf '12345\n' > "$STATE/last-open" || exit 1   # tab 無し(部分書込破損を模す)
stderr_file="$TMP/notab-stderr"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/n.html"}}' 2>"$stderr_file"
calls=$(count_calls); stderr_bytes=$(wc -c < "$stderr_file" | tr -d ' ')
if [ "$calls" -eq 1 ] && [ "$stderr_bytes" -eq 0 ]; then
    echo "✔ tab 無し破損 state で open=${calls} / stderr 空"; PASS=$((PASS+1))
else
    echo "✘ tab 無し破損 state expected open=1/stderr空 got open=${calls} stderr=${stderr_bytes}B"; FAIL=$((FAIL+1))
fi

echo "-- '-a ...' 注入を含む .html パスも '--' で 1 パス扱い(M8 review #8 負テスト)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-inject"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="$STUB" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"-a Calculator.app.html"}}'
calls=$(count_calls)
# `--` の直後に注入文字列が 1 トークン(パス)として現れる = open(1) のフラグ誤解釈を防げている
if [ "$calls" -eq 1 ] && grep -q -- '-- -a Calculator.app.html' "$OPEN_COUNT_FILE"; then
    echo "✔ '-a' 注入も '--' でパス扱い(open=${calls})"; PASS=$((PASS+1))
else
    echo "✘ '-a' 注入 expected open=1/'--'保護 got open=${calls} args=[$(cat "$OPEN_COUNT_FILE" 2>/dev/null)]"; FAIL=$((FAIL+1))
fi

# 注: jq 不在 → python3 フォールバックの強制テストは、PATH を絞ると macOS の /usr/bin/python3
# (CLT shim)が環境不足でハングするため安定実行できない。dual fallback は維持し(M8 review #4)、
# python3 分岐は単純な heredoc として据え置く(本テストでは検証しない)。

echo "-- HTMLVIEWER_HOOK_DEBUG=1 で open 失敗時に last-error が残る(M8 review #5)--"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-debug"
# OPEN_CMD を必ず失敗するコマンドにして DEBUG ログを誘発
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 HTMLVIEWER_HOOK_DEBUG=1 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="false" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/d.html"}}'
if [ -s "$STATE/last-error" ] && grep -q 'open failed' "$STATE/last-error"; then
    echo "✔ DEBUG=1 で open 失敗が last-error に記録"; PASS=$((PASS+1))
else
    echo "✘ DEBUG ログ expected last-error に 'open failed' got [$(cat "$STATE/last-error" 2>/dev/null)]"; FAIL=$((FAIL+1))
fi

echo "-- 既定(DEBUG 無し)では last-error を作らない --"
rm -f "$OPEN_COUNT_FILE"
STATE="$TMP/state-nodebug"
HTMLVIEWER_HOOK_STATE_DIR="$STATE" HTMLVIEWER_HOOK_THROTTLE=5 \
    OPEN_COUNT_FILE="$OPEN_COUNT_FILE" OPEN_CMD="false" \
    bash "$HOOK" <<<'{"tool_input":{"file_path":"/tmp/d.html"}}'
if [ ! -e "$STATE/last-error" ]; then
    echo "✔ DEBUG 無しで last-error 不在"; PASS=$((PASS+1))
else
    echo "✘ DEBUG 無しなのに last-error が存在"; FAIL=$((FAIL+1))
fi

echo
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
