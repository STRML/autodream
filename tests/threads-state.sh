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

# Portable delete for test fixtures: /usr/bin/trash exists only on macOS, and CI runs Linux.
remove_path() { python3 -c 'import os,shutil,sys
p=sys.argv[1]
if os.path.isdir(p) and not os.path.islink(p): shutil.rmtree(p)
elif os.path.lexists(p): os.remove(p)' "$1"; }
cleanup() { remove_path "$TMP"; }
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
  remove_path "$shim/mktemp"
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

test_threads_dropped_status_has_one_contract() {
  local dir="$TMP/dropped-contract" old_date seven_date tie_date future_date before cli_status page_status report
  mkdir -p "$dir/dreams"
  old_date=$(pdate_shift "$AS_OF" -8 d) || return 1
  seven_date=$(pdate_shift "$AS_OF" -7 d) || return 1
  tie_date=$(pdate_shift "$AS_OF" -9 d) || return 1
  future_date=$(pdate_shift "$AS_OF" 2 d) || return 1
  jq -nc --arg old "$old_date" --arg seven "$seven_date" --arg tie "$tie_date" --arg future "$future_date" --arg seen "$AS_OF" '[
    {id:"t-10000001",kind:"work",repo:"/repo",title:"inconsistent last_seen",goal:"contract",sessions:[{date:$old,hash:"a",outcome:"not_achieved"}],status:"open",done_by:null,last_seen:$seen},
    {id:"t-10000002",kind:"work",repo:"/repo",title:"seven days",goal:"boundary",sessions:[{date:$seven,hash:"a",outcome:"not_achieved"}],status:"open",done_by:null,last_seen:$old},
    {id:"t-10000003",kind:"work",repo:"/repo",title:"same day tie",goal:"hash order",sessions:[{date:$tie,hash:"a",outcome:"not_achieved"},{date:$tie,hash:"z",outcome:"achieved"}],status:"open",done_by:null,last_seen:$old},
    {id:"t-10000004",kind:"work",repo:"/repo",title:"future history",goal:"historical cutoff",sessions:[{date:$old,hash:"a",outcome:"not_achieved"},{date:$future,hash:"z",outcome:"achieved"}],status:"open",done_by:null,last_seen:$future},
    {id:"t-10000005",kind:"work",repo:"/repo",title:"mostly achieved",goal:"quiet",sessions:[{date:$old,hash:"a",outcome:"mostly_achieved"}],status:"open",done_by:null,last_seen:$old},
    {id:"t-10000006",kind:"work",repo:"/repo",title:"closed by Sam",goal:"closed",sessions:[{date:$old,hash:"a",outcome:"not_achieved"}],status:"closed_by_sam",done_by:"sam",last_seen:$old}
  ] | .[]' > "$dir/threads.jsonl"
  before=$(cat "$dir/threads.jsonl")
  cli_status=$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq -r '.[] | select(.id == "t-10000001") | .status')
  AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" render >/dev/null 2>&1
  page_status=$(python3 - "$dir/dreams/threads.html" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = text.index("<script id=\"threads-data\" type=\"application/json\">")
start = text.index(">", start) + 1
end = text.index("</script>", start)
threads = json.loads(text[start:end])["threads"]
print(next(item["display_status"] for item in threads if item["id"] == "t-10000001"))
PY
)
  assert_eq "$cli_status" dropped "CLI uses latest session instead of inconsistent last_seen"
  assert_eq "$page_status" "$cli_status" "renderer shares the CLI dropped status"
  assert_eq "$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq -r '.[] | select(.id == "t-10000002") | .status')" open "seven day cutoff remains strict"
  assert_eq "$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq -r '.[] | select(.id == "t-10000003") | .status')" open "same-day tie selects the higher hash"
  assert_eq "$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq -r '.[] | select(.id == "t-10000005") | .status')" open "mostly achieved stays open"
  assert_eq "$(AUTODREAM_DIR="$dir" "$THREADS" list --json | jq -r '.[] | select(.id == "t-10000006") | .status')" closed_by_sam "operator close remains visible"
  report=$(AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" report "$AS_OF")
  case "$report" in *'`t-10000004`'*) ok "historical report ignores future sessions" ;; *) no "historical report ignores future sessions" ;; esac
  case "$report" in *'`t-10000001`'*) ok "CLI, renderer, and report include the same eligible dropped thread" ;; *) no "CLI, renderer, and report include the same eligible dropped thread" ;; esac
  assert_eq "$(cat "$dir/threads.jsonl")" "$before" "derived dropped status never changes stored bytes"
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

