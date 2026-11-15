#!/bin/bash
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
THREADS="$REPO/bin/threads.sh"
PORTABLE="$REPO/bin/portable.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adt12.XXXXXX") || exit 1
PASS=0
FAIL=0
. "$PORTABLE"
AS_OF=$(pdate_shift "$(pdate_yesterday)" 1 d) || exit 1

cleanup() { /usr/bin/trash "$TMP"; }
trap cleanup EXIT

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }
assert_nonzero() { [ "$1" -ne 0 ] && ok "$2" || no "$2 (got zero)"; }

seed() {
  local dir=$1 age_seven age_eight
  age_seven=$(pdate_shift "$AS_OF" -7 d) || return 1
  age_eight=$(pdate_shift "$AS_OF" -8 d) || return 1
  mkdir -p "$dir"
  jq -nc --arg d "$age_eight" '{id:"t-00000001",kind:"work",repo:"/repo/alpha",title:"Alpha [x]* thread",goal:"Ship alpha",sessions:[{date:$d,hash:"a1",session_path:"/sessions/a1.jsonl",outcome:"not_achieved"}],status:"open",done_by:"",last_seen:$d}' > "$dir/threads.jsonl"
  jq -nc --arg d "$age_seven" '{id:"t-00000002",kind:"idea",repo:"/repo/beta",title:"Mostly achieved idea",goal:"Explore beta",sessions:[{date:$d,hash:"b1",session_path:"/sessions/b1.jsonl",outcome:"mostly_achieved"}],status:"open",done_by:"",last_seen:$d}' >> "$dir/threads.jsonl"
  jq -nc --arg d "$age_seven" '{id:"t-00000003",kind:"work",repo:"/repo/alpha",title:"Seven day boundary",goal:"Check cutoff",sessions:[{date:$d,hash:"a2",session_path:"/sessions/a2.jsonl",outcome:"partially_achieved"}],status:"open",done_by:"",last_seen:$d}' >> "$dir/threads.jsonl"
}

state_json() { jq -c "select(.id == \"$2\")" "$1/threads.jsonl"; }

test_threads_close_and_reopen() {
  local dir="$TMP/close" closed_status closed_done_by reopened_status
  seed "$dir"
  AUTODREAM_DIR="$dir" "$THREADS" close t-00000001 >/dev/null 2>&1
  closed_status=$(state_json "$dir" t-00000001 | jq -r .status)
  closed_done_by=$(state_json "$dir" t-00000001 | jq -r .done_by)
  assert_eq "$closed_status" closed_by_sam "operator close persists"
  assert_eq "$closed_done_by" sam "operator owns the close"
  AUTODREAM_DIR="$dir" "$THREADS" reopen t-00000001 >/dev/null 2>&1
  reopened_status=$(state_json "$dir" t-00000001 | jq -r .status)
  assert_eq "$reopened_status" open "explicit reopen succeeds"
  assert_eq "$(state_json "$dir" t-00000001 | jq -r .done_by)" null "reopen clears closure attribution"
}

test_threads_state_write_is_atomic() {
  local dir="$TMP/atomic" before after_failed_write after_failed_rename shim
  seed "$dir"
  before=$(cat "$dir/threads.jsonl")
  shim="$TMP/fail-mktemp"; mkdir -p "$shim"
  cat > "$shim/mktemp" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$shim/mktemp"
  PATH="$shim:$PATH" AUTODREAM_DIR="$dir" "$THREADS" close t-00000001 >/dev/null 2>&1
  assert_nonzero "$?" "mktemp failure is reported"
  after_failed_write=$(cat "$dir/threads.jsonl")
  assert_eq "$after_failed_write" "$before" "old state survives"
  /usr/bin/trash "$shim/mktemp"
  cat > "$shim/mv" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$shim/mv"
  PATH="$shim:$PATH" AUTODREAM_DIR="$dir" "$THREADS" close t-00000001 >/dev/null 2>&1
  assert_nonzero "$?" "rename failure is reported"
  after_failed_rename=$(cat "$dir/threads.jsonl")
  assert_eq "$after_failed_rename" "$before" "rename failure preserves state"
}

test_threads_cli_refuses_unreadable_state() {
  local dir="$TMP/unreadable" before after rc
  seed "$dir"
  before=$(cat "$dir/threads.jsonl")
  chmod 000 "$dir/threads.jsonl"
  AUTODREAM_DIR="$dir" "$THREADS" close t-00000001 >/dev/null 2>&1
  rc=$?
  chmod 600 "$dir/threads.jsonl"
  after=$(cat "$dir/threads.jsonl")
  assert_eq "$rc" 1 "CLI reports unreadable state"
  assert_eq "$after" "$before" "state is not replaced with an empty index"
  printf '{broken json\n' > "$dir/threads.jsonl"
  before=$(cat "$dir/threads.jsonl")
  AUTODREAM_DIR="$dir" "$THREADS" close t-00000001 >/dev/null 2>&1
  rc=$?
  after=$(cat "$dir/threads.jsonl")
  assert_eq "$rc" 1 "CLI reports malformed state"
  assert_eq "$after" "$before" "malformed state is not replaced"
}

