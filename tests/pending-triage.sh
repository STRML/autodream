#!/bin/bash
# Tests for bin/pending-triage.sh: which dreams still have open questions nobody answered.
#
# Fixture reports in a sandbox dreams/ dir, dated relative to today because the script
# only looks at a trailing window. No network, no model calls.
#
# Usage:  tests/pending-triage.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp ccpend
# shellcheck source=/dev/null
. "$REPO/bin/portable.sh"
PENDING="$REPO/bin/pending-triage.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_eq(){ if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got [$1] want [$2])"; fi; }

TODAY=$(date +%Y-%m-%d)
ago(){ pdate_shift "$TODAY" "-$1" d; }

# report DIR DATE QUESTIONS [triaged]
report(){
  local f="$1/$2.md"
  { printf '# Autodream — %s\n\n## Open questions\n\n<!-- autodream:open-questions=%s -->\n' "$2" "$3"
    [ "$3" -gt 0 ] && printf '**A question**\n'
    [ "${4:-}" = triaged ] && printf '\n## Triage decisions\n\n- skipped\n'
  } > "$f"
}

new_env(){ local r; r=$(mktemp -d "${TMPDIR:-/tmp}/ccpend.XXXXXX"); mkdir -p "$r/dreams" "$r/autodream"; printf '%s' "$r"; }
run(){ # $1=root, rest=args
  local root="$1"; shift
  AUTODREAM_DIR="$root/autodream" DREAMS_DIR="$root/dreams" AUTODREAM_CONFIG=/nonexistent "$PENDING" "$@"
}

echo "# an empty queue"
r=$(new_env)
assert_eq "$(run "$r" --summary)" "no issues to address!" "no reports at all"
assert_eq "$(run "$r")" "no issues to address!" "--summary is the default"
report "$r/dreams" "$(ago 1)" 0
assert_eq "$(run "$r" --summary)" "no issues to address!" "a report with zero open questions"
report "$r/dreams" "$(ago 2)" 3 triaged
assert_eq "$(run "$r" --summary)" "no issues to address!" "a triaged report is not pending"
assert_eq "$(run "$r" --list)" "" "and --list prints nothing"
rm -rf "$r"

echo "# one pending report"
r=$(new_env)
report "$r/dreams" "$(ago 1)" 1
assert_eq "$(run "$r" --summary)" "now triaging 1 issue from $(ago 1)" "singular, one date"
rm -rf "$r"

echo "# several reports"
r=$(new_env)
report "$r/dreams" "$(ago 5)" 2
report "$r/dreams" "$(ago 3)" 0
report "$r/dreams" "$(ago 2)" 4 triaged
report "$r/dreams" "$(ago 1)" 3
assert_eq "$(run "$r" --summary)" "now triaging 5 issues from dates $(ago 5) to $(ago 1)" "totals the questions, names the first and last date"
assert_eq "$(run "$r" --list | cut -f1,2 | tr '\t\n' ' ')" "$(ago 5) 2 $(ago 1) 3 " "--list is oldest first and skips the triaged and the empty"
assert_eq "$(run "$r" --list | head -1 | cut -f3)" "$r/dreams/$(ago 5).md" "and carries the report path"
rm -rf "$r"

echo "# the window"
r=$(new_env)
report "$r/dreams" "$(ago 30)" 2
report "$r/dreams" "$(ago 1)" 1
assert_eq "$(run "$r" --summary)" "now triaging 1 issue from $(ago 1)" "a report older than the window is left out"
assert_eq "$(AUTODREAM_PENDING_DAYS=60 run "$r" --summary)" "now triaging 3 issues from dates $(ago 30) to $(ago 1)" "AUTODREAM_PENDING_DAYS widens it"
AUTODREAM_PENDING_DAYS=soon run "$r" --summary >/dev/null 2>&1; assert_eq "$?" "2" "a non-numeric window is refused"
rm -rf "$r"

echo "# a report whose count cannot be read"
r=$(new_env)
printf '# Autodream\n\nno marker here\n' > "$r/dreams/$(ago 1).md"
assert_eq "$(run "$r" --summary)" "no issues to address!" "no marker and no recognisable section is not counted"
rm -rf "$r"

echo "# a report part way through triage stays pending"
r=$(new_env)
report "$r/dreams" "$(ago 1)" 3
printf '\n## Triage in progress\n\n- question 1: approved\n' >> "$r/dreams/$(ago 1).md"
assert_eq "$(run "$r" --summary)" "now triaging 3 issues from $(ago 1)" "the in-progress heading does not retire it"
rm -rf "$r"

echo "# a date in the future is outside the window"
r=$(new_env)
report "$r/dreams" "$(pdate_shift "$TODAY" 3 d)" 2
report "$r/dreams" "$(ago 1)" 1
assert_eq "$(run "$r" --summary)" "now triaging 1 issue from $(ago 1)" "a future-dated report is left out"
rm -rf "$r"

echo "# the config"
r=$(new_env)
report "$r/dreams" "$(ago 20)" 2
report "$r/dreams" "$(ago 1)" 1
# shellcheck disable=SC2016 # the dollar sign is the point: the config must reach an unset variable
printf 'BROKEN=$NO_SUCH_VARIABLE_ANYWHERE\nAUTODREAM_PENDING_DAYS=30\n' > "$r/autodream/config"
out=$(AUTODREAM_DIR="$r/autodream" DREAMS_DIR="$r/dreams" AUTODREAM_CONFIG="$r/autodream/config" "$PENDING" --summary 2>&1)
assert_eq "$out" "now triaging 3 issues from dates $(ago 20) to $(ago 1)" "an unset variable in the config does not kill the script, and the config applies"
out=$(AUTODREAM_PENDING_DAYS=5 AUTODREAM_DIR="$r/autodream" DREAMS_DIR="$r/dreams" AUTODREAM_CONFIG="$r/autodream/config" "$PENDING" --summary 2>&1)
assert_eq "$out" "now triaging 1 issue from $(ago 1)" "the environment beats the config"
rm -rf "$r"

echo "# arguments"
r=$(new_env)
run "$r" --bogus >/dev/null 2>&1; assert_eq "$?" "2" "an unknown option is refused"
rm -rf "$r"

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