test_threads_report_removes_all_status_temps() {
  local dir="$TMP/report-temp-cleanup" report status_files
  mkdir -p "$dir/dreams" "$dir/tmp"
  seed "$dir"
  report=$(TMPDIR="$dir/tmp" AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" report "$AS_OF")
  status_files=$(find "$dir/tmp" -name 'threads-report-status.*' -type f -print)
  case "$report" in *'Dropped threads'*) ok "report succeeds before cleaning status temp" ;; *) no "report succeeds before cleaning status temp" ;; esac
  assert_eq "$status_files" "" "report removes its annotated state temp"
}

test_threads_direct_renderer_derives_dropped_status() {
  local dir="$TMP/render-raw-dropped" status
  mkdir -p "$dir"
  jq -nc '{id:"t-10000001",kind:"work",repo:"/repo",title:"unfinished in 2020",goal:"continue",sessions:[{date:"2020-01-01",hash:"a",outcome:"not_achieved"}],status:"open",done_by:null,last_seen:"2020-01-01"}' > "$dir/threads.jsonl"
  python3 "$REPO/bin/threads-render.py" "$dir/threads.jsonl" "$dir/threads.html" --as-of 2026-11-15 >/dev/null 2>&1
  status=$(python3 - "$dir/threads.html" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = text.index("<script id=\"threads-data\" type=\"application/json\">")
start = text.index(">", start) + 1
end = text.index("</script>", start)
threads = json.loads(text[start:end])["threads"]
print(threads[0]["display_status"])
PY
)
  assert_eq "$status" dropped "standalone renderer derives dropped status from raw JSONL"
}

test_threads_status_jq_is_bounded_at_all_entry_points() {
  local dir="$TMP/status-timeout" shim real_sleep real_jq output rc calls
  seed "$dir"
  shim="$TMP/status-timeout-bin"; mkdir -p "$shim"
  real_sleep=$(command -v sleep)
  real_jq=$(command -v jq)
  cat > "$shim/timeout" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$STATUS_TIMEOUT_CALLS"
shift
"$@" &
pid=$!
("$REAL_SLEEP" 0.1; kill -TERM "$pid" 2>/dev/null) &
watchdog=$!
wait "$pid"
rc=$?
kill "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null
[ "$rc" -ne 143 ] || exit 124
exit "$rc"
EOF
  cat > "$shim/jq" <<'EOF'
#!/bin/bash
case " $* " in
  *" -f "*) exec "$REAL_SLEEP" 5 ;;
esac
exec "$REAL_JQ" "$@"
EOF
  chmod +x "$shim/timeout" "$shim/jq"
  REAL_SLEEP="$real_sleep" REAL_JQ="$real_jq" STATUS_TIMEOUT_CALLS="$dir/calls" \
    PATH="$shim:$PATH" AUTODREAM_DIR="$dir" "$THREADS" list --json > "$dir/list.out" 2>&1
  rc=$?
  assert_eq "$rc" 1 "list fails when status jq exceeds its bound"
  grep -q 'timed out' "$dir/list.out" && ok "list reports status timeout clearly" || no "list reports status timeout clearly"
  REAL_SLEEP="$real_sleep" REAL_JQ="$real_jq" STATUS_TIMEOUT_CALLS="$dir/calls" \
    PATH="$shim:$PATH" AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" render > "$dir/render.out" 2>&1
  rc=$?
  assert_nonzero "$rc" "dashboard render fails when status jq exceeds its bound"
  grep -q 'timed out' "$dir/render.out" && ok "dashboard reports status timeout clearly" || no "dashboard reports status timeout clearly"
  REAL_SLEEP="$real_sleep" REAL_JQ="$real_jq" STATUS_TIMEOUT_CALLS="$dir/calls" \
    PATH="$shim:$PATH" AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" report "$AS_OF" > "$dir/report.out" 2>&1
  rc=$?
  assert_eq "$rc" 1 "report fails when status jq exceeds its bound"
  grep -q 'timed out' "$dir/report.out" && ok "report reports status timeout clearly" || no "report reports status timeout clearly"
  REAL_SLEEP="$real_sleep" REAL_JQ="$real_jq" STATUS_TIMEOUT_CALLS="$dir/calls" \
    PATH="$shim:$PATH" python3 "$REPO/bin/threads-render.py" "$dir/threads.jsonl" "$dir/direct.html" --as-of "$AS_OF" > "$dir/direct.out" 2>&1
  rc=$?
  assert_nonzero "$rc" "standalone renderer fails when status jq exceeds its bound"
  grep -q 'timed out' "$dir/direct.out" && ok "standalone renderer reports status timeout clearly" || no "standalone renderer reports status timeout clearly"
  calls=$(cat "$dir/calls" 2>/dev/null)
  assert_eq "$calls" "10
