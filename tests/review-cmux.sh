#!/bin/bash

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$REPO/bin/portable.sh"
REVIEW="$REPO/bin/review.sh"

pass=0; fail=0
# shellcheck source=/dev/null
. "$HERE/lib-assert.sh"

setup_env(){
  local root; root=$(mktemp -d "${TMPDIR:-/tmp}/ccrevcmux.XXXXXX")
  mkdir -p "$root/dreams" "$root/autodream"
  cat > "$root/cmux-mock.sh" <<'MOCK'
#!/bin/bash
# Mock cmux: log every argv to the file named by CMUX_LOG, then act on the
# subcommand. workspace create is the only interesting one; tab-action (the
# rename loop) and anything else is a silent no-op.
echo "$@" >> "$CMUX_LOG"
case "$1" in
  workspace)
    [ "${CMUX_EXIT:-0}" -eq 0 ] || exit "${CMUX_EXIT}"
    echo "workspace:42"
    exit 0
    ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$root/cmux-mock.sh"
  printf '#!/bin/bash\nexit 0\n' > "$root/claude-mock.sh"
  chmod +x "$root/claude-mock.sh"
  : > "$root/cmux.log"
  printf '%s' "$root"
}

mk_report(){ # $1=root $2=date $3=body
  printf '%s\n' "$3" > "$1/dreams/$2.md"
}

marker_dir(){ # $1=root $2=date
  local key; key=$(shasum -a 256 "$1/dreams/$2.md" | awk '{print $1}')
  printf '%s/autodream/logs/review-launched-%s-%s\n' "$1" "$2" "$key"
}
marker_confirmed(){ printf '%s.confirmed\n' "$(marker_dir "$1" "$2")"; }

run_review(){ # $1=root ; rest = args ; override env via $REVIEW_ENV
  local root="$1"; shift
  env $REVIEW_ENV \
  AUTODREAM_DIR="$root/autodream" \
  AUTODREAM_CONFIG="$root/nonexistent-config" \
  AUTODREAM_TRIAGE_SURFACE=cmux \
  CMUX_BIN="$root/cmux-mock.sh" \
  CLAUDE_BIN="$root/claude-mock.sh" \
  CMUX_LOG="$root/cmux.log" \
  DREAMS_DIR="$root/dreams" \
  bash "$REVIEW" "$@" > "$root/out" 2>&1
}
REVIEW_ENV=""

cmux_calls(){ # $1=root — count `workspace create` invocations in the mock log
  grep -c '^workspace create ' "$1/cmux.log" 2>/dev/null || true
}

REPORT_OPEN='# Autodream — 2020-01-02

## Open questions for the user
1. **Thing** — decide X?

<!-- autodream:open-questions=3 -->'

test_first_trigger_opens_workspace(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 1 "first trigger calls cmux exactly once"
  local dir; dir=$(marker_dir "$root" 2020-01-02)
  local conf; conf=$(marker_confirmed "$root" 2020-01-02)
  [ -d "$dir" ] && ok "claim dir stamped ($(basename "$dir"))" \
    || no "claim dir not found at $dir"
  [ -f "$conf" ] && ok "confirmed token written after successful create" \
    || no "confirmed token missing at $conf"
}

test_second_trigger_is_deduped(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  run_review "$root" 2020-01-02
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 1 "second trigger does not open a second workspace"
  local rc=0
  AUTODREAM_DIR="$root/autodream" \
  AUTODREAM_CONFIG="$root/nonexistent-config" \
  AUTODREAM_TRIAGE_SURFACE=cmux \
  CMUX_BIN="$root/cmux-mock.sh" \
  CLAUDE_BIN="$root/claude-mock.sh" \
  CMUX_LOG="$root/cmux.log" \
  DREAMS_DIR="$root/dreams" \
  bash "$REVIEW" 2020-01-02 > "$root/out2" 2>&1 || rc=$?
  assert_eq "$rc" 0 "deduped trigger still exits 0"
  assert_grep "$root/out2" 'triage already launched for this report' "dedup notice names the date"
  assert_grep "$root/out2" '\-\-force' "dedup notice offers --force"
}

