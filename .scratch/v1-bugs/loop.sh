#!/usr/bin/env bash
# Real-editor feedback loop for fullstop.nvim.
#
# Drives a REAL interactive Neovim — your own config, a real pty via tmux — over
# an RPC socket: set the buffer, place the cursor, type the actual mapped key,
# read the buffer back as JSON. This is the check `make test` cannot make: that
# the plugin works in the editor you use, with the plugins you have loaded.
#
#   .scratch/v1-bugs/loop.sh              # default matrix
#   KEY='<C-CR>' .scratch/v1-bugs/loop.sh # a different binding
#   NVIM_CONFIG=NONE .scratch/v1-bugs/loop.sh   # isolate: no user config
#
# Three environment traps, all handled below, all of which cost time to find:
#   * macOS caps unix socket paths at ~104 bytes, hence the short /tmp socket.
#   * Neovim needs ~10s to load a full config; keys sent before it is ready can
#     kill it outright, so readiness is polled rather than slept on.
#   * A stale swapfile parks Neovim at an E325 prompt where it silently eats all
#     input and every case "fails" for no visible reason, hence -n.
set -u

SESS="fullstop-loop"
SOCK="/tmp/fullstop-loop.sock"
KEY="${KEY:-<C-j>}"
FT="${FT:-typescript}"
NVIM_CONFIG="${NVIM_CONFIG:-}"
FIXTURE="/tmp/fullstop-loop-fixture.ts"
NORMAL_MAP=""

rem() { nvim --server "$SOCK" --remote-expr "$1" 2>/dev/null; }
send() { nvim --server "$SOCK" --remote-send "$1" 2>/dev/null; }

start() {
  local args="-n --listen '$SOCK' '$FIXTURE'"
  [ "$NVIM_CONFIG" = "NONE" ] && args="-u NONE $args"

  tmux kill-session -t "$SESS" 2>/dev/null
  rm -f "$SOCK"
  printf 'const x = 1\n' > "$FIXTURE"
  tmux new-session -d -s "$SESS" -x 120 -y 40 "nvim $args"

  for _ in $(seq 100); do rem '1' >/dev/null 2>&1 && break; sleep 0.2; done
  for _ in $(seq 75); do [ "$(rem '&filetype')" = "$FT" ] && break; sleep 0.2; done
  if [ "$(rem '&filetype')" != "$FT" ]; then
    echo "FATAL: Neovim never became ready (filetype='$(rem '&filetype')', mode='$(rem 'mode(1)')')"
    echo "       mode 'r?' means it is stuck at a prompt — check :messages in tmux attach -t $SESS"
    exit 1
  fi
  NORMAL_MAP="$(rem "maparg('$KEY','n')")"
  echo "ready: ft=$(rem '&filetype')  key=$KEY  insert=$(rem "maparg('$KEY','i')")  normal=${NORMAL_MAP:-unmapped}"
  echo
}

pass=0
fail=0

# run <name> <lua-list-of-lines> <cursor-row> <i|n> <expected-json> [col]
#
# Without `col` the cursor lands at end of line (`A`), which is where a user
# fires from mid-typing. Pass `col` (0-based) to fire from *inside* a line — the
# only way to reach a head whose line ends on a brace, since a cursor on the
# brace is a cursor in a container ("no statement here" → Advance). It is set
# after the <Esc>, which would otherwise drag it a column left.
run() {
  local name="$1" lines="$2" row="$3" mode="$4" want="$5" col="${6:-}"
  # A real config may already own $KEY in normal mode (window/pane navigation is
  # the usual culprit), which shadows the plugin's map. That is the environment's
  # answer, not a plugin failure, so skip rather than stay permanently red — the
  # normal-mode fire itself is covered in tests/test_integration.lua.
  if [ "$mode" = "n" ] && [ "$NORMAL_MAP" != '<Plug>(CompleteStatement)' ]; then
    printf 'SKIP  %-26s normal-mode %s is %s\n' "$name" "$KEY" "${NORMAL_MAP:-unmapped}"
    return
  fi
  rem "luaeval(\"vim.api.nvim_buf_set_lines(0,0,-1,false,$lines)\")" >/dev/null
  rem "luaeval(\"vim.api.nvim_win_set_cursor(0,{$row,0})\")" >/dev/null
  send '<Esc>'
  if [ -n "$col" ]; then
    rem "luaeval(\"vim.api.nvim_win_set_cursor(0,{$row,$col})\")" >/dev/null
    [ "$mode" = "i" ] && send 'i'
  else
    [ "$mode" = "i" ] && send 'A'
  fi
  sleep 0.15
  send "$KEY"
  sleep 0.5
  send '<Esc>'
  sleep 0.1

  local got
  got="$(rem "json_encode(getline(1,'\$'))")"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    printf 'PASS  %-26s %s\n' "$name" "$got"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-26s\n        got:  %s\n        want: %s\n' "$name" "$got" "$want"
  fi
}