10
10
10" "each status jq call uses the ten-second bound"
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

test_threads_renderer_embeds_shared_assets() {
  local dir="$TMP/shared-assets" output
  seed "$dir"
  AUTODREAM_DIR="$dir" DREAMS_DIR="$dir/dreams" "$THREADS" render >/dev/null 2>&1
  output=$(python3 - "$dir/dreams/threads.html" "$REPO/web" <<'PY_ASSETS'
from html.parser import HTMLParser
from pathlib import Path
import sys
class Assets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.external = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if (tag == "script" and "src" in attrs) or (tag == "link" and "href" in attrs):
            self.external.append(tag)
page = Path(sys.argv[1]).read_text()
assets = Path(sys.argv[2])
parser = Assets()
parser.feed(page)
print("ok" if not parser.external and all((assets / name).read_text() in page
      for name in ("threads.js", "threads.css")) else "missing")
PY_ASSETS
)
  assert_eq "$output" ok "standalone page embeds the shared assets without external dependencies"
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
  touch -t 202001010000 "$dir/threads.jsonl.lock"
  AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 >/dev/null 2>&1
  assert_eq "$?" 0 "a stale old lock directory does not block a write"
  [ -d "$dir/threads.jsonl.lock" ] && ok "old directory is left untouched" || no "old directory is left untouched"
  [ -f "$dir/threads.jsonl.flock" ] && ok "new lock uses a persistent plain file" || no "new lock uses a persistent plain file"
}

test_threads_fresh_old_lock_directory_blocks_during_upgrade() {
  local dir="$TMP/old-lock-live" before output rc
  seed "$dir"
  mkdir "$dir/threads.jsonl.lock"
  before=$(cat "$dir/threads.jsonl")
  output=$(AUTODREAM_DIR="$dir" /bin/bash "$THREADS" close t-00000001 2>&1); rc=$?
  assert_eq "$rc" 1 "a writer from the older version still holding its lock blocks the write"
  assert_eq "$(cat "$dir/threads.jsonl")" "$before" "state is untouched while the old writer runs"
  case "$output" in *"older version"*) ok "the refusal names the old writer" ;; *) no "the refusal names the old writer" ;; esac
}

test_threads_status_write_sets_no_signal_trap() {
  # With a kernel flock, process death releases the lock. A trap that released it and let bash
  # continue would publish a stale copy after another writer took the lock.
  if grep -q 'trap ' "$THREADS"; then no "threads.sh installs no signal trap"; else ok "threads.sh installs no signal trap"; fi
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
  test_threads_dropped_status_has_one_contract \
  test_threads_missing_state_is_empty \
  test_threads_empty_state_is_empty \
  test_threads_report_without_index_is_empty \
  test_threads_report_removes_all_status_temps \
  test_threads_direct_renderer_derives_dropped_status \
  test_threads_status_jq_is_bounded_at_all_entry_points \
  test_threads_render_missing_index_uses_empty_validated_state \
  test_threads_renderer_reads_validated_state_from_stdin \
  test_threads_renderer_embeds_shared_assets \
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
  test_threads_fresh_old_lock_directory_blocks_during_upgrade \
  test_threads_status_write_sets_no_signal_trap \
  test_threads_missing_python_refuses_writes; do
  "$test_name"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
