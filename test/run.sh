#!/usr/bin/env bash
#
# Automated test suite for the list-tools Pi extension.
#
# Design notes:
#  - Every test runs pi with `--no-extensions -e "$EXT"` so ONLY the builtin
#    tools plus this extension are loaded. That makes results deterministic on
#    any machine (CI included), independent of which packages a user has
#    installed. The builtin set is stable: bash, edit, find, grep, ls, read,
#    write (7 tools).
#  - No API key or network is required: the extension writes its output during
#    the `session_start` event and calls process.exit(0) before any LLM call.
#  - Output correctness is checked on STDOUT specifically (fd 1), because the
#    original bugs were (a) output landing on stderr and (b) >64KB pipe
#    truncation. Tests pipe through `cat`/`grep`/`wc` to exercise real pipes.
#
# Usage:  test/run.sh            (uses `pi` on PATH)
#         PI=/path/to/pi test/run.sh
set -uo pipefail

PI="${PI:-pi}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXT="$REPO_DIR/list-tools.ts"
MIXED_EXT="$SCRIPT_DIR/fixtures/mixed-tools.ts"

# Base invocation: builtin-only + our extension, deterministic everywhere.
# We run in a temp cwd so no project-local .pi/extensions interfere.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# runtool <args...> : run pi with the extension, capture STDOUT only (fd1).
# stderr is discarded so we prove the dump is on real stdout and pipeable.
runtool() {
	( cd "$WORKDIR" && "$PI" --no-extensions -e "$EXT" "$@" 2>/dev/null )
}

PASS=0
FAIL=0
FAILED_NAMES=()

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

# assert_contains <name> <haystack> <needle>
assert_contains() {
	if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1" "expected to contain: $3"; fi
}
# assert_not_contains <name> <haystack> <needle>
assert_not_contains() {
	if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1" "should NOT contain: $3"; else ok "$1"; fi
}
# assert_eq <name> <actual> <expected>
assert_eq() {
	if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3' got '$2'"; fi
}

echo "== list-tools test suite =="
echo "pi: $($PI --version 2>/dev/null | head -1 || echo unknown)"
echo "ext: $EXT"
echo

# ---------------------------------------------------------------------------
echo "[1] table mode (default) — pipeable on stdout"
OUT="$(runtool --list-tools)"
assert_contains  "table: header present"        "$OUT" "Pi tools"
assert_contains  "table: terminal header"       "$OUT" "Tool"
assert_contains  "table: extension header"      "$OUT" "Extension"
assert_contains  "table: params header"         "$OUT" "Params"
assert_contains  "table: description header"    "$OUT" "Description"
assert_not_contains "table: not markdown"       "$OUT" "| Tool | Extension | Params | Description |"
assert_contains  "table: builtin read row"      "$OUT" "read"
assert_contains  "table: builtin write row"     "$OUT" "write"
assert_contains  "table: extension col labeled" "$OUT" "(built-in)"
# Builtin-only baseline is exactly 7 tools.
assert_contains  "table: count is 7"            "$OUT" "Pi tools (7)"

OUT="$( ( cd "$WORKDIR" && "$PI" --no-extensions -e "$MIXED_EXT" -e "$EXT" --list-tools 2>/dev/null ) )"
assert_contains "table: mixed fixture count" "$OUT" "Pi tools (9)"
NEXT_AFTER_AAA="$(printf '%s\n' "$OUT" | awk '/^aaa_fixture_tool[[:space:]]/ { getline; print; exit }')"
assert_contains "table: sorts by extension before tool" "$NEXT_AFTER_AAA" "zzz_fixture_tool"

# ---------------------------------------------------------------------------
echo "[2] output is on STDOUT (not stderr) and survives a pipe"
# grep only sees fd1; if output were on stderr this would be empty.
CNT="$( ( cd "$WORKDIR" && "$PI" --no-extensions -e "$EXT" --list-tools 2>/dev/null | grep -c '(built-in)' ) )"
if [ "$CNT" -ge 7 ]; then ok "stdout: >=7 builtin rows through grep pipe"; else bad "stdout: builtin rows through pipe" "got $CNT"; fi
# stderr should NOT carry the table.
ERR="$( ( cd "$WORKDIR" && "$PI" --no-extensions -e "$EXT" --list-tools 2>&1 >/dev/null ) )"
assert_not_contains "stderr: does not carry the table" "$ERR" "Pi tools"

