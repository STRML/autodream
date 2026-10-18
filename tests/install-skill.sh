#!/usr/bin/env bash
# The global /autodream skill: where install.sh links it, and when it leaves it alone.
#
# The install target is a sandbox directory (its first positional argument) and HOME is a
# sandbox too, so nothing here touches ~/.claude. --no-schedule keeps launchd out of it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
no()   { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n' "$1"; }
assert_eq()   { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got [$1] want [$2])"; fi; }
absent()  { if [ -e "$1" ]; then no "$2"; else ok "$2"; fi; }
linked()  { if [ -L "$1" ]; then ok "$2"; else no "$2"; fi; }
assert_grep() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$3"; else no "$3 (no [$2] in $1)"; fi; }

SANDBOX=""
trap '[ -n "$SANDBOX" ] && rm -rf "$SANDBOX"' EXIT

new_sandbox() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/ccad-sk.XXXXXX")
  SANDBOX=$(cd "$SANDBOX" && pwd)
  mkdir -p "$SANDBOX/home" "$SANDBOX/target"
}
# install [env KEY=VALUE ...] -- <installer args>
install() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  env HOME="$SANDBOX/home" ${envs[@]+"${envs[@]}"} bash "$REPO/install.sh" --no-schedule "$@" > "$SANDBOX/install.out" 2>&1
}

echo "# the default install links the skill and the scripts it calls"
new_sandbox
install -- "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the install succeeds"
assert_eq "$(readlink "$SANDBOX/target/skills/autodream")" "$REPO/skills/autodream" "the skill is linked under the target's skills dir"
assert_eq "$(sed -n '2p' "$SANDBOX/target/skills/autodream/SKILL.md")" "name: autodream" "and its SKILL.md is readable through the link"
assert_eq "$(readlink "$SANDBOX/target/autodream/pending-triage.sh")" "$REPO/bin/pending-triage.sh" "pending-triage.sh is linked"
assert_eq "$(readlink "$SANDBOX/target/autodream/report-format.sh")" "$REPO/bin/report-format.sh" "and so is the library it sources"

echo "# --no-skill leaves the skills dir alone"
new_sandbox
install -- --no-skill "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the install succeeds"
absent "$SANDBOX/target/skills" "no skills dir is created"

echo "# AUTODREAM_SKILLS_DIR moves the link"
new_sandbox
install AUTODREAM_SKILLS_DIR="$SANDBOX/elsewhere" -- "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the install succeeds"
assert_eq "$(readlink "$SANDBOX/elsewhere/autodream")" "$REPO/skills/autodream" "the skill is linked there"
absent "$SANDBOX/target/skills" "and not under the target"

echo "# a skill the user already has is left alone, and the install still finishes"
new_sandbox
mkdir -p "$SANDBOX/target/skills/autodream"
printf 'mine\n' > "$SANDBOX/target/skills/autodream/SKILL.md"
install -- "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the install succeeds"
assert_eq "$(cat "$SANDBOX/target/skills/autodream/SKILL.md")" "mine" "the user's skill is untouched"
assert_grep "$SANDBOX/install.out" "refusing to install over it" "the install says why"
assert_grep "$SANDBOX/install.out" "/autodream skill not linked" "and that the skill is missing"
linked "$SANDBOX/target/autodream/run.sh" "the scripts are still linked"

echo "# a dry run links nothing"
new_sandbox
install -- --dry-run "$SANDBOX/target"; rc=$?
assert_eq "$rc" "0" "the dry run succeeds"
assert_grep "$SANDBOX/install.out" "[dry-run] link $SANDBOX/target/skills/autodream -> $REPO/skills/autodream" "it says what it would link"
absent "$SANDBOX/target/skills" "and creates no skills dir"

printf '\npassed: %s   failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
