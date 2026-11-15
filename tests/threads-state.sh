#!/bin/bash
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
THREADS="$REPO/bin/threads.sh"
PORTABLE="$REPO/bin/portable.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adt12.XXXXXX") || exit 1
export HOME="$TMP/home"
export DREAMS_DIR="$TMP/dreams"
mkdir -p "$HOME" "$DREAMS_DIR"
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

test_threads_empty_state_is_empty() {
  local dir="$TMP/zero-byte" output rc
  mkdir -p "$dir"
  : > "$dir/threads.jsonl"
  output=$(AUTODREAM_DIR="$dir" "$THREADS" list --json 2>/dev/null)
  rc=$?
  assert_eq "$rc" 0 "zero-byte index is readable"
  assert_eq "$(printf '%s' "$output" | jq 'length')" 0 "zero-byte index reads as empty"
}

test_threads_renderer_uses_hash_tie_breaker() {
  local dir="$TMP/render-tie" cli_status page_status
  mkdir -p "$dir"
  jq -cn '{id:"t-00000009",kind:"work",repo:"/repo",title:"tie",goal:"tie",sessions:[{date:"2000-01-01",hash:"a",outcome:"not_achieved"},{date:"2000-01-01",hash:"z",outcome:"achieved"}],status:"open",done_by:null,last_seen:"2000-01-01"}' > "$dir/threads.jsonl"
  cli_status=$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq -r '.[0].status')
  AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" render >/dev/null 2>&1
  page_status=$(python3 - "$dir/dreams/threads.html" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = text.index("<script id=\"threads-data\" type=\"application/json\">")
start = text.index(">", start) + 1
end = text.index("</script>", start)
print(json.loads(text[start:end])["threads"][0]["display_status"])
PY
)
  assert_eq "$cli_status" open "CLI selects the higher hash on a same-day tie"
  assert_eq "$page_status" "$cli_status" "dashboard uses the CLI same-day tie order"
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

wait_for_gate() {
  local marker=$1 tries=0
  while [ ! -e "$marker" ] && [ "$tries" -lt 200 ]; do sleep 0.05; tries=$((tries + 1)); done
  [ -e "$marker" ]
}

start_lock_holder() {
  local dir=$1
  mkfifo "$dir/release"
  AUTODREAM_DIR="$dir" /bin/bash -c '
    . "$1" list --json >/dev/null || exit 1
    threads_acquire_lock || exit 1
    : > "$2/ready"
    read -r release < "$2/release"
    threads_release_lock
    : > "$2/released"
    read -r finish < "$2/release"
  ' holder "$THREADS" "$dir" > "$dir/holder.out" 2>&1 &
  HOLDER=$!
  wait_for_gate "$dir/ready"
}

probe_lock() {
  python3 - "$1/threads.jsonl.flock" <<'PY_PROBE'
import fcntl, sys
with open(sys.argv[1], "a") as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(1)
PY_PROBE
}

test_threads_flock_excludes_until_release() {
  local dir="$TMP/held-lock" rc before started
  seed "$dir"
  start_lock_holder "$dir" || { no "holder acquires lock"; kill "$HOLDER"; wait "$HOLDER" 2>/dev/null; return; }
  before=$(cat "$dir/threads.jsonl")
  probe_lock "$dir"
  assert_eq "$?" 1 "another process cannot acquire the held kernel lock"
  started=$SECONDS
  AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 > "$dir/close.out" 2>&1
  rc=$?
  assert_eq "$rc" 1 "CLI fails when the retry budget is spent"
  [ "$((SECONDS - started))" -ge 3 ] && ok "retry budget waits at least three seconds" || no "retry budget waits at least three seconds"
  grep -q 'lock is held' "$dir/close.out" && ok "lock refusal is loud" || no "lock refusal is loud"
  assert_eq "$(cat "$dir/threads.jsonl")" "$before" "refused writer preserves state"
  printf 'release\n' > "$dir/release"
  wait_for_gate "$dir/released" || no "holder closes its descriptor"
  [ -f "$dir/threads.jsonl.flock" ] && ok "release leaves the lock file in place" || no "release leaves the lock file in place"
  probe_lock "$dir"
  assert_eq "$?" 0 "another process acquires immediately after release"
  AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 >/dev/null 2>&1
  assert_eq "$?" 0 "CLI can write after release"
  assert_eq "$(state_json "$dir" t-00000001 | jq -r .status)" closed_by_sam "released lock permits publication"
  [ -f "$dir/threads.jsonl.flock" ] && ok "lock file remains after CLI publication" || no "lock file remains after CLI publication"
  printf 'finish\n' > "$dir/release"
  wait "$HOLDER"
}