# ---------------------------------------------------------------------------
echo "[3] verbose mode — exhaustive markdown"
OUT="$(runtool --list-tools verbose)"
assert_contains "verbose: title"             "$OUT" "# Pi tool registry"
assert_contains "verbose: per-tool heading"  "$OUT" "## \`read\`"
assert_contains "verbose: verbatim desc lbl" "$OUT" "Description (verbatim)"
assert_contains "verbose: parameters block"  "$OUT" "Parameters:"
assert_contains "verbose: per-param desc"    "$OUT" "Path to the file to read"
assert_contains "verbose: guidelines block"  "$OUT" "Prompt guidelines (verbatim)"
# equals-form must match space-form.
OUT2="$(runtool --list-tools=verbose)"
assert_eq "verbose: =form equals space-form" "$OUT2" "$OUT"

# ---------------------------------------------------------------------------
echo "[4] json mode — valid JSON, fully piped (>64KB guard is mode-agnostic)"
JOUT="$(runtool --list-tools json)"
# Must be parseable JSON.
if printf '%s' "$JOUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list); print(len(d))' >/tmp/jcount 2>/dev/null; then
	ok "json: valid JSON array"
	assert_eq "json: 7 builtin tools" "$(cat /tmp/jcount)" "7"
else
	bad "json: valid JSON array" "python json.load failed"
fi
assert_contains "json: has description field"   "$JOUT" "\"description\""
assert_contains "json: has parameters schema"   "$JOUT" "\"parameters\""
assert_contains "json: has sourceInfo"          "$JOUT" "\"sourceInfo\""
assert_contains "json: per-param description"   "$JOUT" "Path to the file to read"

# ---------------------------------------------------------------------------
echo "[5] large-output pipe integrity (>64KB partial-write regression)"
# builtin json must not be truncated: it must end with the closing bracket
# after being piped through cat.
TAIL="$(runtool --list-tools json | cat | tail -c 3 | tr -d '[:space:]')"
assert_eq "json: pipe ends with closing bracket" "$TAIL" "]"

# Deterministic >64KB guard using the big-emitter fixture: pipe a 200KB payload
# and confirm every byte arrives (single fs.writeSync would truncate at ~64KB).
BIG_EXT="$SCRIPT_DIR/fixtures/big-emitter.ts"
BYTES="$( ( cd "$WORKDIR" && "$PI" --no-extensions -e "$BIG_EXT" --emit-big 2>/dev/null | wc -c ) )"
BYTES="$(printf '%s' "$BYTES" | tr -d '[:space:]')"
if [ "$BYTES" -eq 200000 ]; then ok "big: full 200000-byte payload piped intact"; else bad "big: full payload piped intact" "got $BYTES bytes (expected 200000)"; fi
BIGTAIL="$( ( cd "$WORKDIR" && "$PI" --no-extensions -e "$BIG_EXT" --emit-big 2>/dev/null | tail -c 16 | tr -d '[:space:]' ) )"
assert_eq "big: sentinel tail survives pipe" "$BIGTAIL" "END_OF_BIG_EMIT"

# ---------------------------------------------------------------------------
echo "[6] --show-tool <name>"
OUT="$(runtool --show-tool read)"
assert_contains "show-tool: heading"        "$OUT" "## \`read\`"
assert_contains "show-tool: params"         "$OUT" "Parameters:"
assert_contains "show-tool: per-param desc" "$OUT" "Path to the file to read"
# unknown tool -> not found + suggestion when a substring matches
OUT="$(runtool --show-tool wri)"
assert_contains "show-tool: not-found msg"  "$OUT" "not found"
assert_contains "show-tool: suggestion"     "$OUT" "write"

# ---------------------------------------------------------------------------
echo "[7] --tools-filter"
OUT="$(runtool --list-tools --tools-filter read,write)"
assert_contains     "filter: includes read"   "$OUT" "read"
assert_contains     "filter: includes write"  "$OUT" "write"
assert_not_contains "filter: excludes grep"   "$OUT" "grep"

# ---------------------------------------------------------------------------
echo "[8] flag-form parsing: bare defaults to table; bad mode falls back"
OUT="$(runtool --list-tools table)"
assert_contains "flag: explicit table"       "$OUT" "Pi tools"
OUT="$(runtool --list-tools bogusmode)"
assert_contains "flag: bad mode -> table"    "$OUT" "Tool"

# ---------------------------------------------------------------------------
echo "[9] regression: without --list-tools the extension stays silent"
# No flag => extension must not emit the dump. (No LLM call needed: we check
# that stdout has no table header. A normal run would try to contact a model,
# so we cap it with a tiny timeout and only inspect stdout for our marker.)
OUT="$( ( cd "$WORKDIR" && timeout 20 "$PI" --no-extensions -e "$EXT" -p "hi" 2>/dev/null ) || true )"
assert_not_contains "regression: no dump without flag" "$OUT" "Pi tools ("

echo
echo "== results: $PASS passed, $FAIL failed =="
if [ "$FAIL" -gt 0 ]; then
	printf 'Failed tests:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
	exit 1
fi
exit 0
