#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SUT="$REPO/bin/scheduler-label.sh"

PASS=0
FAIL=0
SANDBOX=""

cleanup() { [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

assert_eq() {
  local want="$1" got="$2" what="$3"
  if [ "$want" = "$got" ]; then ok "$what"; else nope "$what" "want [$want] got [$got]"; fi
}

USER_SLUG="$(id -un | tr -dc 'a-zA-Z0-9')"
DEFAULT="com.$USER_SLUG.autodream"

make_plist() {
  local label="$1" runner_dir="$2" file="$LA/$1.plist"
  cat > "$file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$runner_dir/run.sh</string>
    </array>
</dict>
</plist>
PLIST
  printf '%s\n' "$file"
}

make_review_plist() {
  local label="$1" runner_dir="$2"
  cat > "$LA/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>exec "\$1" "\$(date -v-1d +%Y-%m-%d)"</string>
        <string>triage</string>
        <string>$runner_dir/review.sh</string>
    </array>
</dict>
</plist>
PLIST
}

reset_sandbox() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/scheduler-label.XXXXXX")"
  LA="$SANDBOX/LaunchAgents"
  OMP="$SANDBOX/omp/autodream"
  CC="$SANDBOX/claude/autodream"
  mkdir -p "$LA" "$OMP" "$CC"
  export LAUNCH_AGENTS_DIR="$LA"
}

run_sut() { # run_sut <target> -> sets SUT_OUT / SUT_RC
  SUT_OUT="$(bash "$SUT" "$1" 2>"$SANDBOX/err")"
  SUT_RC=$?
  SUT_ERR="$(cat "$SANDBOX/err")"
}

MODES_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/scheduler-label-modes.XXXXXX")"
find "$REPO/bin" -name '*.sh' -exec stat -f '%p %N' {} \; > "$MODES_SNAPSHOT" 2>/dev/null
stat -f '%p %N' "$REPO/install.sh" >> "$MODES_SNAPSHOT" 2>/dev/null
restore_modes() {
  [ -s "$MODES_SNAPSHOT" ] || return 0
  while read -r mode path; do
    [ -e "$path" ] && chmod "${mode: -4}" "$path" 2>/dev/null
  done < "$MODES_SNAPSHOT"
  unlink "$MODES_SNAPSHOT" 2>/dev/null
}
trap 'cleanup; restore_modes' EXIT

printf 'scheduler-label\n'

reset_sandbox
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "empty LaunchAgents dir yields the default label"
assert_eq "0" "$SUT_RC" "empty LaunchAgents dir exits 0"

reset_sandbox
export LAUNCH_AGENTS_DIR="$SANDBOX/nope"
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "a missing LaunchAgents dir yields the default, not a literal glob"
assert_eq "0" "$SUT_RC" "a missing LaunchAgents dir exits 0"
export LAUNCH_AGENTS_DIR="$LA"

reset_sandbox
make_plist "com.$USER_SLUG.omp-autodream" "$CC" >/dev/null
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "a plist running another install's run.sh is not adopted"
assert_eq "0" "$SUT_RC" "a foreign label under a different name is not a conflict"

if grep -q "$CC/run.sh" "$LA/com.$USER_SLUG.omp-autodream.plist"; then
  ok "the foreign plist is left pointing at its own runner"
else
  nope "the foreign plist is left pointing at its own runner" "it was rewritten"
fi

reset_sandbox
make_plist "$DEFAULT" "$OMP" >/dev/null
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "our own plist at the default label is adopted"
assert_eq "0" "$SUT_RC" "adopting our own plist exits 0"

reset_sandbox
make_plist "com.example.autodream-omp" "$OMP" >/dev/null
run_sut "$OMP"
assert_eq "com.example.autodream-omp" "$SUT_OUT" "our own plist under a custom label is adopted"
assert_eq "0" "$SUT_RC" "adopting a custom label exits 0"

reset_sandbox
make_plist "$DEFAULT" "$CC" >/dev/null
run_sut "$OMP"
assert_eq "3" "$SUT_RC" "a foreign install squatting the default label exits 3"
assert_eq "$DEFAULT" "$SUT_OUT" "a conflict still prints a usable label for namespace-only callers"
case "$SUT_ERR" in
  *"$LA/$DEFAULT.plist"*) ok "the conflict message names the offending plist" ;;
  *) nope "the conflict message names the offending plist" "stderr was [$SUT_ERR]" ;;
esac

reset_sandbox
make_plist "$DEFAULT.ondemand" "$OMP" >/dev/null
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "the .ondemand sibling is not adopted as the base label"

reset_sandbox
mv "$(make_plist "$DEFAULT" "$CC")" "$LA/backup.ondemand.plist"
run_sut "$OMP"
assert_eq "3" "$SUT_RC" "a foreign default-label job is a conflict whatever its filename"