test_force_bypasses_marker(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local before; before=$(cmux_calls "$root")
  run_review "$root" --force 2020-01-02              # first run is a force
  assert_eq "$(cmux_calls "$root")" "$((before + 1))" "--force opens despite the marker"
  [ -f "$(marker_confirmed "$root" 2020-01-02)" ] \
    && ok "--force stamps its own confirmed token" \
    || no "--force left no confirmed token (next trigger would re-pop)"
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" "$((before + 1))" "token stamped by --force dedups the next trigger"
}

test_failed_create_releases_marker(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local rc=0
  REVIEW_ENV="CMUX_EXIT=1" run_review "$root" 2020-01-02 || rc=$?
  assert_eq "$rc" 1 "failed create exits non-zero"
  local dir; dir=$(marker_dir "$root" 2020-01-02)
  [ ! -e "$dir" ] && ok "failed create leaves no claim dir behind" \
    || no "failed create left a claim dir"
  [ ! -e "$(marker_confirmed "$root" 2020-01-02)" ] \
    && ok "failed create leaves no confirmed token" \
    || no "failed create left a confirmed token"
  assert_grep "$root/out" 'cmux workspace create failed' "failure names cmux"
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 2 "retry after failure opens the workspace"
}

test_marker_binds_to_report_digest(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  run_review "$root" 2020-01-02                      # stamps confirmed for digest A
  mk_report "$root" 2020-01-02 'completely rewritten report body' >/dev/null
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 2 "rebuilt report (new digest) opens again"
  [ -f "$(marker_confirmed "$root" 2020-01-02)" ] \
    && ok "new confirmed token stamped for rebuilt report" \
    || no "new confirmed token missing for rebuilt report"
}

test_stale_markers_are_pruned(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  mkdir -p "$root/autodream/logs"
  local stale_dir="$root/autodream/logs/review-launched-2000-01-01-olddigest"
  local stale_conf="$stale_dir.confirmed"
  mkdir -p "$stale_dir"
  touch "$stale_conf"
  touch -t 200001010000 "$stale_dir" "$stale_conf"  # 2000 → far older than 14d
  run_review "$root" 2020-01-02
  [ ! -e "$stale_dir" ] && ok "stale claim dir (>14d) reaped" \
    || no "stale claim dir still present"
  [ ! -e "$stale_conf" ] && ok "stale confirmed token (>14d) reaped" \
    || no "stale confirmed token still present"
}

test_confirmed_marker_survives_grace(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  run_review "$root" 2020-01-02                      # 1 create, confirmed stamped
  local dir; dir=$(marker_dir "$root" 2020-01-02)
  local conf; conf=$(marker_confirmed "$root" 2020-01-02)
  touch -t "$(pdate_fmt_epoch $(( $(date +%s) - 172800 )) +%Y%m%d%H%M.%S)" "$dir" "$conf"   # >900s grace, <14d prune
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 1 "confirmed launch is deduped even past the grace window"
}

test_abandoned_claim_is_reclaimed(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local dir; dir=$(marker_dir "$root" 2020-01-02)
  mkdir -p "$dir"
  touch -t "$(pdate_fmt_epoch $(( $(date +%s) - 172800 )) +%Y%m%d%H%M.%S)" "$dir"     # unconfirmed, >grace, <14d prune
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 1 "abandoned claim is reclaimed and the popup opens"
  assert_grep "$root/out" 'reclaiming abandoned claim' "reclaim is reported"
  [ -f "$(marker_confirmed "$root" 2020-01-02)" ] \
    && ok "reclaimed claim ends with a fresh confirmed token" \
    || no "reclaimed claim has no confirmed token"
}

test_in_progress_claim_suppresses(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local dir; dir=$(marker_dir "$root" 2020-01-02)
  mkdir -p "$dir"                                    # fresh, unconfirmed
  run_review "$root" 2020-01-02
  assert_eq "$(cmux_calls "$root")" 0 "young unconfirmed claim suppresses a concurrent trigger"
  assert_grep "$root/out" 'already in progress' "in-progress notice is emitted"
}

