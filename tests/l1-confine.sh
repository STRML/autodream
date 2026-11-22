#!/bin/bash
# Unit tests for bin/l1-confine.sh: the OS sandbox an L1 worker runs under (#169).
#
# The failure matrix, one row per case below:
#
#   state                                   probe says                         prefix / stage
#   no sandbox tool on PATH                 no, names what is missing          prefix fails
#   tool rejects the profile at startup     no, quotes the tool's complaint    -
#   tool starts but confines nothing        no, "did not refuse a write"       -
#   tool works                              yes, tool name                     argv writes only the stage
#   writable path with a quote or newline   -                                  refused, no profile
#   a protected path under a writable one   -                                  denied after the allow
#
# The real-confinement cases run only where a sandbox works (the probe says yes). Inside another
# sandbox, sandbox-exec cannot start, so there they print a skip line and the shim cases still run.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp l1conf

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_eq(){ [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }
has(){ case "$1" in *"$2"*) ok "$3" ;; *) no "$3 (missing [$2] in [$1])" ;; esac; }
lacks(){ case "$1" in *"$2"*) no "$3 (found [$2] in [$1])" ;; *) ok "$3" ;; esac; }

H="$REPO/bin/l1-confine.sh"
if [ ! -r "$H" ]; then
  printf '  FAIL - %s is missing; the rest of this suite would be vacuous\n' "$H"
  printf '\npassed: 0   failed: 1\n'
  exit 1
fi

