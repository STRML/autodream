#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n' "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }
assert_grep() { grep -qF -- "$2" "$1" 2>/dev/null && ok "$3" || no "$3 (no [$2] in $1)"; }
assert_no_file() { [ ! -e "$1" ] && ok "$2" || no "$2 (unexpected: $1)"; }
remove_path() { python3 -c 'import os,shutil,sys; p=sys.argv[1]; shutil.rmtree(p) if os.path.isdir(p) and not os.path.islink(p) else os.path.lexists(p) and os.remove(p)' "$1"; }

SANDBOX=""
cleanup() { [ -n "$SANDBOX" ] && remove_path "$SANDBOX"; }
trap cleanup EXIT

new_sandbox() {
  [ -n "$SANDBOX" ] && remove_path "$SANDBOX"
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/ccad-wa.XXXXXX")
  HOME_TEST="$SANDBOX/home"
  LA="$HOME_TEST/Library/LaunchAgents"
  mkdir -p "$LA" "$SANDBOX/shim" "$SANDBOX/bin"
  CALLS="$SANDBOX/launchctl-calls"
  : > "$CALLS"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$SANDBOX/shim/launchctl"
  for name in cmux claude; do printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/bin/$name"; done
  chmod +x "$SANDBOX/shim/launchctl" "$SANDBOX/bin/cmux" "$SANDBOX/bin/claude"
}
run_install() {
  env HOME="$HOME_TEST" PATH="$SANDBOX/shim:$SANDBOX/bin:/usr/bin:/bin" \
    AUTODREAM_CMUX_DEFAULT="$SANDBOX/no-cmux" AUTODREAM_EPHEMERAL_DIRS= \
    bash "$REPO/install.sh" "$@" > "$SANDBOX/install.out" 2>&1
}
nightly_label() {
  for p in "$LA"/*.plist; do
    case "$p" in *-review.plist|*-web.plist) ;; *) basename "$p" .plist; return ;; esac
  done
}

echo "# a normal install provisions the web LaunchAgent beside review"
new_sandbox
run_install "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the install succeeds"
NIGHTLY=$(nightly_label)
WEB="$LA/$NIGHTLY-web.plist"
[ -f "$WEB" ] && ok "the web plist exists" || no "the web plist exists"
if [ -f "$WEB" ]; then
  assert_grep "$WEB" "<string>$NIGHTLY-web</string>" "the web label is owned by this nightly label"
  assert_grep "$WEB" "<key>RunAtLoad</key><true/>" "the web agent starts at login"
  assert_grep "$WEB" "<key>ThrottleInterval</key><integer>60</integer>" "restarts are throttled"
  assert_grep "$WEB" "<key>SuccessfulExit</key><false/>" "only unsuccessful exits restart"
  assert_grep "$WEB" "$SANDBOX/target/autodream/autodream-web.py" "the plist runs the installed server"
  assert_grep "$WEB" "<key>CMUX_BIN</key><string>$SANDBOX/bin/cmux</string>" "cmux is pinned"
  assert_grep "$WEB" "<key>CLAUDE_BIN</key><string>$SANDBOX/bin/claude</string>" "claude is pinned"
fi

echo "# --no-web and AUTODREAM_WEB=0 remove only the web agent"
new_sandbox
run_install "$SANDBOX/target"; NIGHTLY=$(nightly_label)
run_install --no-web "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "--no-web succeeds"
assert_no_file "$LA/$NIGHTLY-web.plist" "--no-web removes its plist"
assert_grep "$CALLS" "bootout gui/$(id -u)/$NIGHTLY-web" "--no-web unloads its label"

new_sandbox
mkdir -p "$SANDBOX/target/autodream"
printf 'AUTODREAM_WEB=0\n' > "$SANDBOX/target/autodream/config"
run_install "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the config opt-out succeeds"
assert_no_file "$LA/$(nightly_label)-web.plist" "AUTODREAM_WEB=0 leaves no plist"

echo "# --no-web leaves the web agent enabled when review is disabled"
new_sandbox
run_install --no-review "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the review opt-out install succeeds"
[ -f "$LA/$(nightly_label)-web.plist" ] && ok "review opt-out keeps the web plist" || no "review opt-out keeps the web plist"
[ -f "$LA/$(nightly_label)-review.plist" ] && no "review opt-out leaves no review plist" || ok "review opt-out leaves no review plist"

printf '\npassed: %s   failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
