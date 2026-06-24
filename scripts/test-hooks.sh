#!/bin/bash
# M8: hooks/open-html.sh の入力処理・拡張子フィルタ・スロットルを JSON fixture で検証する。
# `open` は OPEN_CMD で stub に差し替え(呼び出し回数を一時ファイルにカウント)。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/open-html.sh"
PASS=0; FAIL=0

# stub: 呼び出しごとに $OPEN_COUNT_FILE に追記
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OPEN_COUNT_FILE="$TMP/open-calls"
STUB="$TMP/open-stub"
cat > "$STUB" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$OPEN_COUNT_FILE"
EOF
chmod +x "$STUB"

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

echo
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
