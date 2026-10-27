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
  # 30KB of question text across several questions: the cap is 12000 bytes and
  # must cut between questions, never inside one.
  local big; big=$(head -c 6000 /dev/zero | tr '\0' 'q')
  mk_report "$root" 2020-01-02 "1. **Q1** — $big
2. **Q2** — $big
3. **Q3** — $big
4. **Q4** — $big"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  local bytes; bytes=$(wc -c < "$root/sp" | tr -d ' ')
  [ "$bytes" -lt 16000 ] && ok "system prompt stays bounded (${bytes} bytes)" \
    || no "system prompt stays bounded (got ${bytes} bytes)"
  assert_grep "$root/sp" 'truncated="1"' "the block is marked truncated"
  assert_grep "$root/sp" 'did not all fit' "the prompt says the list was cut"
  assert_nogrep "$root/sp" 'quoted in full' "the prompt does not claim completeness"
  # Every question that appears is whole: it starts with its own number and
  # carries the full body, and the count of numbers shown is a prefix of 1..4.
  local shown; shown=$(grep -cE '^[0-9]+\. \*\*Q' "$root/sp")
  [ "$shown" -ge 1 ] && ok "at least one whole question survived the cap (${shown})" \
    || no "at least one whole question survived the cap (got ${shown})"
  # No question may be cut: every 6000-byte body in the fixture is either shown
  # whole or not shown at all, so a run of q's shorter than 6000 means a cut.
  local cut; cut=$(grep -oE 'q{100,}' "$root/sp" | awk 'length($0) != 6000' | wc -l | tr -d ' ')
  assert_eq "$cut" "0" "the cap never cuts a question in half"
}