ondemand_label() { # ondemand_label <install-dir> -> the Label autodream-now would load
  AUTODREAM_DIR="$1" bash "$REPO/bin/autodream-now.sh" 2020-01-01 --dry-run 2>/dev/null \
    | sed -n '/<key>Label<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}'
}
reset_sandbox
omp_label="$(ondemand_label "$OMP")"
cc_label="$(ondemand_label "$CC")"
case "$omp_label" in
  "$DEFAULT.ondemand."????????) ok "the on-demand label carries a per-install suffix" ;;
  *) nope "the on-demand label carries a per-install suffix" "label was [$omp_label]" ;;
esac
[ "$omp_label" != "$cc_label" ] && ok "two installs with no scheduled job get different on-demand labels" \
  || nope "two installs with no scheduled job get different on-demand labels" "both were [$omp_label]"
assert_eq "$omp_label" "$(ondemand_label "$OMP/")" "a trailing slash does not change the on-demand label"
ln -s "$SANDBOX/omp" "$SANDBOX/omp-link"
assert_eq "$omp_label" "$(ondemand_label "$SANDBOX/omp-link/autodream")" "a symlinked install dir does not change the on-demand label"
reset_sandbox
make_plist "$DEFAULT" "$CC" >/dev/null
[ "$(ondemand_label "$OMP")" != "$(ondemand_label "$CC")" ] && ok "a foreign default-label holder does not share this install's on-demand label" \
  || nope "a foreign default-label holder does not share this install's on-demand label" "labels matched"

reset_sandbox
make_review_plist "com.$USER_SLUG.autodream-review" "$CC"
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "a plist running review.sh is not adopted"

reset_sandbox
printf 'this is not a plist\n' > "$LA/com.broken.autodream.plist"
make_plist "$DEFAULT" "$OMP" >/dev/null
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "a malformed plist is skipped rather than fatal"
assert_eq "0" "$SUT_RC" "a malformed plist does not change the exit status"

reset_sandbox
make_plist "$DEFAULT" "$OMP" >/dev/null
run_sut "$OMP/"
assert_eq "$DEFAULT" "$SUT_OUT" "a trailing slash on the target still matches our own plist"

reset_sandbox
make_plist "$DEFAULT" "$OMP" >/dev/null
ln -s "$SANDBOX/omp" "$SANDBOX/omp-link"
run_sut "$SANDBOX/omp-link/autodream"
assert_eq "$DEFAULT" "$SUT_OUT" "a symlinked target still matches our own plist"

reset_sandbox
make_plist "com.$USER_SLUG.autodream" "$CC" >/dev/null
make_plist "$DEFAULT" "$OMP" >/dev/null
run_sut "$OMP"
assert_eq "$DEFAULT" "$SUT_OUT" "with both installs present, ours is adopted"
assert_eq "0" "$SUT_RC" "with both installs present, exit is 0"

reset_sandbox
mv "$(make_plist "$DEFAULT" "$CC")" "$LA/backup.plist"
run_sut "$OMP"
assert_eq "3" "$SUT_RC" "the default label in backup.plist, running another install, is a conflict"
case "$SUT_ERR" in
  *"$LA/backup.plist"*) ok "the conflict names backup.plist" ;;
  *) nope "the conflict names backup.plist" "stderr was [$SUT_ERR]" ;;
esac

reset_sandbox
make_review_plist "$DEFAULT" "$CC"
run_sut "$OMP"
assert_eq "3" "$SUT_RC" "the default label held by a job with no run.sh is a conflict"

reset_sandbox
mv "$(make_plist "com.example.nightly" "$OMP")" "$LA/nightly.plist"
run_sut "$OMP"
assert_eq "com.example.nightly" "$SUT_OUT" "our own job is adopted whatever its file is called"
assert_eq "0" "$SUT_RC" "adopting a renamed file exits 0"


reset_sandbox
unset LAUNCH_AGENTS_DIR
FAKE_HOME="$SANDBOX/home"
FAKE_LA="$FAKE_HOME/Library/LaunchAgents"
mkdir -p "$FAKE_LA" "$SANDBOX/shim"
LA="$FAKE_LA"
cat > "$SANDBOX/shim/launchctl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$*" >> "$LAUNCHCTL_CALLS"
SHIM
chmod +x "$SANDBOX/shim/launchctl"
export LAUNCHCTL_CALLS="$SANDBOX/launchctl-calls"
: > "$LAUNCHCTL_CALLS"

FOREIGN="$FAKE_LA/$DEFAULT.plist"
make_plist "$DEFAULT" "$CC" >/dev/null
BEFORE="$(cat "$FOREIGN")"

