#!/bin/bash
# Tests for bin/stop-check-counts.sh: counts over the stop-check verdict log, by kind, in a window,
# plus an eight-week weekly table. Model-free and read-only.
#
# Every fixture line is synthetic and the clock is injected (STOP_CHECK_NOW), so the expected numbers
# below are literals worked out by hand, not another run of the code under test. The log's real
# `message` and `note` fields hold quoted session text; the script must print counts only.
#
# Usage:  tests/stop-check-counts.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp scct
BIN="$REPO/bin/stop-check-counts.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_eq(){     [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }
assert_grep(){   grep -q -- "$2" "$1" 2>/dev/null && ok "$3" || no "$3 (no /$2/ in $1)"; }
assert_nogrep(){ grep -q -- "$2" "$1" 2>/dev/null && no "$3 (/$2/ unexpectedly in $1)" || ok "$3"; }

# 2026-11-19T12:00:00Z, a Thursday. Its UTC week starts Monday 2026-11-16.
NOW=1795089600
LOG="$SUITE_TMP/verdicts.jsonl"
M='"message":"SECRET-MESSAGE-TEXT","note":"SECRET-NOTE-TEXT"'
cat > "$LOG" <<EOF
{"kind":"ok","at":"2026-11-19T11:00:00.500Z",$M}
{"kind":"ok","at":"2026-11-19T10:00:00Z",$M}
{"kind":"ask","at":"2026-11-19T09:00:00.000Z",$M}
{"kind":"bad","at":"2026-11-18T01:00:00.123Z",$M}
{"kind":"weird","at":"2026-11-18T05:00:00Z",$M}
{"kind":"error","at":"2026-11-18T00:00:00Z",$M}
{"kind":"ok","at":"2026-11-17T23:59:59Z",$M}
{"kind":"ok","at":"2026-11-15T23:59:59Z",$M}
{"kind":"ok","at":"2026-11-10T12:00:00Z",$M}
{"kind":"bad","at":"2026-11-09T00:00:00Z",$M}
{"kind":"ok","at":"2026-09-28T00:00:00Z",$M}
{"kind":"ok","at":"2026-09-27T23:59:59Z",$M}
{"kind":"bad","at":"2026-11-20T00:00:00Z",$M}
not json at all
{"kind":"ok",$M}
{"kind":"ok","at":"garbage",$M}
EOF

run(){ # args... -> $OUT, $RC
  STOP_CHECK_VERDICTS="$LOG" STOP_CHECK_NOW="$NOW" bash "$BIN" "$@" > "$SUITE_TMP/out" 2> "$SUITE_TMP/err"
  RC=$?; OUT="$SUITE_TMP/out"
}
cell(){ # $1=section start regex, $2=first column value, $3=column number -> that cell
  awk -v s="$1" -v k="$2" -v c="$3" '$0 ~ s { on = 1; next } on && $1 == k { print $c; exit }' "$OUT"
}

echo "# default window is 36 hours, boundary inclusive, grouped by kind"
run
assert_eq "$RC" "0" "exits 0"
assert_grep "$OUT" 'last 36h' "header names the window"
assert_grep "$OUT" '2026-11-18T00:00:00Z' "header names the window start"
assert_eq "$(cell '^kind' ok 2)" "2" "ok in window (the 23:59:59 line the day before is out)"
assert_eq "$(cell '^kind' ask 2)" "1" "ask in window"
assert_eq "$(cell '^kind' bad 2)" "1" "bad in window"
assert_eq "$(cell '^kind' error 2)" "1" "error exactly at the cutoff is in"
assert_eq "$(cell '^kind' weird 2)" "1" "a kind the script has never heard of still gets its row"
assert_eq "$(cell '^kind' total 2)" "6" "window total"
assert_grep "$OUT" 'unparseable.*3' "three unusable lines are counted, not silently dropped"

echo "# --since-hours narrows the window"
run --since-hours 1
assert_grep "$OUT" 'last 1h' "header names a 1h window"
assert_eq "$(cell '^kind' total 2)" "1" "1h window holds only the 11:00:00.500 line"
assert_eq "$(cell '^kind' ok 2)" "1" "and it is an ok"

echo "# weekly table: eight UTC weeks starting Monday, oldest first, zero weeks kept"
run
assert_grep "$OUT" '^week ' "weekly header"
cur=$(awk '$1 == "2026-11-16"' "$OUT")
set -- $cur
assert_eq "$*" "2026-11-16 1 1 1 3 1 7" "current week row: ask bad error ok weird total"
prev=$(awk '$1 == "2026-11-09"' "$OUT")
set -- $prev
assert_eq "$*" "2026-11-09 0 1 0 2 0 3" "Sunday 23:59:59 belongs to the week of the Monday before it"
gap=$(awk '$1 == "2026-11-02"' "$OUT")
set -- $gap
assert_eq "$*" "2026-11-02 0 0 0 0 0 0" "an empty week is a row of zeros, not a gap"
first=$(awk '/^week /{on=1; next} on && $1 ~ /^20/ {print $1; exit}' "$OUT")
assert_eq "$first" "2026-09-28" "table starts eight weeks back"
assert_eq "$(awk '/^week /{on=1; next} on && $1 ~ /^20/' "$OUT" | wc -l | tr -d ' ')" "8" "exactly eight rows"
assert_nogrep "$OUT" '^2026-09-21' "the week before the window is not shown"

echo "# counts only: never a message or note"
assert_nogrep "$OUT" 'SECRET' "no message or note text in the output"

echo "# failure modes are loud"
STOP_CHECK_VERDICTS="$SUITE_TMP/nope.jsonl" STOP_CHECK_NOW="$NOW" bash "$BIN" > "$SUITE_TMP/out" 2> "$SUITE_TMP/err"; RC=$?
assert_eq "$RC" "1" "a missing log exits 1"
cat "$SUITE_TMP/out" "$SUITE_TMP/err" > "$SUITE_TMP/both"
assert_grep "$SUITE_TMP/both" 'no verdict log' "and says so"
: > "$SUITE_TMP/empty.jsonl"
STOP_CHECK_VERDICTS="$SUITE_TMP/empty.jsonl" STOP_CHECK_NOW="$NOW" bash "$BIN" > "$SUITE_TMP/out" 2> "$SUITE_TMP/err"; RC=$?
assert_eq "$RC" "0" "an empty log is a valid zero"
OUT="$SUITE_TMP/out"
assert_eq "$(cell '^kind' total 2)" "0" "empty log: total 0"
run --since-hours abc
assert_eq "$RC" "2" "a non-numeric window exits 2"
run --since-hours
assert_eq "$RC" "2" "a missing window value exits 2"

echo "# bash 3.2 and a real clock: no STOP_CHECK_NOW still runs"
STOP_CHECK_VERDICTS="$LOG" bash "$BIN" > "$SUITE_TMP/out" 2> "$SUITE_TMP/err"; RC=$?
assert_eq "$RC" "0" "runs against the real clock"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