test_threads_list_computes_dropped() {
  local dir="$TMP/dropped" age_seven_count age_eight_count mostly_achieved_count
  seed "$dir"
  age_seven_count=$(AUTODREAM_DIR="$dir" "$THREADS" list --status dropped --json | jq '[.[] | select(.id == "t-00000003")] | length')
  age_eight_count=$(AUTODREAM_DIR="$dir" "$THREADS" list --status dropped --json | jq '[.[] | select(.id == "t-00000001")] | length')
  mostly_achieved_count=$(AUTODREAM_DIR="$dir" "$THREADS" list --status dropped --json | jq '[.[] | select(.id == "t-00000002")] | length')
  assert_eq "$age_seven_count" 0 "older than seven days is strict"
  assert_eq "$age_eight_count" 1 "unfinished open thread becomes dropped"
  assert_eq "$(state_json "$dir" t-00000001 | jq -r .status)" open "dropped status is not persisted"
  assert_eq "$mostly_achieved_count" 0 "mostly achieved stays quiet"
}

test_threads_missing_state_is_empty() {
  local dir="$TMP/missing" count
  mkdir -p "$dir"
  count=$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq 'length')
  assert_eq "$count" 0 "missing index reads as empty"
}

test_threads_report_without_index_is_empty() {
  local dir="$TMP/fresh-report" report
  mkdir -p "$dir/dreams"
  report=$(AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" report 2020-01-02 2>&1)
  assert_eq "$report" "$(printf '## Dropped threads\n\nNo dropped threads are currently eligible.')" "fresh install report renders an empty section without a warning"
}

test_threads_render_missing_index_uses_empty_validated_state() {
  local dir="$TMP/fresh-render" rc output
  mkdir -p "$dir/dreams"
  AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" \
    /bin/bash "$THREADS" render >/dev/null 2>&1
  rc=$?
  output=$(python3 - "$dir/dreams/threads.html" <<'PY'
import sys
print("empty" if '"threads":[]' in open(sys.argv[1], encoding="utf-8").read() else "nonempty")
PY
)
  assert_eq "$rc" 0 "missing index renders successfully"
  assert_eq "$output" 'empty' "missing index reaches the renderer as an empty state value"
}

test_threads_renderer_reads_validated_state_from_stdin() {
  local dir="$TMP/render-stdin" output rc
  mkdir -p "$dir"
  printf '%s\n' '[{"id":"t-12345678","kind":"work","repo":"","title":"stdin thread","goal":"continue","sessions":[],"status":"open","done_by":null,"last_seen":"2020-01-01"}]' |
    python3 "$REPO/bin/threads-render.py" - "$dir/threads.html" --as-of "$AS_OF" >/dev/null 2>&1
  rc=$?
  output=$(grep -c 'stdin thread' "$dir/threads.html" 2>/dev/null || true)
  assert_eq "$rc" 0 "renderer accepts the already validated state on stdin"
  assert_eq "$output" 1 "renderer uses the supplied state snapshot"
}

test_threads_dashboard_singular_session_label() {
  local output
  output=$(python3 - "$REPO/templates/threads.html" <<'PY'
import sys
template = open(sys.argv[1], encoding="utf-8").read()
print("ok" if 'thread.sessions.length === 1 ? " session" : " sessions"' in template else "missing")
PY
)
  assert_eq "$output" ok "dashboard uses singular session for one linked session"
}

test_threads_resume_missing_index_is_clean() {
  local dir="$TMP/fresh-resume" output rc
  mkdir -p "$dir"
  output=$(AUTODREAM_DIR="$dir" "$THREADS" resume t-12345678 2>&1)
  rc=$?
  assert_eq "$rc" 1 "missing index reports an unknown thread"
  case "$output" in *"unknown thread id"*) ok "missing index produces a clean resume error" ;; *) no "missing index produces a clean resume error ($output)" ;; esac
  case "$output" in *"Traceback"*) no "missing index resume has no traceback" ;; *) ok "missing index resume has no traceback" ;; esac
}

test_threads_rejects_null_session_as_unreadable_state() {
  local dir="$TMP/null-session" output rc
  mkdir -p "$dir"
  printf '%s\n' '{"id":"t-12345678","kind":"work","repo":"","title":"broken","goal":"broken","sessions":[null],"status":"open","done_by":null,"last_seen":"2020-01-01"}' > "$dir/threads.jsonl"
  output=$(AUTODREAM_DIR="$dir" "$THREADS" close t-12345678 2>&1)
  rc=$?
  assert_eq "$rc" 1 "malformed session element is rejected by the state reader"
  case "$output" in *"malformed state"*) ok "malformed session is reported as unreadable state" ;; *) no "malformed session is reported as unreadable state ($output)" ;; esac
}