test_threads_sigkill_releases_flock_immediately() {
  local dir="$TMP/killed-lock"
  seed "$dir"
  start_lock_holder "$dir" || { no "holder acquires lock"; kill "$HOLDER"; wait "$HOLDER" 2>/dev/null; return; }
  probe_lock "$dir"
  assert_eq "$?" 1 "holder owns the kernel lock before SIGKILL"
  kill -KILL "$HOLDER"
  wait "$HOLDER" 2>/dev/null || true
  probe_lock "$dir"
  assert_eq "$?" 0 "SIGKILL releases immediately without retry or reclaim"
  AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 >/dev/null 2>&1
  assert_eq "$?" 0 "CLI writes after a killed holder"
}

test_threads_old_lock_directory_does_not_block() {
  local dir="$TMP/old-lock"
  seed "$dir"
  mkdir "$dir/threads.jsonl.lock"
  AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 >/dev/null 2>&1
  assert_eq "$?" 0 "old lock directory does not block a write"
  [ -d "$dir/threads.jsonl.lock" ] && ok "old directory is left untouched" || no "old directory is left untouched"
  [ -f "$dir/threads.jsonl.flock" ] && ok "new lock uses a persistent plain file" || no "new lock uses a persistent plain file"
}

test_threads_missing_python_refuses_writes() {
  local dir="$TMP/no-python" tool before output rc
  seed "$dir"
  mkdir "$dir/bin"
  for tool in dirname readlink jq cat mktemp mkdir date stat; do
    ln -s "$(command -v "$tool")" "$dir/bin/$tool"
  done
  before=$(cat "$dir/threads.jsonl")
  output=$(PATH="$dir/bin" AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 2>&1)
  rc=$?
  assert_eq "$rc" 1 "missing python3 refuses CLI writes"
  case "$output" in *"python3 is required"*) ok "missing python3 is loud" ;; *) no "missing python3 is loud ($output)" ;; esac
  assert_eq "$(cat "$dir/threads.jsonl")" "$before" "missing python3 preserves state"
  output=$(PATH="$dir/bin" AUTODREAM_DIR="$dir" /bin/bash "$THREADS" update 2020-01-02 </dev/null 2>&1)
  printf '%s\n' "$output" | grep -q '^threads_skipped: locked$' && ok "nightly discloses missing lock support" || no "nightly discloses missing lock support ($output)"
}

for test_name in \
  test_threads_close_and_reopen \
  test_threads_state_write_is_atomic \
  test_threads_cli_refuses_unreadable_state \
  test_threads_list_computes_dropped \
  test_threads_missing_state_is_empty \
  test_threads_empty_state_is_empty \
  test_threads_report_without_index_is_empty \
  test_threads_render_missing_index_uses_empty_validated_state \
  test_threads_renderer_reads_validated_state_from_stdin \
  test_threads_dashboard_singular_session_label \
  test_threads_resume_missing_index_is_clean \
  test_threads_rejects_null_session_as_unreadable_state \
  test_threads_renderer_rejects_malformed_session_record \
  test_threads_renderer_uses_hash_tie_breaker \
  test_threads_invalid_and_unknown_ids_are_refused \
  test_threads_search_treats_metacharacters_literally \
  test_threads_dropped_days_accepts_leading_zero \
  test_threads_environment_overrides_config \
  test_threads_flock_excludes_until_release \
  test_threads_sigkill_releases_flock_immediately \
  test_threads_old_lock_directory_does_not_block \
  test_threads_missing_python_refuses_writes; do
  "$test_name"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