test_fenced_example_is_not_the_section(){
  local root; root=$(setup_env)
  # An example fence earlier in the report quotes the heading and a body. The
  # extraction must not start there.
  {
    printf '# Autodream — 2020-01-02\n\n## Top patterns\n\nExample of the section format:\n\n'
    printf '```\n## Open questions for the user\nFENCED-EXAMPLE-BODY\n```\n\n'
    printf '## Open questions for the user\n\n%s\n\n<!-- autodream:open-questions=1 -->\n' "$Q_BODY"
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_nogrep "$root/sp" 'FENCED-EXAMPLE-BODY' "a fenced example heading does not start the section"
  assert_grep "$root/sp" 'Hook tightening' "the real section is still inlined"
}

test_fenced_heading_inside_a_question_does_not_end_it(){
  local root; root=$(setup_env)
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user\n\n'
    printf '1. **Fenced** — which heading wins?\n\n```\n## Example heading inside a fence\n```\n\n'
    printf '   - AFTER-THE-FENCE the rest of question 1.\n\n'
    printf '2. **Second** — still here?\n\n<!-- autodream:open-questions=2 -->\n'
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'AFTER-THE-FENCE' "text after a fenced heading is kept"
  assert_grep "$root/sp" 'still here' "the next question is kept"
}

test_heading_must_match_the_whole_line(){
  local root; root=$(setup_env)
  # A different heading that merely starts with the text is not the section.
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user agents\n\nNOT-THE-SECTION\n\n'
    printf '## Open questions for the user\n\n%s\n\n<!-- autodream:open-questions=1 -->\n' "$Q_BODY"
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_nogrep "$root/sp" 'NOT-THE-SECTION' "a longer heading is a different section"
  assert_grep "$root/sp" 'Hook tightening' "the exact heading is still found"
}

test_tilde_fence_example_is_not_the_section(){
  local root; root=$(setup_env)
  {
    printf '# Autodream — 2020-01-02\n\n## Top patterns\n\nExample:\n\n'
    printf '~~~\n## Open questions for the user\nTILDE-FENCED-BODY\n~~~\n\n'
    printf '## Open questions for the user\n\n%s\n\n<!-- autodream:open-questions=1 -->\n' "$Q_BODY"
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_nogrep "$root/sp" 'TILDE-FENCED-BODY' "a tilde-fenced example does not start the section"
  assert_grep "$root/sp" 'Hook tightening' "the real section is still inlined"
}

test_tilde_fence_inside_a_question_does_not_end_it(){
  local root; root=$(setup_env)
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user\n\n'
    printf '1. **Tilde** — which heading wins?\n\n~~~\n## Example heading in a tilde fence\n~~~\n\n'
    printf '   - AFTER-TILDE the rest of question 1.\n\n'
    printf '2. **Second** — still here?\n\n<!-- autodream:open-questions=2 -->\n'
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'AFTER-TILDE' "text after a tilde-fenced heading is kept"
  assert_grep "$root/sp" 'still here' "the next question is kept"
}

test_cap_never_keeps_a_heading_without_its_context(){
  local root; root=$(setup_env)
  # Question 1 fits; question 2 is a heading whose own context overflows the
  # remaining room. Keeping the heading alone would ask for a decision on a
  # question whose evidence was cut off.
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user\n\n'
    printf '1. **Small** — a question that fits.\n   - context that fits.\n\n'
    printf '2. **Huge** — a question whose context does not fit.\n'
    printf '   - %s\n\n' "$(head -c 13000 /dev/zero | tr '\0' 'z')"
    printf '3. **Third** — never reached.\n\n<!-- autodream:open-questions=3 -->\n'
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'a question that fits' "the question that fits is shown"
  assert_nogrep "$root/sp" 'whose context does not fit' "a heading is not kept without its context"
  assert_grep "$root/sp" 'truncated="1"' "the block says it was truncated"
}

test_longer_fence_containing_a_shorter_is_content(){
  local root; root=$(setup_env)
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user\n\n'
    printf '1. **Nested** — which fence wins?\n\n'
    printf '````\n```\n## Example heading inside the inner fence\n```\nAFTER-NESTED still inside the outer fence.\n````\n\n'
    printf '2. **Second** — still here?\n\n<!-- autodream:open-questions=2 -->\n'
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'AFTER-NESTED' "a shorter fence inside a longer one does not close it"
  assert_grep "$root/sp" 'still here' "the next question survives a nested fence"
  assert_grep "$root/sp" 'truncated="0"' "a section that fits is not marked truncated"
}

test_cap_does_not_split_on_a_list_item_inside_a_fence(){
  local root; root=$(setup_env)
  # A fenced example inside the question holds a `- option` line. If the cap
  # treats that as a new question it keeps the heading and the opening fence,
  # then starts counting a fresh block, and the question loses its context.
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user\n\n'
    printf '1. **Small** — a question that fits.\n   - context that fits.\n\n'
    printf '2. **Fenced** — which option wins?\n   - context before the fence.\n\n'
    printf '```\n- option a\n- option b\n```\n\n'
    printf '   - %s\n\n' "$(head -c 13000 /dev/zero | tr '\0' 'w')"
    printf '3. **Third** — never reached.\n\n<!-- autodream:open-questions=3 -->\n'
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'a question that fits' "the question that fits is shown"
  # Either the whole fenced question is shown or none of it; a heading plus its
  # opening fence with the context cut is the failure.
  if grep -q 'which option wins' "$root/sp"; then
    grep -q 'context before the fence' "$root/sp" && ok "a fenced question is kept whole" \
      || no "a fenced question is kept whole (heading kept, context dropped)"
  else
    ok "a fenced question is kept whole (dropped entirely)"
  fi
  assert_grep "$root/sp" 'truncated="1"' "the block says it was truncated"
}

test_labelled_fence_is_a_fence(){
  local root; root=$(setup_env)
  {
    printf '# Autodream — 2020-01-02\n\n## Open questions for the user\n\n'
    printf '1. **Labelled** — which label wins?\n\n'
    printf '```bash\n## not a heading\n- not a question\n```\n\n'
    printf '   - AFTER-LABELLED the rest of question 1.\n\n'
    printf '2. **Second** — still here?\n\n<!-- autodream:open-questions=2 -->\n'
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_grep "$root/sp" 'AFTER-LABELLED' "a \`\`\`bash fence does not end the question"
  assert_grep "$root/sp" 'still here' "the next question survives a labelled fence"
  assert_grep "$root/sp" 'truncated="0"' "a labelled fence is not mistaken for truncation"
}

test_labelled_fence_before_the_section_is_an_example(){
  local root; root=$(setup_env)
  {
    printf '# Autodream — 2020-01-02\n\n## Top patterns\n\n'
    printf '```markdown\n## Open questions for the user\nLABELLED-EXAMPLE\n```\n\n'
    printf '## Open questions for the user\n\n%s\n\n<!-- autodream:open-questions=1 -->\n' "$Q_BODY"
  } > "$root/dreams/2020-01-02.md"
  run_review "$root" --force 2020-01-02
  system_prompt "$root" > "$root/sp"
  assert_nogrep "$root/sp" 'LABELLED-EXAMPLE' "a labelled example fence does not start the section"
  assert_grep "$root/sp" 'Hook tightening' "the real section is still found"
}

test_temps_are_removed(){
  local root; root=$(setup_env); mk_report "$root" 2020-01-02 "$Q_BODY"
  local before; before=$(ls "${TMPDIR:-/tmp}" | grep -c '^autodream-questions' || true)
  run_review "$root" --force 2020-01-02
  local after; after=$(ls "${TMPDIR:-/tmp}" | grep -c '^autodream-questions' || true)
  assert_eq "$after" "$before" "no question temp file survives the launch"
}

echo "tests/review-prompt.sh"
test_questions_inlined_findings_not
test_launch_prompt_is_an_instruction
test_prompt_does_not_ask_for_the_whole_report
test_missing_section_still_launches
test_section_is_capped
test_fenced_example_is_not_the_section
test_fenced_heading_inside_a_question_does_not_end_it
test_heading_must_match_the_whole_line
test_tilde_fence_example_is_not_the_section
test_tilde_fence_inside_a_question_does_not_end_it
test_cap_never_keeps_a_heading_without_its_context
test_longer_fence_containing_a_shorter_is_content
test_cap_does_not_split_on_a_list_item_inside_a_fence
test_labelled_fence_is_a_fence
test_labelled_fence_before_the_section_is_an_example
test_temps_are_removed

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
