#!/bin/bash

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp rptst
BIN="$REPO/bin/report-scripts.sh"

pass=0; fail=0
# shellcheck source=/dev/null
. "$HERE/lib-assert.sh"
skipped=0
skip(){ printf '  skip - %s\n' "$1"; skipped=$((skipped + 1)); }
CHILDKILL_SKIP="child-kill: pgrep cannot read the process table here (the sandbox); CI and launchd can"

new_case(){ # $1=name -> sets C, F, CONF, SCRIPTS
  C="$SUITE_TMP/$1"
  mkdir -p "$C/home" "$C/ad" "$C/f" "$C/scripts"
  F="$C/f"; CONF="$C/ad/report-scripts.conf"; SCRIPTS="$C/scripts"
}
mk_script(){ # $1=path, then the script body on stdin
  cat > "$1"; chmod +x "$1"
}
collect(){ # runs the collector the way run.sh does; sets RC
  HOME="$C/home" AUTODREAM_DIR="$C/ad" AUTODREAM_REPORT_TIMEOUT="${TMO:-60}" AUTODREAM_REPORT_KILL_GRACE="${KG:-5}" \
    bash "$BIN" collect "$F" > "$C/collect.out" 2> "$C/collect.err"
  RC=$?
}
row(){ awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$F/report-index.txt"; }
PROCS_SKIP="process table: ps cannot list processes here (the sandbox); CI and launchd can"
procs_probe_usable(){ ps axeww -o pid= > /dev/null 2>&1; }
if ! procs_probe_usable && [ "${CI:-}" != true ]; then
  skip "$PROCS_SKIP: every entry would be failed, so the whole suite is skipped"
  echo "passed: 0   failed: 0   skipped: $skipped"
  exit 0
fi

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

echo "# a command that ignores TERM is KILLed after the grace period"
new_case deaf
mk_script "$SCRIPTS/deaf.sh" <<'SH'
#!/bin/bash
trap '' TERM
while :; do sleep 1; done
SH
printf 'deaf %s\n' "$SCRIPTS/deaf.sh" > "$CONF"
t0=$SECONDS
TMO=1 KG=1 collect
[ $((SECONDS - t0)) -lt 20 ] && ok "collector returned in $((SECONDS - t0))s" || no "a TERM-ignoring command held the collector"
assert_eq "$(row deaf)" "timeout" "and its row says timeout"

echo "# a command that traps TERM and exits 0 still timed out: the status comes from the watchdog, not the exit code"
new_case trapzero
mk_script "$SCRIPTS/polite.sh" <<'SH'
#!/bin/bash
trap 'echo "stopping cleanly"; exit 0' TERM
echo "working"
while :; do /bin/sleep 0.2; done
SH
printf 'polite %s\n' "$SCRIPTS/polite.sh" > "$CONF"
TMO=1 KG=1 collect
assert_eq "$(row polite)" "timeout" "exit 0 after the TERM is a timeout, not ok"
assert_grep "$F/report-polite.md" 'timed out after 1s' "and the report says it timed out"
assert_grep "$F/report-polite.md" 'FAILED' "with FAILED on it so L2 cannot read the partial output as a success"
assert_grep "$F/report-polite.md" 'stopping cleanly' "and keeps what the command printed while stopping"

echo "# a timeout binary on PATH is never used: it reports the command's own status and leaves a wrapper's children"
new_case tbin
mk_script "$SCRIPTS/polite.sh" <<'SH'
#!/bin/bash
trap 'exit 0' TERM
while :; do /bin/sleep 0.2; done
SH
printf 'polite %s\n' "$SCRIPTS/polite.sh" > "$CONF"
TB="$C/tbin"; mkdir -p "$TB"
for t in timeout gtimeout; do printf '#!/bin/bash\necho used >> "%s/called"\nexec /usr/bin/false\n' "$C" > "$TB/$t"; chmod +x "$TB/$t"; done
PATH="$TB:$PATH" TMO=1 KG=1 collect
assert_no_file "$C/called" "neither timeout nor gtimeout was run"
assert_eq "$(row polite)" "timeout" "the row still says timeout"

echo "# a timed-out command's own children do not outlive it"
new_case kids
mk_script "$SCRIPTS/kids.sh" <<SH
#!/bin/bash
sleep 300 &
echo \$! > "$C/kid.pid"
wait
SH
printf 'kids %s\n' "$SCRIPTS/kids.sh" > "$CONF"
if pgrep -P $$ > /dev/null 2>&1 || [ $? -le 1 ]; then
  TMO=1 KG=1 collect
  kid=$(cat "$C/kid.pid" 2>/dev/null); gone=no
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$kid" 2>/dev/null || { gone=yes; break; }; sleep 0.3; done
  [ "$gone" = yes ] && ok "the command's child is gone after the timeout" || { no "the command's child (pid $kid) outlived the timeout"; kill "$kid" 2>/dev/null; }
else skip "$CHILDKILL_SKIP (a timed-out command's own children)"; fi

echo "# a byte cap with a leading zero is a number, not a bad octal"
new_case octal
mk_script "$SCRIPTS/o.sh" <<'SH'
#!/bin/bash
echo octal ok
SH
printf 'o %s\n' "$SCRIPTS/o.sh" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" AUTODREAM_REPORT_MAX_BYTES=08 AUTODREAM_REPORT_TIMEOUT=09 AUTODREAM_REPORT_KILL_GRACE=08 bash "$BIN" collect "$F" > "$C/collect.out" 2> "$C/collect.err"
assert_eq "$?" "0" "MAX_BYTES=08 TIMEOUT=09 KILL_GRACE=08 do not abort the collector"
assert_grep "$F/report-o.md" 'octal ok' "and the report is written"

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

echo "# output is capped, in the report and while the command runs"
new_case big
mk_script "$SCRIPTS/big.sh" <<'SH'
#!/bin/bash
head -c 3000 /dev/zero | tr '\0' 'x'
echo
SH
printf 'big %s\n' "$SCRIPTS/big.sh" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" AUTODREAM_REPORT_MAX_BYTES=1000 bash "$BIN" collect "$F" > /dev/null 2>&1
sz=$(wc -c < "$F/report-big.md")
[ "$sz" -lt 2500 ] && ok "a 3 KB report is cut to the 1000-byte cap (file is $sz bytes)" || no "report not capped ($sz bytes)"
assert_grep "$F/report-big.md" 'truncated' "the cut says so"
new_case flood
mk_script "$SCRIPTS/flood.sh" <<'SH'
#!/bin/bash
head -c 20000000 /dev/zero | tr '\0' 'x'
SH
printf 'flood %s\n' "$SCRIPTS/flood.sh" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" AUTODREAM_REPORT_MAX_BYTES=1000 bash "$BIN" collect "$F" > /dev/null 2>&1
sz=$(wc -c < "$F/report-flood.md")
[ "$sz" -lt 6000 ] && ok "a command that prints 20 MB is stopped long before it fills the disk (report is $sz bytes)" || no "a flooding command was not bounded ($sz bytes)"
assert_eq "$(row flood)" "failed" "and its row says failed"
assert_grep "$F/report-flood.md" 'output exceeded' "and says the output was too large, not just that it exited 153"
assert_nogrep "$F/report-flood.md" 'exited 153' "no bare signal exit code"

echo "# the watchdog does not leave its own sleep behind when the command finishes in time"
new_case orphan
mk_script "$SCRIPTS/quick.sh" <<'SH'
#!/bin/bash
/bin/sleep 0.3
echo quick
SH
printf 'quick %s\n' "$SCRIPTS/quick.sh" > "$CONF"
SPD="$C/spshim"; mkdir -p "$SPD"
printf '#!/bin/bash\necho $$ > "%s/pid"\nexec /bin/sleep "$@"\n' "$SPD" > "$SPD/sleep"; chmod +x "$SPD/sleep"
PATH="$SPD:$PATH" AUTODREAM_REPORT_TIMEOUT_BIN="" TMO=137 KG=5 collect
sleep 0.5
sp_pid=$(cat "$SPD/pid" 2>/dev/null)
if [ -z "$sp_pid" ]; then no "the watchdog's sleep was observed"
elif kill -0 "$sp_pid" 2>/dev/null; then no "the watchdog's sleep outlived the command"; kill "$sp_pid" 2>/dev/null
else ok "no orphaned watchdog sleep after a command that finished in time"; fi

echo "# the watchdog still KILLs a TERM-ignoring descendant after its wrapper dies from the TERM"
new_case gchild
mk_script "$SCRIPTS/wrapper.sh" <<SH
#!/bin/bash
( trap '' TERM; exec sh -c 'echo \$\$ > "\$1"; exec /bin/sleep 300' _ "$C/gchild.pid" ) &
wait
SH
printf 'wrapper %s\n' "$SCRIPTS/wrapper.sh" > "$CONF"
pgrep -P $$ > /dev/null 2>&1; if [ $? -le 1 ]; then
  AUTODREAM_REPORT_TIMEOUT_BIN="" TMO=1 KG=1 collect
  gpid=$(cat "$C/gchild.pid" 2>/dev/null)
  if [ -z "$gpid" ]; then no "the grandchild started"
  elif kill -0 "$gpid" 2>/dev/null; then no "a TERM-ignoring grandchild outlived the timeout and the wrapper"; kill -KILL "$gpid" 2>/dev/null
  else ok "the grandchild was KILLed after the grace period"; fi
else skip "$CHILDKILL_SKIP (a TERM-ignoring grandchild after its wrapper dies)"; fi

echo "# verifier-b's wrapper: it exits 0 on TERM while a TERM-ignoring child keeps running; the row is timeout and the child dies"
new_case gchild0
mk_script "$SCRIPTS/wrap0.sh" <<SH
#!/bin/bash
trap 'exit 0' TERM
( trap '' TERM; exec sh -c 'echo \$\$ > "\$1"; exec /bin/sleep 300' _ "$C/gchild0.pid" ) &
while :; do wait; done
SH
printf 'wrap0 %s\n' "$SCRIPTS/wrap0.sh" > "$CONF"
TMO=2 KG=1 collect
assert_eq "$(row wrap0)" "timeout" "a wrapper that exits 0 on TERM is a timeout, not ok"
if pgrep -P $$ > /dev/null 2>&1 || [ $? -le 1 ]; then
  g0=$(cat "$C/gchild0.pid" 2>/dev/null)
  if [ -z "$g0" ]; then no "the TERM-ignoring child started"
  elif kill -0 "$g0" 2>/dev/null; then no "the TERM-ignoring child outlived the wrapper's exit 0 and the grace period"; kill -KILL "$g0" 2>/dev/null
  else ok "the TERM-ignoring child was KILLed although its wrapper exited 0"; fi
else skip "$CHILDKILL_SKIP (a TERM-ignoring child after a wrapper that exits 0)"; fi

skip_unless_ci(){ if [ "${CI:-}" = true ]; then no "$1"; else skip "$1"; fi; }

echo "# a command that exits while its background child runs on: the child is stopped and the row is failed"
new_case orphan
mk_script "$SCRIPTS/orphan.sh" <<SH
#!/bin/bash
( trap '' TERM; exec sh -c 'echo \$\$ > "\$1"; exec /bin/sleep 300' _ "$C/orphan.pid" ) &
sleep 0.5
exit 0
SH
printf 'orphan %s\n' "$SCRIPTS/orphan.sh" > "$CONF"
if procs_probe_usable; then
  KG=1 collect
  leaked=$(cat "$C/orphan.pid" 2>/dev/null)
  if [ -z "$leaked" ]; then no "the orphan's child started"
  elif kill -0 "$leaked" 2>/dev/null; then no "a background child outlived the command that started it (pid $leaked)"; kill -KILL "$leaked" 2>/dev/null
  else ok "the background child was stopped after its command exited"; fi
  assert_eq "$(row orphan)" "failed" "a command that leaves a process behind is failed, not ok"
  assert_grep "$F/report-orphan.md" 'left a background process running' "the report says what was left behind"
  assert_eq "$RC" "0" "the collector itself still exits 0"
else skip_unless_ci "$PROCS_SKIP (a background child after its command exits)"; fi

echo "# a child that moves itself into its own process group is still found, through the marker in its environment"
new_case pgrp
mk_script "$SCRIPTS/pgrp.sh" <<SH
#!/bin/bash
set -m
sleep 300 &
echo \$! > "$C/pgrp.pid"
set +m
exit 0
SH
printf 'pgrp %s\n' "$SCRIPTS/pgrp.sh" > "$CONF"
if procs_probe_usable; then
  KG=1 collect
  moved=$(cat "$C/pgrp.pid" 2>/dev/null)
  if [ -z "$moved" ]; then no "the regrouped child started"
  elif kill -0 "$moved" 2>/dev/null; then no "a child in its own process group outlived the command (pid $moved)"; kill -KILL "$moved" 2>/dev/null
  else ok "a child in its own process group was stopped"; fi
  assert_eq "$(row pgrp)" "failed" "and the row is failed"
else skip_unless_ci "$PROCS_SKIP (a child in its own process group)"; fi

echo "# a command that exits 0 and leaves nothing behind stays ok"
new_case tidy
mk_script "$SCRIPTS/tidy.sh" <<'SH'
#!/bin/bash
sleep 0.2 &
wait
echo done
SH
printf 'tidy %s\n' "$SCRIPTS/tidy.sh" > "$CONF"
if procs_probe_usable; then
  collect
  assert_eq "$(row tidy)" "ok" "a command that reaps its own children is ok"
else skip_unless_ci "$PROCS_SKIP (a clean command next to the leftover check)"; fi

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

echo "# an interpreter entry pins its payload too: every argument that is an existing file is hashed with the script"
snap_case tamper_payload
mk_script "$SCRIPTS/payload.sh" <<'SH'
#!/bin/bash
echo "payload ran"
SH
printf 'viabash /bin/bash %s\n' "$SCRIPTS/payload.sh" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
snap_collect
assert_grep "$F/report-viabash.md" 'payload ran' "an unchanged payload runs"
printf '#!/bin/bash\ntouch "%s/evil-ran"\necho "payload ran"\n' "$C" > "$SCRIPTS/payload.sh"
snap_collect
assert_no_file "$C/evil-ran" "a payload rewritten after the snapshot is not executed, though the interpreter is unchanged"
assert_eq "$(row viabash)" "changed" "index row says changed"

snap_case tamper_payload_new
printf 'viabash /bin/bash %s\n' "$SCRIPTS/later-payload.sh" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
mk_script "$SCRIPTS/later-payload.sh" <<SH
#!/bin/bash
touch "$C/later-ran"
SH
snap_collect
assert_no_file "$C/later-ran" "a payload that did not exist at the snapshot is not run when it appears"
assert_eq "$(row viabash)" "changed" "index row says changed"

snap_case tamper_absent
rm -f "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
printf 'good %s\n' "$SCRIPTS/good.sh" > "$CONF"
snap_collect
assert_no_file "$F/report-good.md" "a conf created after an absent snapshot is not read"
assert_grep "$F/report-index.txt" 'none configured' "the index says none configured"

snap_case nohash
printf '#present\n-\tgood %s\n' "$SCRIPTS/good.sh" > "$C/snap"
snap_collect
assert_grep "$F/report-good.md" 'could not be hashed' "a script the snapshot could not hash is refused, not waved through as unchanged"
assert_eq "$(row good)" "changed" "row says changed"
assert_nogrep "$F/report-good.md" '^good ran$' "and it did not run"

snap_case hash_fails_twice
mkdir -p "$C/shim"; printf '#!/bin/bash\nexit 1\n' > "$C/shim/shasum"; chmod +x "$C/shim/shasum"
PATH="$C/shim:$PATH" HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
assert_grep "$C/snap" "^-	good " "with shasum failing the snapshot records no hash"
printf '#!/bin/bash\ntouch "%s/ran-unverified"\n' "$C" > "$SCRIPTS/good.sh"
PATH="$C/shim:$PATH" HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" collect "$F" "$C/snap" > /dev/null 2>&1
assert_no_file "$C/ran-unverified" "a hash that fails on both sides is not read as unchanged, so a rewritten script does not run"
assert_eq "$(row good)" "changed" "row says changed"

snap_case snapshot_content
assert_grep "$C/snap" '^#present$' "the snapshot says the conf was present"
assert_grep "$C/snap" "^[0-9a-f]\{64\}	good $SCRIPTS/good.sh" "each entry carries the sha256 of its script"

snap_case unavailable
printf '#unavailable\n' > "$C/snap"
snap_collect
assert_no_file "$F/report-good.md" "an unavailable snapshot runs nothing, even with a good conf on disk"
assert_grep "$F/report-index.txt" 'unavailable' "and the index says the allowlist was unavailable, not that none is configured"

echo "# a write that fails is a write-failed row, not an ok row for a missing or cut-off report"
new_case partial
mk_script "$SCRIPTS/p.sh" <<'SH'
#!/bin/bash
echo hi
SH
long=$(head -c 1200 /dev/zero | tr '\0' 'a')
printf 'p %s %s\n' "$SCRIPTS/p.sh" "$long" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
mkdir "$F/.report-p.tmp"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" collect "$F" "$C/snap" > "$C/collect.out" 2> "$C/collect.err"
assert_eq "$?" "1" "a report that cannot be written makes collect exit 1"
assert_eq "$(row p)" "write-failed" "and its index row says write-failed"

echo "# the same contract through a size limit, only where this host enforces the limit on the header write"
new_case partial_ulimit
mk_script "$SCRIPTS/p.sh" <<'SH'
#!/bin/bash
echo hi
SH
printf 'p %s %s\n' "$SCRIPTS/p.sh" "$long" > "$CONF"
HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" snapshot > "$C/snap" 2> /dev/null
probe="$C/ulimit-probe"
( trap '' XFSZ; ulimit -f 1; printf '%01200d' 0 > "$probe" ) 2> /dev/null
probe_size=$(wc -c < "$probe" 2> /dev/null | tr -d ' ')
if [ "${probe_size:-0}" -ge 1200 ]; then
  skip "ulimit -f 1 did not stop a 1200-byte write here (probe wrote ${probe_size} bytes), so the size-limit variant of write-failed is not asserted"
elif [ "$(uname -s)" != Linux ]; then
  skip "ulimit -f is not enforced on every write path on $(uname -s): a macOS runner stopped the probe and still let the collector's header write through, so the size-limit variant of write-failed runs on Linux only"
else
  ( trap '' XFSZ; ulimit -f 1; HOME="$C/home" AUTODREAM_DIR="$C/ad" bash "$BIN" collect "$F" "$C/snap" > "$C/collect.out" 2> "$C/collect.err" )
  assert_eq "$?" "1" "a report cut off by a size limit makes collect exit 1"
  assert_eq "$(row p)" "write-failed" "and its index row says write-failed"
fi

echo "# a report that cannot be written is a loud failure, not an ok row"
new_case wfail
mk_script "$SCRIPTS/w.sh" <<'SH'
#!/bin/bash
echo hi
SH
printf 'w %s\n' "$SCRIPTS/w.sh" > "$CONF"
mkdir "$F/.report-w.tmp"
collect
assert_eq "$RC" "1" "a report file that cannot be written makes collect exit 1"
assert_eq "$(row w)" "write-failed" "and the index row says so, not ok"
new_case wfail_idx
printf 'w %s\n' "$SCRIPTS/w.sh" > "$CONF"
ln -s "$C/nodir/x" "$F/.report-index.tmp"
collect
assert_eq "$RC" "1" "an index that cannot be written makes collect exit 1"

echo "# a conf that exists and cannot be read is unavailable, not 'none configured'"
new_case unreadable_conf
printf 'w %s\n' "$SCRIPTS/w.sh" > "$CONF"
chmod 000 "$CONF"
collect
chmod 644 "$CONF"
assert_grep "$F/report-index.txt" 'unavailable' "a manual collect over an unreadable conf says the allowlist is unavailable"
assert_nogrep "$F/report-index.txt" 'none configured' "and never reads as none configured"

echo "# an index whose rows cannot be read back is a failed collect, not a short index with exit 0"
new_case rows_unreadable
mk_script "$SCRIPTS/w.sh" <<'SH'
#!/bin/bash
echo hi
SH
printf 'w %s\n' "$SCRIPTS/w.sh" > "$CONF"
mkdir -p "$C/shim"
printf '#!/bin/bash\ncase "$*" in */rows*) exit 1 ;; esac\nexec /bin/cat "$@"\n' > "$C/shim/cat"; chmod +x "$C/shim/cat"
PATH="$C/shim:$PATH" collect
assert_eq "$RC" "1" "a failed copy of the rows into the index makes collect exit 1"

echo
echo "passed: $pass   failed: $fail   skipped: $skipped"
[ "$fail" -eq 0 ]