test_headless_missing_cmux_fails(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local rc=0
  env AUTODREAM_DIR="$root/autodream" \
      AUTODREAM_CONFIG="$root/nonexistent-config" \
      AUTODREAM_TRIAGE_SURFACE=cmux \
      CMUX_BIN="$root/nonexistent-cmux" \
      DREAMS_DIR="$root/dreams" \
      PATH="$root:/usr/bin:/bin" \
      bash "$REVIEW" 2020-01-02 < /dev/null > "$root/out" 2>&1 || rc=$?
  assert_eq "$rc" 1 "headless run with missing cmux exits non-zero"
  assert_grep "$root/out" 'not a TTY' "headless guard names the TTY condition"
  assert_nogrep "$root/out" 'falling back to inline' "headless run does not fall back to inline"
}

test_interactive_missing_cmux_falls_back_inline(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local rc=0
  env AUTODREAM_DIR="$root/autodream" \
      AUTODREAM_CONFIG="$root/nonexistent-config" \
      AUTODREAM_TRIAGE_SURFACE=cmux \
      CMUX_BIN="$root/nonexistent-cmux" \
      DREAMS_DIR="$root/dreams" \
      PATH="$root:/usr/bin:/bin" \
      CLAUDE_BIN="$root/cmux-mock.sh" \
      python3 "$HERE/with-pty.py" bash "$REVIEW" 2020-01-02 > "$root/out" 2>&1 || rc=$?
  assert_eq "$rc" 0 "interactive run with missing cmux exits 0 (inline fallback)"
  assert_grep "$root/out" 'falling back to inline' "interactive run falls back to inline"
}

test_logs_dir_failure_exits_nonzero(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  mkdir -p "$root/autodream"
  printf 'not a dir\n' > "$root/autodream/logs"      # block the logs dir
  local rc=0
  run_review "$root" 2020-01-02 || rc=$?
  assert_eq "$rc" 1 "uncreatable logs dir exits non-zero"
  assert_grep "$root/out" 'cannot create logs dir' "logs-dir failure is named"
}

test_unwritable_claim_dir_fails(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  mkdir -p "$root/autodream/logs"
  chmod 500 "$root/autodream/logs"                   # owned+r, not writable
  local rc=0
  env AUTODREAM_DIR="$root/autodream" \
    AUTODREAM_CONFIG="$root/nonexistent-config" \
    AUTODREAM_TRIAGE_SURFACE=cmux \
    CMUX_BIN="$root/cmux-mock.sh" \
    CLAUDE_BIN="$root/claude-mock.sh" \
    CMUX_LOG="$root/cmux.log" \
    DREAMS_DIR="$root/dreams" \
    bash "$REVIEW" 2020-01-02 > "$root/out" 2>&1 || rc=$?
  chmod 700 "$root/autodream/logs"                   # restore so sandbox can rm
  assert_eq "$rc" 1 "unwritable claim dir exits non-zero (not 'in progress')"
  assert_grep "$root/out" 'cannot create claim' "claim I/O error is named"
  assert_eq "$(cmux_calls "$root")" 0 "no cmux launch when the claim could not be written"
}

test_missing_claude_preflights(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local rc=0
  env AUTODREAM_DIR="$root/autodream" \
    AUTODREAM_CONFIG="$root/nonexistent-config" \
    AUTODREAM_TRIAGE_SURFACE=cmux \
    CMUX_BIN="$root/cmux-mock.sh" \
    CMUX_LOG="$root/cmux.log" \
    CLAUDE_BIN="$root/nonexistent-claude" \
    DREAMS_DIR="$root/dreams" \
    bash "$REVIEW" 2020-01-02 > "$root/out" 2>&1 || rc=$?
  assert_eq "$rc" 1 "missing claude aborts before launching the workspace"
  assert_grep "$root/out" 'claude binary not found' "claude-missing is named"
  assert_eq "$(cmux_calls "$root")" 0 "no workspace created for a missing claude"
  [ ! -e "$(marker_confirmed "$root" 2020-01-02)" ] \
    && ok "no confirmed token for a never-launched workspace" \
    || no "confirmed token written despite preflight abort"
}

