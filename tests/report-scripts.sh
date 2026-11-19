#!/bin/bash
# Tests for bin/report-scripts.sh, the one collector behind every "run this command for me" operator note.
#
# L2 has Read and Glob only, so a note that asks for a command's output used to fail silently. The
# collector runs each allowlisted command before L2 and writes the result where L2 can read it. What
# matters here is the failure matrix, because the whole point is that a failure is content, never
# silence and never an aborted run: a missing script, a non-zero exit, a timeout and a bad conf line
# each still produce a file and an index row.
#
# Usage:  tests/report-scripts.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp rptst
BIN="$REPO/bin/report-scripts.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_file(){     [ -f "$1" ] && ok "$2" || no "$2 (missing: $1)"; }
assert_no_file(){  [ ! -e "$1" ] && ok "$2" || no "$2 (unexpected: $1)"; }
assert_grep(){     grep -q -- "$2" "$1" 2>/dev/null && ok "$3" || no "$3 (no /$2/ in $1)"; }
assert_nogrep(){   grep -q -- "$2" "$1" 2>/dev/null && no "$3 (/$2/ unexpectedly in $1)" || ok "$3"; }
assert_eq(){       [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }

# One sandbox per case: HOME, AUTODREAM_DIR (where the conf lives) and a findings dir.
new_case(){ # $1=name -> sets C, F, CONF, SCRIPTS
  C="$SUITE_TMP/$1"
  mkdir -p "$C/home" "$C/ad" "$C/f" "$C/scripts"
  F="$C/f"; CONF="$C/ad/report-scripts.conf"; SCRIPTS="$C/scripts"
}
mk_script(){ # $1=path, then the script body on stdin
  cat > "$1"; chmod +x "$1"
}
collect(){ # runs the collector the way run.sh does; sets RC
  HOME="$C/home" AUTODREAM_DIR="$C/ad" AUTODREAM_REPORT_TIMEOUT="${TMO:-60}" \
    bash "$BIN" collect "$F" > "$C/collect.out" 2> "$C/collect.err"
  RC=$?
}
row(){ awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$F/report-index.txt"; }

echo "# no conf: the index says so, nothing runs, exit 0"
new_case noconf
collect
assert_eq "$RC" "0" "no conf exits 0"
assert_file "$F/report-index.txt" "no conf still writes the index (one shape for L2)"
assert_grep "$F/report-index.txt" 'none configured' "index says none configured"
assert_grep "$F/report-index.txt" "$CONF" "index names the conf path so L2 can tell the operator where to add an entry"
assert_eq "$(ls "$F" | grep -c '^report-.*\.md$')" "0" "no conf writes no report file"

echo "# conf with only comments and blanks"
new_case empty
printf '# nothing yet\n\n   \n' > "$CONF"
collect
assert_eq "$RC" "0" "comments-only conf exits 0"
assert_grep "$F/report-index.txt" 'none configured' "comments-only conf reads as none configured"

echo "# a working entry: header carries the command, exit code and a UTC time; body is stdout"
new_case good
mk_script "$SCRIPTS/hello.sh" <<'SH'
#!/bin/bash
echo "row one"
echo "row two: $*"
echo "noise" >&2
SH
printf 'hello %s --since-hours 36\n' "$SCRIPTS/hello.sh" > "$CONF"
collect
assert_eq "$RC" "0" "good entry exits 0"
assert_file "$F/report-hello.md" "report-hello.md written"
head -1 "$F/report-hello.md" > "$C/h1"
assert_grep "$C/h1" '^# report-hello: ' "header names the entry"
assert_grep "$C/h1" "hello.sh --since-hours 36" "header carries the command line"
assert_grep "$C/h1" 'exit 0' "header carries the exit code"
assert_grep "$C/h1" '[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' "header carries a UTC time"
assert_grep "$F/report-hello.md" '^row one$' "stdout is the body"
assert_grep "$F/report-hello.md" '^row two: --since-hours 36$' "args reach the script"
assert_nogrep "$F/report-hello.md" 'noise' "stderr of a clean run stays out of the report"
assert_eq "$(row hello)" "ok" "index row says ok"
assert_grep "$F/report-index.txt" "$F/report-hello.md" "index row carries the exact path L2 will Read"

echo "# non-zero exit: the failure is the content"
new_case fail
mk_script "$SCRIPTS/bad.sh" <<'SH'
#!/bin/bash
echo "partial row"
echo "boom: ledger unreadable" >&2
exit 3
SH
printf 'bad %s\n' "$SCRIPTS/bad.sh" > "$CONF"
collect
assert_eq "$RC" "0" "a failing report script never fails the collector"
assert_file "$F/report-bad.md" "failing entry still writes its file"
assert_grep "$F/report-bad.md" 'exit 3' "file records the exit code"
assert_grep "$F/report-bad.md" 'FAILED' "file says FAILED so L2 cannot read it as an empty success"
assert_grep "$F/report-bad.md" 'boom: ledger unreadable' "failure carries stderr"
assert_grep "$F/report-bad.md" 'partial row' "failure keeps the partial stdout"
assert_eq "$(row bad)" "failed" "index row says failed"

echo "# timeout: killed, file written, the collector returns promptly"
new_case slow
mk_script "$SCRIPTS/slow.sh" <<'SH'
#!/bin/bash
echo "started"
exec sleep 30
SH
printf 'slow %s\n' "$SCRIPTS/slow.sh" > "$CONF"
t0=$SECONDS
TMO=1 collect
elapsed=$((SECONDS - t0))
assert_eq "$RC" "0" "a timed-out entry never fails the collector"
[ "$elapsed" -lt 15 ] && ok "collector returned in ${elapsed}s, not the script's 30" || no "collector waited ${elapsed}s for a hung script"
assert_grep "$F/report-slow.md" 'timed out after 1s' "file says it timed out and for how long"
assert_grep "$F/report-slow.md" 'started' "timeout keeps what was printed before the kill"
assert_eq "$(row slow)" "timeout" "index row says timeout"

echo "# missing and non-executable scripts"
new_case missing
mk_script "$SCRIPTS/noexec.sh" <<'SH'
#!/bin/bash
echo hi
SH
chmod -x "$SCRIPTS/noexec.sh"
printf 'gone %s\nnoexec %s\n' "$SCRIPTS/nope.sh" "$SCRIPTS/noexec.sh" > "$CONF"
collect
assert_eq "$RC" "0" "missing script exits 0"
assert_grep "$F/report-gone.md" 'not found' "missing script: file says not found"
assert_grep "$F/report-gone.md" 'nope.sh' "missing script: file names the path"
assert_eq "$(row gone)" "missing" "missing script: index row says missing"
assert_grep "$F/report-noexec.md" 'not executable' "non-executable script: file says so"
assert_eq "$(row noexec)" "missing" "non-executable script: index row says missing"

echo "# path rules: ~ expands against HOME, anything else must be absolute"
new_case paths
mkdir -p "$C/home/bin"
mk_script "$C/home/bin/tilde.sh" <<'SH'
#!/bin/bash
echo "tilde ran in $(pwd -P)"
SH
printf 'tilde ~/bin/tilde.sh\nrel scripts/rel.sh\n' > "$CONF"
collect
assert_grep "$F/report-tilde.md" 'tilde ran in' "~/ path ran"
assert_grep "$F/report-tilde.md" "tilde ran in $(cd "$C/home" && pwd -P)" "the script runs with cwd HOME"
assert_grep "$F/report-rel.md" 'not an absolute path' "a relative path is refused as content, not run from the wrong cwd"
assert_eq "$(row rel)" "invalid" "relative path: index row says invalid"

echo "# no stdin, and args are literal words (no eval, no glob, no expansion)"
new_case lit
mk_script "$SCRIPTS/lit.sh" <<'SH'
#!/bin/bash
printf 'stdin=[%s]\n' "$(cat)"
for a in "$@"; do printf 'arg=[%s]\n' "$a"; done
SH
printf 'lit %s *.md $(touch %s/pwned) ; touch %s/pwned2\n' "$SCRIPTS/lit.sh" "$C" "$C" > "$CONF"
touch "$C/home/glob-bait.md"
collect
assert_grep "$F/report-lit.md" '^stdin=\[\]$' "stdin is /dev/null"
assert_grep "$F/report-lit.md" '^arg=\[\*\.md\]$' "a glob is not expanded"
assert_grep "$F/report-lit.md" '^arg=\[\$(touch\]$' "a command substitution is not run"
assert_no_file "$C/pwned" "command substitution did not execute"
assert_no_file "$C/pwned2" "a semicolon did not start a second command"

echo "# an entry that reads stdin does not eat the conf: the next entry still runs, and the last line may lack a newline"
new_case stdin
mk_script "$SCRIPTS/reader.sh" <<'SH'
#!/bin/bash
cat > /dev/null
echo "reader done"
SH
mk_script "$SCRIPTS/after.sh" <<'SH'
#!/bin/bash
echo "after ran"
SH
printf 'reader %s\nafter %s' "$SCRIPTS/reader.sh" "$SCRIPTS/after.sh" > "$CONF"
collect
assert_grep "$F/report-reader.md" 'reader done' "first entry ran"
assert_grep "$F/report-after.md" 'after ran' "second entry ran after a stdin reader, last line without newline"

echo "# bad and duplicate names are refused, never written outside the findings dir"
new_case names
mk_script "$SCRIPTS/n.sh" <<'SH'
#!/bin/bash
echo first
SH
mk_script "$SCRIPTS/n2.sh" <<'SH'
#!/bin/bash
echo second
SH
printf 'dup %s\n../escape %s\nsp/ace %s\ndup %s\n' "$SCRIPTS/n.sh" "$SCRIPTS/n.sh" "$SCRIPTS/n.sh" "$SCRIPTS/n2.sh" > "$CONF"
collect
assert_eq "$RC" "0" "bad names exit 0"
assert_no_file "$C/escape.md" "a ../ name did not write outside the findings dir"
assert_no_file "$F/report-../escape.md" "a ../ name wrote nothing under the findings dir"
assert_grep "$F/report-dup.md" '^first$' "the first entry of a duplicated name keeps its file"
assert_nogrep "$F/report-dup.md" '^second$' "the duplicate never overwrites it"
assert_grep "$F/report-index.txt" 'invalid' "index flags the refused lines"
assert_grep "$F/report-index.txt" 'duplicate' "index says which was a duplicate"

echo "# a rerun drops the report of an entry that left the conf"
new_case stale
mk_script "$SCRIPTS/a.sh" <<'SH'
#!/bin/bash
echo a
SH
mk_script "$SCRIPTS/b.sh" <<'SH'
#!/bin/bash
echo b
SH
printf 'a %s\nb %s\n' "$SCRIPTS/a.sh" "$SCRIPTS/b.sh" > "$CONF"
collect
assert_file "$F/report-b.md" "first run wrote b"
printf 'a %s\n' "$SCRIPTS/a.sh" > "$CONF"
collect
assert_no_file "$F/report-b.md" "a removed entry's old report is gone, L2 cannot read a stale answer"
assert_file "$F/report-a.md" "the remaining entry is refreshed"

echo "# output is capped"
new_case big
mk_script "$SCRIPTS/big.sh" <<'SH'
#!/bin/bash
head -c 300000 /dev/zero | tr '\0' 'x'
echo
SH
printf 'big %s\n' "$SCRIPTS/big.sh" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" AUTODREAM_REPORT_MAX_BYTES=1000 bash "$BIN" collect "$F" > /dev/null 2>&1
sz=$(wc -c < "$F/report-big.md")
[ "$sz" -lt 2500 ] && ok "a 300 KB report is cut to the cap (file is $sz bytes)" || no "report not capped ($sz bytes)"
assert_grep "$F/report-big.md" 'truncated' "the cut says so"

echo "# an unwritable findings dir is a loud failure, not a silent one"
new_case nofind
rc=0
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" collect "$C/does/not/exist" > /dev/null 2> "$C/err" || rc=$?
[ "$rc" -ne 0 ] && ok "missing findings dir exits non-zero" || no "missing findings dir exited 0"

echo "# names that differ only by case are one name (they are one file on APFS)"
new_case casedup
mk_script "$SCRIPTS/c1.sh" <<'SH'
#!/bin/bash
echo first
SH
mk_script "$SCRIPTS/c2.sh" <<'SH'
#!/bin/bash
echo second
SH
printf 'Foo %s\nfoo %s\n' "$SCRIPTS/c1.sh" "$SCRIPTS/c2.sh" > "$CONF"
collect
assert_grep "$F/report-Foo.md" '^first$' "the first spelling keeps its file"
assert_eq "$(row foo)" "invalid" "the second spelling is refused"
assert_nogrep "$F/report-Foo.md" '^second$' "and never overwrites the first"

echo "# the allowlist is a snapshot: a worker that rewrites the conf or a script after it cannot make the collector run anything new"
snap_case(){ # $1=name; the conf lists one good script; takes the snapshot, as run.sh does before any model runs
  new_case "$1"
  mk_script "$SCRIPTS/good.sh" <<'SH'
#!/bin/bash
echo "good ran"
SH
  printf 'good %s\n' "$SCRIPTS/good.sh" > "$CONF"
  HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> "$C/snap.err"
}
snap_collect(){
  HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" collect "$F" "$C/snap" > "$C/collect.out" 2> "$C/collect.err"
  RC=$?
}
snap_case tamper_conf
printf 'good %s\nevil %s\n' "$SCRIPTS/good.sh" "$SCRIPTS/evil.sh" > "$CONF"
mk_script "$SCRIPTS/evil.sh" <<SH
#!/bin/bash
touch "$C/evil-ran"
SH
snap_collect
assert_eq "$RC" "0" "collect with a snapshot exits 0"
assert_grep "$F/report-good.md" 'good ran' "the snapshotted entry runs"
assert_no_file "$F/report-evil.md" "an entry added to the conf after the snapshot gets no file"
assert_no_file "$C/evil-ran" "and is never executed"
assert_nogrep "$F/report-index.txt" 'evil' "and is not in the index"

snap_case tamper_script
printf '#!/bin/bash\ntouch "%s/evil-ran"\necho "good ran"\n' "$C" > "$SCRIPTS/good.sh"
snap_collect
assert_no_file "$C/evil-ran" "a script rewritten after the snapshot is not executed"
assert_grep "$F/report-good.md" 'changed since this run started' "its file says why"
assert_eq "$(row good)" "changed" "index row says changed"

snap_case tamper_new_script
printf 'later %s\n' "$SCRIPTS/later.sh" >> "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
mk_script "$SCRIPTS/later.sh" <<SH
#!/bin/bash
touch "$C/later-ran"
SH
snap_collect
assert_no_file "$C/later-ran" "a script that did not exist at the snapshot is not run when it appears"
assert_eq "$(row later)" "changed" "index row says changed"

snap_case tamper_absent
rm -f "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
printf 'good %s\n' "$SCRIPTS/good.sh" > "$CONF"
snap_collect
assert_no_file "$F/report-good.md" "a conf created after an absent snapshot is not read"
assert_grep "$F/report-index.txt" 'none configured' "the index says none configured"

snap_case snapshot_content
assert_grep "$C/snap" '^#present$' "the snapshot says the conf was present"
assert_grep "$C/snap" "^[0-9a-f]\{64\}	good $SCRIPTS/good.sh" "each entry carries the sha256 of its script"

snap_case unavailable
printf '#unavailable\n' > "$C/snap"
snap_collect
assert_no_file "$F/report-good.md" "an unavailable snapshot runs nothing, even with a good conf on disk"
assert_grep "$F/report-index.txt" 'unavailable' "and the index says the allowlist was unavailable, not that none is configured"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