D="$SUITE_TMP/c"; mkdir -p "$D/shim" "$D/bare"
# A PATH holding only what the helper itself needs, so no real sandbox tool is on it.
for t in sh bash mkdir rm cat dirname basename mktemp tr head sed printf env; do
  p=$(command -v "$t" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "$D/bare/$t"
done
# probe's reason is one line; the tab separates the verdict from it.
probe_with() { env PATH="$1" TMPDIR="$D" bash "$H" probe; }
verdict() { printf '%s' "$1" | cut -f1; }
reason() { printf '%s' "$1" | cut -f2-; }

echo "# probe: no sandbox tool"
out=$(probe_with "$D/bare")
assert_eq "$(verdict "$out")" "no" "a host with neither sandbox-exec nor bwrap is not confined"
has "$(reason "$out")" "sandbox-exec or bwrap" "and the reason names what is missing"

echo "# probe: a tool that rejects the profile"
printf '#!/bin/sh\necho "sandbox-exec: profile rejected: syntax error" >&2\nexit 65\n' > "$D/shim/sandbox-exec"; chmod +x "$D/shim/sandbox-exec"
out=$(probe_with "$D/shim:$D/bare")
assert_eq "$(verdict "$out")" "no" "a profile the tool refuses at startup is not confined"
has "$(reason "$out")" "rejected" "and the reason quotes the tool"

echo "# probe: a tool that starts and confines nothing"
# Skips the -p profile argument and runs the command as is: the probe must not trust exit 0.
printf '#!/bin/sh\nshift 2\nexec "$@"\n' > "$D/shim/sandbox-exec"; chmod +x "$D/shim/sandbox-exec"
out=$(probe_with "$D/shim:$D/bare")
assert_eq "$(verdict "$out")" "no" "a tool that accepts the profile and refuses nothing is not confined"
has "$(reason "$out")" "did not refuse a write outside" "and the reason says so"

echo "# prefix: the profile text"
printf '#!/bin/sh\nexit 0\n' > "$D/shim/sandbox-exec"
S="$D/stage"; mkdir -p "$S" "$D/state/dir"
prefix_text() { env PATH="$D/shim:$D/bare" "$@" | tr '\0' '\n'; }
PS=$(cd "$S" && pwd -P)
txt=$(prefix_text bash "$H" prefix "$S" "$D/state/dir" "$D/state/file.json*")
has "$txt" "-p" "sandbox-exec gets an inline profile"
has "$txt" "(deny file-write*)" "writes are denied by default"
has "$txt" "(allow file-write* (subpath \"$PS\"))" "the staging directory is writable"
has "$txt" "(subpath \"$(cd "$D/state/dir" && pwd -P)\")" "a state directory is a subpath rule"
has "$txt" "(regex #\"^$(cd "$D/state" && pwd -P | sed 's/[][\.^$*+?(){}|]/\\&/g')/file\\.json\")" "a path ending in * is a prefix rule"
# The protect list is denied AFTER the writable paths and BEFORE the stage allow, so it wins over a
# state directory that happens to contain it but the stage (inside it) stays writable.
txt=$(prefix_text env L1_CONFINE_PROTECT="$D/state/dir/inner" bash "$H" prefix "$S" "$D/state/dir")
allow_line=$(printf '%s\n' "$txt" | grep -n "subpath \"$(cd "$D/state/dir" && pwd -P)\"" | head -1 | cut -d: -f1)
deny_line=$(printf '%s\n' "$txt" | grep -n "(deny file-write\* (subpath" | head -1 | cut -d: -f1)
stage_line=$(printf '%s\n' "$txt" | grep -n "subpath \"$PS\"" | tail -1 | cut -d: -f1)
[ -n "$allow_line" ] && [ -n "$deny_line" ] && [ -n "$stage_line" ] && [ "$allow_line" -lt "$deny_line" ] && [ "$deny_line" -lt "$stage_line" ] \
  && ok "a protected path is denied after the writable rules and before the stage allow" || no "rule order allow=$allow_line deny=$deny_line stage=$stage_line"
env PATH="$D/shim:$D/bare" bash "$H" prefix "$S" "$D/state/\"quoted" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a writable path that could close the profile string is refused"
env PATH="$D/shim:$D/bare" bash "$H" prefix "$S" "$D/state/$(printf 'a\nb')" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "so is one with a newline"
env PATH="$D/bare" bash "$H" prefix "$S" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "prefix with no sandbox tool fails"

echo "# prefix: paths are resolved as the kernel sees them, and checked again after"
mkdir -p "$D/realdir"; : > "$D/realdir/onefile"; ln -s "$D/realdir" "$D/linkdir"
txt=$(prefix_text bash "$H" prefix "$S" "$D/linkdir/onefile")
has "$txt" "(subpath \"$(cd "$D/realdir" && pwd -P)/onefile\")" "an existing regular file under a symlinked parent resolves through the parent"
mkdir -p "$D/q\"uote"; ln -s "$D/q\"uote" "$D/quotelink"
env PATH="$D/shim:$D/bare" bash "$H" prefix "$S" "$D/quotelink" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a symlink whose target holds a quote is refused, not written into the profile"
env PATH="$D/shim:$D/bare" L1_CONFINE_PROTECT="$D/quotelink" bash "$H" prefix "$S" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "and so is a protected path that resolves to one"

echo "# prefix: bwrap"
printf '#!/bin/sh\nexit 0\n' > "$D/shim/bwrap"; chmod +x "$D/shim/bwrap" "$D/shim/sandbox-exec"
txt=$(prefix_text env L1_CONFINE_TOOL=bwrap bash "$H" prefix "$S" "$D/state/dir" "$D/state/nonexistent" "$D/state/file.json*")
has "$txt" "--ro-bind" "the whole filesystem is bound read-only"
has "$txt" "--die-with-parent" "and the sandbox dies with the runner"
has "$txt" "--bind" "paths are bound writable"
has "$txt" "$PS" "the staging directory is one of them"
has "$txt" "$D/state/dir" "an existing state directory is another"
lacks "$txt" "nonexistent" "a state path that does not exist is skipped"
lacks "$txt" "file.json" "a prefix rule has no bwrap equivalent and is skipped"
assert_eq "$(printf '%s\n' "$txt" | tail -1)" "--" "the engine command follows a --"
mkdir -p "$D/state/dir/inner"; : > "$D/state/pre.json"
txt=$(prefix_text env L1_CONFINE_TOOL=bwrap L1_CONFINE_PROTECT="$D/state/dir/inner" bash "$H" prefix "$S" "$D/state/dir" "$D/state/pre.json*")
has "$txt" "--ro-bind
$D/state/dir/inner" "a protected path is re-bound read-only"
has "$txt" "$D/state/pre.json" "a prefix rule binds a file that already matches it"
bind_line=$(printf '%s\n' "$txt" | grep -n "^$D/state/dir\$" | head -1 | cut -d: -f1)
ro_line=$(printf '%s\n' "$txt" | grep -n "^$D/state/dir/inner\$" | head -1 | cut -d: -f1)
stage_line=$(printf '%s\n' "$txt" | grep -n "^$PS\$" | tail -1 | cut -d: -f1)
[ -n "$bind_line" ] && [ -n "$ro_line" ] && [ -n "$stage_line" ] && [ "$bind_line" -lt "$ro_line" ] && [ "$ro_line" -lt "$stage_line" ] \
  && ok "the read-only bind comes after the state path and before the stage" || no "bwrap order bind=$bind_line ro=$ro_line stage=$stage_line"
mkdir -p "$D/lk"; : > "$D/lk/a.json"; ln -s "$D/realdir" "$D/lk/a.json.lock"
txt=$(prefix_text env L1_CONFINE_TOOL=bwrap bash "$H" prefix "$S" "$D/lk/a.json*")
has "$txt" "$D/lk/a.json" "a prefix rule binds the regular file that matches it"
lacks "$txt" "a.json.lock" "and skips a match that is a symlink: it would grant its target"
printf '%s\n' "$(env PATH="$D/bare" L1_CONFINE_TOOL=none bash "$H" prefix "$S" 2>&1; echo "rc=$?")" | tail -1 | grep -q 'rc=1' && ok "an unknown L1_CONFINE_TOOL is refused" || no "an unknown L1_CONFINE_TOOL is refused"

echo "# engine-prefix: one definition of an engine's prefix, built from the adapter's own write list"
FA="$D/fake-adapter.sh"; WR="$D/writes.txt"
printf '#!/bin/sh\n[ "$1" = l1-writes ] || exit 2\ncat "%s"\n' "$WR" > "$FA"; chmod +x "$FA"
NA="$D/no-profile-adapter.sh"; printf '#!/bin/sh\nexit 2\n' > "$NA"; chmod +x "$NA"
ep() { env PATH="$D/shim:$D/bare" "$@"; }
mkdir -p "$D/state/dir"; printf '%s\n' "$D/state/dir" > "$WR"
txt=$(ep bash "$H" engine-prefix "$FA" "$S" | tr '\0' '\n')
has "$txt" "(subpath \"$(cd "$D/state/dir" && pwd -P)\")" "the adapter's write list is in the profile"
has "$txt" "(allow file-write* (subpath \"$PS\"))" "beside the staging directory"
ep bash "$H" engine-prefix "$NA" "$S" >/dev/null 2>"$D/err"; rc=$?
assert_eq "$rc" "1" "an adapter with no write profile gives no prefix"
has "$(cat "$D/err")" "no write profile" "and says why"
printf 'relative/dir\n' > "$WR"
ep bash "$H" engine-prefix "$FA" "$S" >/dev/null 2>"$D/err"; rc=$?
assert_eq "$rc" "1" "a relative path in the write list is refused"
has "$(cat "$D/err")" "relative/dir" "and named"
has "$(cat "$D/err")" "absolute" "with the reason"
printf '%s\n' "$D/state/\"quoted" > "$WR"
ep bash "$H" engine-prefix "$FA" "$S" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a quote in a write-list path is refused"
ln -s "$D/realdir" "$D/leaflink"; printf '%s\n' "$D/leaflink" > "$WR"
ep bash "$H" engine-prefix "$FA" "$S" >/dev/null 2>"$D/err"; rc=$?
assert_eq "$rc" "1" "a writable path whose last component is a symlink is refused: it would grant its target"
has "$(cat "$D/err")" "symlink" "and the reason says so"
ep bash "$H" prefix "$S" "$D/leaflink" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "the same through the prefix verb"
ep L1_CONFINE_TOOL=bwrap bash "$H" prefix "$S" "$D/leaflink" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "and under bwrap"
printf '%s\n' "$D/state/dir" > "$WR"
FB="$D/failing-adapter.sh"; printf '#!/bin/sh\necho "refused: a path holds a newline" >&2\nexit 3\n' > "$FB"; chmod +x "$FB"
ep bash "$H" engine-prefix "$FB" "$S" >/dev/null 2>"$D/err"; rc=$?
assert_eq "$rc" "1" "an adapter whose l1-writes fails gives no prefix"
has "$(cat "$D/err")" "exit 3" "with its exit status"
has "$(cat "$D/err")" "refused: a path holds a newline" "and its own words"
mkdir -p "$D/with space"; printf '%s\n' "$D/with space" "$D/state/dir" > "$WR"
txt=$(ep bash "$H" engine-prefix "$FA" "$S" | tr '\0' '\n')
has "$txt" "(subpath \"$(cd "$D/with space" && pwd -P)\")" "a path with a space is one path"
has "$txt" "(subpath \"$(cd "$D/state/dir" && pwd -P)\")" "and the line after it is the next"
printf '%s\n' "$D/state/dir" > "$WR"
ln -s "$S" "$D/stagelink"
ep bash "$H" engine-prefix "$FA" "$D/stagelink" >/dev/null 2>"$D/err"; rc=$?
assert_eq "$rc" "1" "a staging directory that is a symlink is refused"
has "$(cat "$D/err")" "symlink" "and the reason says so"
mkdir -p "$D/stageroot/h.a"
ep L1_STAGE_ROOT="$D/stageroot" bash "$H" engine-prefix "$FA" "$D/stageroot/h.a" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "a stage under the staging root is accepted"
ep L1_STAGE_ROOT="$D/stageroot" bash "$H" engine-prefix "$FA" "$S" >/dev/null 2>"$D/err"; rc=$?
assert_eq "$rc" "1" "a stage that does not resolve under the staging root is refused"
has "$(cat "$D/err")" "staging root" "and named"
for tool in sandbox-exec bwrap; do
  ep L1_CONFINE_TOOL=$tool L1_CONFINE_PROTECT="relative/protected" bash "$H" prefix "$S" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" "1" "[$tool] a relative protected path is refused"
  mkdir -p "$D/globs/a1" "$D/globs/b2"
  ep L1_CONFINE_TOOL=$tool L1_CONFINE_PROTECT="$D/globs/*" bash "$H" prefix "$S" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" "1" "[$tool] a glob in a protected path is refused, not expanded to what exists"
done

echo "# the manual real-call check reads the nightly's configuration, and the caller's environment wins as in run.sh"
RC="$REPO/tests/l1-confine-real.sh"
mkdir -p "$D/nightly"; printf 'export AUTODREAM_L1_WRITES_EXTRA=/config-only\n' > "$D/nightly/config"
out=$(env -u AUTODREAM_L1_WRITES_EXTRA AUTODREAM_DIR="$D/nightly" HOME="$D/home" bash "$RC" --writes 2>&1)
has "$out" "/config-only" "an AUTODREAM_L1_WRITES_EXTRA set only in the config reaches the adapter"
out=$(AUTODREAM_L1_WRITES_EXTRA=/caller-override AUTODREAM_DIR="$D/nightly" HOME="$D/home" bash "$RC" --writes 2>&1)
has "$out" "/caller-override" "one the caller exported wins over the config"
lacks "$out" "/config-only" "and the config's value is not used beside it"

echo "# real confinement (only where a sandbox works here)"
real=$(env TMPDIR="$D" bash "$H" probe)
if [ "$(verdict "$real")" != "yes" ]; then
  printf '  skip - no working sandbox on this host (%s)\n' "$(reason "$real")"
else
  W="$D/real"; mkdir -p "$W/outside" "$W/state/allowed" "$W/state/allowed/protected"
  mkdir -p "$W/staging/x/tmp"; stage=$(cd "$W/staging/x" && pwd -P)
  run_confined() { # $1..: shell body, run under the prefix with the state dir writable
    local argv=() a
    while IFS= read -r -d '' a; do argv+=("$a"); done < <(L1_CONFINE_PROTECT="$W/state/allowed/protected" bash "$H" prefix "$stage" "$W/state/allowed" "$W/state/ptr*")
    "${argv[@]}" /bin/sh -c "$1" _ "$stage" "$W/outside" "$W/state" >/dev/null 2>&1
  }
  run_confined 'printf a > "$1/answer.json"'; rc=$?
  assert_eq "$rc" "0" "the engine can write its answer in the staging directory"
  assert_eq "$(cat "$stage/answer.json" 2>/dev/null)" "a" "and it is there"
  printf 'original' > "$W/outside/findings.json"
  run_confined 'printf forged > "$2/findings.json"; printf forged > "$2/other.json"'
  assert_eq "$(cat "$W/outside/findings.json")" "original" "a write over a file outside the stage is refused, the file unchanged"
  [ ! -e "$W/outside/other.json" ] && ok "and a new file outside the stage is not created" || no "a new file outside the stage was created"
  run_confined 'printf state > "$3/allowed/session-env"'
  assert_eq "$(cat "$W/state/allowed/session-env" 2>/dev/null)" "state" "a listed state directory is writable"
  run_confined 'printf x > "$3/allowed/protected/config"'
  [ ! -e "$W/state/allowed/protected/config" ] && ok "a protected path inside it is not" || no "a protected path inside a state directory was written"
  printf old > "$W/state/ptr-1.tmp"
  run_confined 'printf x > "$3/ptr-1.tmp"'
  assert_eq "$(cat "$W/state/ptr-1.tmp" 2>/dev/null)" "x" "a prefix rule covers a file that already matches it"
  if [ "$(verdict "$real")" = yes ] && [ "$(reason "$real")" = sandbox-exec ]; then
    run_confined 'printf x > "$3/ptr-2.tmp"'
    assert_eq "$(cat "$W/state/ptr-2.tmp" 2>/dev/null)" "x" "and, under sandbox-exec, a temp file made beside it later"
  fi
  run_confined 'printf y > "$3/elsewhere"'
  [ ! -e "$W/state/elsewhere" ] && ok "and nothing else beside it" || no "a file outside the prefix was written"
  run_confined 'mkdir "$2/newdir"'
  [ ! -d "$W/outside/newdir" ] && ok "a directory cannot be made outside the stage" || no "a directory was made outside the stage"
  run_confined 'rm -f "$2/findings.json"'
  [ -f "$W/outside/findings.json" ] && ok "and a file outside it cannot be deleted" || no "a file outside the stage was deleted"
fi

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
