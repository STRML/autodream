#!/bin/bash
# Tests for what bin/review.sh hands the triage session.
#
# The session's --append-system-prompt used to carry the ENTIRE report. On
# 2026-10-27 that refused every launch: the 2026-10-26 report narrated a night
# of Samsung TV work (sdb, root status, dlopen), and Opus 5.5's classifiers
# answered "Opus 5.5's safeguards flagged this session ... [cyber]" before the
# first reply — on the literal prompt "go". The report's open-questions section
# is ~2KB of decision text and passes; the findings body does not. So the
# contract under test is:
#
#   * the open-questions section is inlined, verbatim
#   * no other part of the report is inlined
#   * the launch prompt is a real instruction, not a bare "go"
#   * a report with no section at all still launches (empty block, no crash)
#   * the inlined section is capped
#
# The mock claude dumps each argv element to $ARGV_DIR/argN so the assertions
# read exactly what the session would receive. No network, no model calls.
#
# Usage:  tests/review-prompt.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp ccrevprompt
REVIEW="$REPO/bin/review.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_grep(){   grep -q -- "$2" "$1" 2>/dev/null && ok "$3" || no "$3 (no /$2/ in $1)"; }
assert_nogrep(){ grep -q -- "$2" "$1" 2>/dev/null && no "$3 (/ $2 / unexpectedly in $1)" || ok "$3"; }
assert_eq(){     [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }

setup_env(){
  local root; root=$(mktemp -d "${TMPDIR:-/tmp}/ccrevprompt.XXXXXX")
  mkdir -p "$root/dreams" "$root/bin" "$root/argv"
  cat > "$root/bin/claude" <<'MOCK'
#!/bin/bash
rm -f "$ARGV_DIR"/arg*
i=0
for a in "$@"; do
  i=$((i + 1))
  printf '%s' "$a" > "$ARGV_DIR/arg$i"
done
printf '%s' "$i" > "$ARGV_DIR/count"
exit 0
MOCK
  chmod +x "$root/bin/claude"
  printf '%s' "$root"
}

# run_review ROOT [args...] — launches with the mock, returns review.sh's code.
run_review(){
  local root="$1"; shift
  ARGV_DIR="$root/argv" \
  AUTODREAM_CONFIG="$root/nonexistent-config" \
  AUTODREAM_TRIAGE_SURFACE=inline \
  DREAMS_DIR="$root/dreams" \
  CLAUDE_BIN="$root/bin/claude" \
  bash "$REVIEW" "$@" > "$root/out" 2>&1
}

# The system prompt is the argv element after --append-system-prompt.
system_prompt(){ # $1=root
  cat "$1/argv/arg4" 2>/dev/null
}
launch_prompt(){ # $1=root
  cat "$1/argv/arg5" 2>/dev/null
}

# A report whose findings body is long and distinct from its questions, so a
# leak is unambiguous. FINDINGS-SENTINEL only ever appears in the body.
mk_report(){ # $1=root $2=date $3=questions-body
  local root="$1" date="$2" q="$3"
  {
    printf '# Autodream — %s\n\n' "$date"
    printf '## Activity snapshot\n\n'
    printf 'FINDINGS-SENTINEL the body nobody needs inlined.\n\n'
    printf '## Top patterns (ranked)\n\n'
    printf '### Some finding\n\nFINDINGS-SENTINEL again, in a finding.\n\n'
    printf '## Open questions for the user\n\n'
    printf '%s\n\n' "$q"
    printf '<!-- autodream:open-questions=1 -->\n\n'
    printf '## Triage decisions\n\n- none yet\n'
  } > "$root/dreams/$date.md"
}

Q_BODY='1. **Hook tightening** — should nudge-assumptions.sh block at edit #1?
   - Two findings: the hook fired late, and the agent re-derived the rule.
   - Options: (a) block at #1 (recommended); (b) keep nudging; (c) delete it.'

# --- tests -----------------------------------------------------------------

test_questions_inlined_findings_not(){
  local root; root=$(setup_env); mk_report "$root" 2020-01-02 "$Q_BODY"
  run_review "$root" --force 2020-01-02
  local sp; sp=$(system_prompt "$root")
  printf '%s' "$sp" > "$root/sp"
  assert_grep "$root/sp" 'Hook tightening' "the open question is inlined"
  assert_grep "$root/sp" 'block at edit #1' "question body and options are inlined"
  assert_grep "$root/sp" 'open-questions date="2020-01-02"' "the block names the date"
  assert_nogrep "$root/sp" 'FINDINGS-SENTINEL' "the findings body is NOT inlined"
  assert_nogrep "$root/sp" 'Top patterns' "other report sections are NOT inlined"
}

test_launch_prompt_is_an_instruction(){
  local root; root=$(setup_env); mk_report "$root" 2020-01-02 "$Q_BODY"
  run_review "$root" --force 2020-01-02
  local p; p=$(launch_prompt "$root")
  assert_eq "$p" 'Start the triage: restate the first open question and recommend one action.' "launch prompt is a real instruction"
  [ "$p" = "go" ] && no "launch prompt is not the bare word go" || ok "launch prompt is not the bare word go"
}

test_prompt_does_not_ask_for_the_whole_report(){
  local root; root=$(setup_env); mk_report "$root" 2020-01-02 "$Q_BODY"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  # A prompt that tells the model to read the report undoes the whole fix.
  assert_nogrep "$root/sp" 'Read the report' "system prompt does not instruct a full report read"
  assert_grep "$root/sp" 'Do not read the whole report' "system prompt tells the model to stay out of the body"
}

test_missing_section_still_launches(){
  local root; root=$(setup_env)
  printf '# Autodream — 2020-01-02\n\n## Top patterns\n\nNothing.\n\n<!-- autodream:open-questions=1 -->\n' \
    > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  assert_eq "$(cat "$root/argv/count" 2>/dev/null)" "5" "a section-less report still launches the session"
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'open-questions date="2020-01-02"' "the empty block is still well formed"
}

test_section_is_capped(){
  local root; root=$(setup_env)
  # 30KB of question text: the cap is 12000 bytes.
  local big; big=$(head -c 30000 /dev/zero | tr '\0' 'q')
  mk_report "$root" 2020-01-02 "1. **Huge** — $big"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  local bytes; bytes=$(wc -c < "$root/sp" | tr -d ' ')
  [ "$bytes" -lt 16000 ] && ok "system prompt stays bounded (${bytes} bytes)" \
    || no "system prompt stays bounded (got ${bytes} bytes)"
}

echo "tests/review-prompt.sh"
test_questions_inlined_findings_not
test_launch_prompt_is_an_instruction
test_prompt_does_not_ask_for_the_whole_report
test_missing_section_still_launches
test_section_is_capped

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