start

echo "=== top level (the shapes the README advertises) ==="
run "call-args (insert)" "{'const x = getValue(a, b'}" 1 i '["const x = getValue(a, b);", ""]'
run "if-block (insert)" "{'if (cond'}" 1 i '["if (cond) {", "  ", "}"]'
run "function (insert)" "{'function foo(a: string'}" 1 i '["function foo(a: string) {", "  ", "}"]'
run "arrow (insert)" "{'const f = (x) =>'}" 1 i '["const f = (x) => {", "  ", "};"]'
run "already-complete" "{'const w = 1;'}" 1 i '["const w = 1;", ""]'
run "empty line" "{''}" 1 i '["", ""]'
run "call-args (normal)" "{'const y = foo(a'}" 1 n '["const y = foo(a);", ""]'

echo
echo "=== nested inside a block (issue 01) ==="
run "nested call-args" \
  "{'function outer() {','  const x = getValue(a, b','}'}" 2 i \
  '["function outer() {", "  const x = getValue(a, b);", "  ", "}"]'
run "nested if" \
  "{'function outer() {','  if (cond','}'}" 2 i \
  '["function outer() {", "  if (cond) {", "    ", "  }", "}"]'
run "nested return" \
  "{'function outer() {','  return foo(a','}'}" 2 i \
  '["function outer() {", "  return foo(a);", "  ", "}"]'
run "nested in arrow body" \
  "{'const f = () => {','  const y = bar(1, 2','}'}" 2 i \
  '["const f = () => {", "  const y = bar(1, 2);", "  ", "}"]'
run "nested 2 levels deep" \
  "{'function o() {','  if (a) {','    const z = baz(q','  }','}'}" 3 i \
  '["function o() {", "  if (a) {", "    const z = baz(q);", "    ", "  }", "}"]'
run "class method body" \
  "{'class C {','  m() {','    const v = call(x','  }','}'}" 3 i \
  '["class C {", "  m() {", "    const v = call(x);", "    ", "  }", "}"]'

echo
echo "=== body slot (issue 05) ==="
# The reported bug: the block must land on the head, not on the statement below.
run "if head above body" "{'if (test)','foo();'}" 1 i '["if (test) {", "  ", "}", "foo();"]'
run "fired on that body" "{'if (test)','foo();'}" 2 i '["if (test)", "foo();", ""]'
run "multi-line head" "{'if (','  test',')','foo();'}" 1 i \
  '["if (", "  test", ") {", "  ", "}", "foo();"]'
run "else head above body" "{'if (a) {','} else','foo();'}" 2 i \
  '["if (a) {", "} else {", "  ", "}", "foo();"]'
run "nested if head" "{'function outer() {','  if (test)','  foo();','}'}" 2 i \
  '["function outer() {", "  if (test) {", "    ", "  }", "  foo();", "}"]'
# A slot already filled never opens a block, however block-ish the keyword.
run "same-line if body" "{'if (test) foo();'}" 1 i '["if (test) foo();", ""]'
run "same-line else body" "{'if (a) {','} else foo();'}" 2 i '["if (a) {", "} else foo();", ""]'
run "guard return" "{'if (!a) return'}" 1 i '["if (!a) return;", ""]'
run "guard throw" "{'if (!a) throw new Error(msg'}" 1 i '["if (!a) throw new Error(msg);", ""]'
# Braced bodies: fired from inside the head, since these lines end on a brace.
run "closed if block" "{'if (a) {','  foo();','}'}" 1 i \
  '["if (a) {", "  foo();", "}", ""]' 3
run "open block brace" "{'if (a) { foo();'}" 1 i '["if (a) { foo(); }", ""]' 3
run "assigned fn block" "{'const f = function () {','}'}" 1 i \
  '["const f = function () {", "};", ""]' 10
# ...and fired on the statement *inside* that open block, the cursor selects it:
# it is already complete, so this advances instead of reaching up to the `if`.
run "body in open block" "{'if (a) { foo();'}" 1 i '["if (a) { foo();", ""]'

echo
echo "=== realistic top-level shapes ==="
run "await chain" "{'const { data } = await db.from(t).select(cols'}" 1 i \
  '["const { data } = await db.from(t).select(cols);", ""]'
run "nested calls" "{'const r = foo(bar(a, b'}" 1 i '["const r = foo(bar(a, b));", ""]'
run "object literal arg" "{'const p = fn({ a: 1, b: 2'}" 1 i '["const p = fn({ a: 1, b: 2 });", ""]'

echo
echo "$pass passed, $fail failed"
tmux kill-session -t "$SESS" 2>/dev/null
rm -f "$SOCK" "$FIXTURE"
[ "$fail" -eq 0 ]