test_missing_shasum_fails_closed(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  local rc=0
  printf '#!/bin/sh\nexit 127\n' > "$root/shasum"; chmod +x "$root/shasum"
  env AUTODREAM_DIR="$root/autodream" \
    AUTODREAM_CONFIG="$root/nonexistent-config" \
    AUTODREAM_TRIAGE_SURFACE=cmux \
    CMUX_BIN="$root/cmux-mock.sh" \
    CMUX_LOG="$root/cmux.log" \
    DREAMS_DIR="$root/dreams" \
    PATH="$root:/bin" \
    bash "$REVIEW" 2020-01-02 > "$root/out" 2>&1 || rc=$?
  assert_eq "$rc" 1 "missing shasum aborts (fail closed)"
  assert_grep "$root/out" 'shasum unavailable' "shasum-missing is named"
}

test_empty_ref_still_confirms(){
  local root; root=$(setup_env)
  mk_report "$root" 2020-01-02 "$REPORT_OPEN"
  cat > "$root/cmux-noref.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$CMUX_LOG"              # log so cmux_calls can count us
echo "created workspace"            # success exit, no workspace:NN ref
exit 0
MOCK
  chmod +x "$root/cmux-noref.sh"
  local rc=0
  env AUTODREAM_DIR="$root/autodream" \
    AUTODREAM_CONFIG="$root/nonexistent-config" \
    AUTODREAM_TRIAGE_SURFACE=cmux \
    CMUX_BIN="$root/cmux-noref.sh" \
    CLAUDE_BIN="$root/claude-mock.sh" \
    CMUX_LOG="$root/cmux.log" \
    DREAMS_DIR="$root/dreams" \
    bash "$REVIEW" 2020-01-02 > "$root/out" 2>&1 || rc=$?
  assert_eq "$rc" 0 "empty ref on rc-0 still exits 0"
  [ -f "$(marker_confirmed "$root" 2020-01-02)" ] \
    && ok "rc-0 confirm is bound regardless of parseable ref" \
    || no "rc-0 launch left no confirmed token (next trigger could duplicate)"
  env AUTODREAM_DIR="$root/autodream" \
    AUTODREAM_CONFIG="$root/nonexistent-config" \
    AUTODREAM_TRIAGE_SURFACE=cmux \
    CMUX_BIN="$root/cmux-noref.sh" \
    CLAUDE_BIN="$root/claude-mock.sh" \
    CMUX_LOG="$root/cmux.log" \
    DREAMS_DIR="$root/dreams" \
    bash "$REVIEW" 2020-01-02 > "$root/out2" 2>&1 || rc=$?
  assert_eq "$(cmux_calls "$root")" 1 "confirmed empty-ref launch dedups the next trigger"
  assert_grep "$root/out2" 'already launched for this report' "dedup notice fired"
}

[ -x "$REVIEW" ] || { echo "FATAL: $REVIEW not executable"; exit 1; }

echo "cc-autodream review.sh cmux-surface tests (mock cmux)"
echo
test_first_trigger_opens_workspace
test_second_trigger_is_deduped
test_force_bypasses_marker
test_failed_create_releases_marker
test_marker_binds_to_report_digest
test_stale_markers_are_pruned
test_confirmed_marker_survives_grace
test_abandoned_claim_is_reclaimed
test_in_progress_claim_suppresses
test_headless_missing_cmux_fails
test_interactive_missing_cmux_falls_back_inline
test_logs_dir_failure_exits_nonzero
test_unwritable_claim_dir_fails
test_empty_ref_still_confirms
test_missing_claude_preflights
test_missing_shasum_fails_closed
echo
echo "----------------------------------------"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