test_threads_renderer_rejects_malformed_session_record() {
  local dir="$TMP/render-bad-session" output rc
  mkdir -p "$dir"
  printf '%s\n' '{"id":"t-12345678","kind":"work","repo":"","title":"broken","goal":"broken","sessions":[{"date":"2020-01-01"}],"status":"open","done_by":null,"last_seen":"2020-01-01"}' > "$dir/threads.jsonl"
  output=$(python3 "$REPO/bin/threads-render.py" "$dir/threads.jsonl" "$dir/threads.html" --as-of "$AS_OF" 2>&1)
  rc=$?
  assert_eq "$rc" 1 "renderer rejects session missing its hash"
  case "$output" in *"invalid thread"*) ok "renderer identifies malformed session state" ;; *) no "renderer identifies malformed session state ($output)" ;; esac
  case "$output" in *"Traceback"*) no "renderer malformed-state error has no traceback" ;; *) ok "renderer malformed-state error has no traceback" ;; esac
}

test_threads_invalid_and_unknown_ids_are_refused() {
  local dir="$TMP/ids" invalid_rc unknown_rc
  seed "$dir"
  AUTODREAM_DIR="$dir" "$THREADS" close bad-id >/dev/null 2>&1
  invalid_rc=$?
  AUTODREAM_DIR="$dir" "$THREADS" close t-ffffffff >/dev/null 2>&1
  unknown_rc=$?
  assert_eq "$invalid_rc" 2 "invalid IDs are refused as malformed input"
  assert_eq "$unknown_rc" 1 "unknown IDs are refused as missing records"
}

test_threads_search_treats_metacharacters_literally() {
  local dir="$TMP/search" count
  seed "$dir"
  count=$(AUTODREAM_DIR="$dir" "$THREADS" search '[x]*' --json | jq 'length')
  assert_eq "$count" 1 "search metacharacters match literally"
}

test_threads_dropped_days_accepts_leading_zero() {
  local dir="$TMP/leading-zero" count
  seed "$dir"
  printf 'AUTODREAM_THREADS_DROPPED_DAYS=08\n' > "$dir/config"
  count=$(AUTODREAM_DIR="$dir" "$THREADS" list --status dropped --json | jq '[.[] | select(.id == "t-00000001")] | length')
  assert_eq "$count" 0 "08 is parsed as decimal eight"
}

test_threads_environment_overrides_config() {
  local dir="$TMP/config-precedence" count
  seed "$dir"
  printf 'AUTODREAM_THREADS_DROPPED_DAYS=08\n' > "$dir/config"
  count=$(AUTODREAM_DIR="$dir" AUTODREAM_THREADS_DROPPED_DAYS=7 "$THREADS" list --status dropped --json | jq '[.[] | select(.id == "t-00000001")] | length')
  assert_eq "$count" 1 "environment value wins over config"
}

test_threads_reclaims_stale_lock() {
  local dir="$TMP/stale-lock" now old stamp rc
  seed "$dir"
  mkdir "$dir/threads.jsonl.lock"
  now=$(pdate_epoch "$(date '+%Y-%m-%d %H:%M:%S')") || return 1
  old=$((now - 121))
  stamp=$(pdate_fmt_epoch "$old" +%Y%m%d%H%M.%S) || return 1
  touch -t "$stamp" "$dir/threads.jsonl.lock"
  AUTODREAM_DIR="$dir" "$THREADS" close t-00000001 >/dev/null 2>&1
  rc=$?
  assert_eq "$rc" 0 "lock older than 120 seconds is reclaimed"
}

for test_name in \
  test_threads_close_and_reopen \
  test_threads_state_write_is_atomic \
  test_threads_cli_refuses_unreadable_state \
  test_threads_list_computes_dropped \
  test_threads_missing_state_is_empty \
  test_threads_report_without_index_is_empty \
  test_threads_render_missing_index_uses_empty_validated_state \
  test_threads_renderer_reads_validated_state_from_stdin \
  test_threads_dashboard_singular_session_label \
  test_threads_resume_missing_index_is_clean \
  test_threads_rejects_null_session_as_unreadable_state \
  test_threads_renderer_rejects_malformed_session_record \
  test_threads_invalid_and_unknown_ids_are_refused \
  test_threads_search_treats_metacharacters_literally \
  test_threads_dropped_days_accepts_leading_zero \
  test_threads_environment_overrides_config \
  test_threads_reclaims_stale_lock; do
  "$test_name"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