HOME="$FAKE_HOME" PATH="$SANDBOX/shim:$PATH" \
  bash "$REPO/install.sh" "$SANDBOX/omp" >"$SANDBOX/install.out" 2>&1
INSTALL_RC=$?

assert_eq "$BEFORE" "$(cat "$FOREIGN")" "install.sh leaves a foreign plist byte-identical"
assert_eq "0" "$INSTALL_RC" "a refused schedule does not fail the whole install"

if grep -q "bootstrap" "$LAUNCHCTL_CALLS" 2>/dev/null; then
  nope "install.sh bootstraps nothing when refused" "launchctl calls: $(cat "$LAUNCHCTL_CALLS")"
else
  ok "install.sh bootstraps nothing when refused"
fi

if grep -qi "already scheduled by" "$SANDBOX/install.out"; then
  ok "install.sh reports why the schedule was skipped"
else
  nope "install.sh reports why the schedule was skipped" "output: $(tail -5 "$SANDBOX/install.out")"
fi

if grep -q 'pmset repeat wake' "$SANDBOX/install.out"; then
  nope "a refused schedule does not advise pmset" "install.out still prints the wake advice"
else
  ok "a refused schedule does not advise pmset"
fi

if [ -L "$SANDBOX/omp/autodream/run.sh" ]; then
  ok "a refused schedule still installs the symlinks"
else
  nope "a refused schedule still installs the symlinks" "run.sh symlink missing"
fi

reset_sandbox
unset LAUNCH_AGENTS_DIR
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/Library/LaunchAgents" "$SANDBOX/shim"
cat > "$SANDBOX/shim/launchctl" <<'SHIM'
#!/bin/bash
case "$1" in
  bootstrap) echo "bootstrap: simulated failure" >&2; exit 5 ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$SANDBOX/shim/launchctl"

HOME="$FAKE_HOME" PATH="$SANDBOX/shim:$PATH" \
  bash "$REPO/install.sh" "$SANDBOX/omp" >"$SANDBOX/fail.out" 2>&1
FAIL_RC=$?

if [ "$FAIL_RC" -ne 0 ]; then
  ok "a failed launchctl bootstrap fails the install (exit $FAIL_RC)"
else
  nope "a failed launchctl bootstrap fails the install" "install.sh exited 0 on a broken schedule"
fi

if grep -qi "Schedule FAILED" "$SANDBOX/fail.out"; then
  ok "a real scheduling failure is reported as a failure, not as 'in place'"
else
  nope "a real scheduling failure is reported as a failure, not as 'in place'" "output: $(tail -5 "$SANDBOX/fail.out")"
fi

reset_sandbox
TEMPLATE="$REPO/launchd/com.user.autodream.plist.example"
if [ -f "$TEMPLATE" ]; then
  sed -n '/<?xml/,$p' "$TEMPLATE" \
    | sed -e "s|/Users/REPLACE_WITH_USERNAME/.claude/autodream|$OMP|g" \
          -e "s|/Users/REPLACE_WITH_USERNAME|$SANDBOX|g" \
          -e "s|<string>com.user.autodream</string>|<string>$DEFAULT</string>|" \
    > "$LA/$DEFAULT.plist"
  if plutil -lint "$LA/$DEFAULT.plist" >/dev/null 2>&1; then
    run_sut "$OMP"
    assert_eq "$DEFAULT" "$SUT_OUT" "a job installed from the shipped template is adopted, not duplicated"
    assert_eq "0" "$SUT_RC" "the shipped template is not read as a foreign conflict"
  else
    nope "the shipped template renders a valid plist" "plutil rejected the filled-in template"
  fi
else
  nope "the shipped template exists" "$TEMPLATE missing"
fi

run_plist() { # run_plist <target> -> sets SUT_OUT / SUT_RC
  SUT_OUT="$(bash "$SUT" --plist "$1" 2>"$SANDBOX/err")"
  SUT_RC=$?
}

reset_sandbox
OWN="$(make_plist "com.$USER_SLUG.custom-autodream" "$OMP")"
run_plist "$OMP"
assert_eq "$OWN" "$SUT_OUT" "--plist prints the scheduled plist this install owns"
assert_eq "0" "$SUT_RC" "--plist exits 0 when it finds one"

reset_sandbox
make_plist "$DEFAULT" "$CC" >/dev/null
run_plist "$OMP"
assert_eq "" "$SUT_OUT" "--plist never returns another install's job, even on the default label"
assert_eq "1" "$SUT_RC" "--plist exits 1 when only another install is scheduled"

reset_sandbox
run_plist "$OMP"
assert_eq "1" "$SUT_RC" "--plist exits 1 when nothing is scheduled"

printf '\npassed: %d   failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
