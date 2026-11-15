#!/usr/bin/env bash
set -uo pipefail
unset DREAMS_DIR

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
  cat > "$SANDBOX/shim/launchctl" <<SH
#!/bin/sh
printf '%s\\n' "\$*" >> "$CALLS"
if [ "\$1" = print ]; then
  [ -f "$SANDBOX/print-error" ] && exit 1
  [ -f "$SANDBOX/loaded" ] && cat "$SANDBOX/loaded" && exit 0
  exit 113
fi
SH
  for name in cmux claude; do printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/bin/$name"; done
  chmod +x "$SANDBOX/shim/launchctl" "$SANDBOX/bin/cmux" "$SANDBOX/bin/claude"
}
run_install() {
  env -u AUTODREAM_DIR HOME="$HOME_TEST" PATH="$SANDBOX/shim:$SANDBOX/bin:/usr/bin:/bin" \
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

test_foreign_web_agents_are_untouched() {
  local kind option destination before foreign
  for kind in filename label loaded unknown; do
    for option in enabled disabled dry; do
      new_sandbox
      run_install "$SANDBOX/target"
      NIGHTLY=$(nightly_label)
      destination="$LA/$NIGHTLY-web.plist"
      rm -f "$destination"
      foreign="$LA/foreign.plist"
      case "$kind" in
        filename) foreign="$destination" ;;
        loaded) foreign="$SANDBOX/loaded" ;;
        unknown) foreign="$SANDBOX/print-error" ;;
      esac
      if [ "$kind" = unknown ]; then
        printf 'ownership query failed\n' > "$foreign"
      elif [ "$kind" = loaded ]; then
        printf 'arguments = {\n /usr/bin/python3\n /elsewhere/autodream-web.py\n serve\n}\n' > "$foreign"
      else
        python3 - "$foreign" "$NIGHTLY" "$kind" <<'FIXTURE'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'Label': sys.argv[2] + ('-other' if sys.argv[3] == 'filename' else '-web'),
                  'ProgramArguments': ['/usr/bin/python3', '/elsewhere/autodream-web.py', 'serve']}, f)
FIXTURE
      fi
      before=$(cat "$foreign")
      : > "$CALLS"
      case "$option" in
        enabled) run_install "$SANDBOX/target" ;;
        disabled) run_install --no-web "$SANDBOX/target" ;;
        dry) run_install --dry-run "$SANDBOX/target" ;;
      esac
      assert_eq "$?" 0 "$kind/$option: install skips the foreign web agent"
      assert_eq "$(cat "$foreign" 2>/dev/null)" "$before" "$kind/$option: foreign file is unchanged"
      if grep -E "^(bootout .*[/]$NIGHTLY-web|bootstrap .*[/]$NIGHTLY-web.plist)$" "$CALLS" >/dev/null; then
        no "$kind/$option: foreign job is never mutated"
      else
        ok "$kind/$option: foreign job is never mutated"
      fi
      assert_grep "$SANDBOX/install.out" 'web LaunchAgent skipped: ownership conflict' "$kind/$option: explains refusal"
    done
  done
}
_run() { "$@"; }
test_owned_loaded_web_agent_is_reinstalled() {
  new_sandbox
  run_install "$SANDBOX/target"
  NIGHTLY=$(nightly_label)
  printf 'arguments = {\n /usr/bin/python3\n %s/target/autodream/autodream-web.py\n serve\n}\n' "$SANDBOX" > "$SANDBOX/loaded"
  : > "$CALLS"
  run_install "$SANDBOX/target"
  assert_grep "$CALLS" "bootout gui/$(id -u)/$NIGHTLY-web" "owned loaded service can be replaced"
  : > "$CALLS"
  run_install --no-web "$SANDBOX/target"
  assert_no_file "$LA/$NIGHTLY-web.plist" "owned loaded service can be removed"
  assert_grep "$CALLS" "bootout gui/$(id -u)/$NIGHTLY-web" "owned loaded service can be unloaded"
}
test_web_reports_directory_precedence() {
  local source expected suffix reports
  for source in relative absolute environment empty; do
    new_sandbox
    mkdir -p "$SANDBOX/target/autodream"
    if [ "$source" = relative ]; then
      printf 'DREAMS_DIR="$AUTODREAM_DIR/reports"\n' > "$SANDBOX/target/autodream/config"
      expected="$SANDBOX/target/autodream/reports"
    else
      printf 'export DREAMS_DIR="%s/reports & archive"\n' "$SANDBOX" > "$SANDBOX/target/autodream/config"
      expected="$SANDBOX/reports & archive"
    fi
    case "$source" in
      environment)
        expected="$SANDBOX/env-reports"
        DREAMS_DIR="$expected" run_install "$SANDBOX/target" ;;
      empty)
        expected="$SANDBOX/target/dreams"
        DREAMS_DIR='' run_install "$SANDBOX/target" ;;
      *) run_install "$SANDBOX/target" ;;
    esac
    assert_eq "$?" 0 "$source: install succeeds"
    NIGHTLY=$(nightly_label)
    for suffix in '' -web -review; do
      reports=$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:DREAMS_DIR' "$LA/$NIGHTLY$suffix.plist")
      assert_eq "$reports" "$expected" "$source: $NIGHTLY$suffix uses the resolved reports directory"
    done
  done
}
_run test_web_reports_directory_precedence
_run test_owned_loaded_web_agent_is_reinstalled
_run test_foreign_web_agents_are_untouched

printf '\npassed: %s   failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
