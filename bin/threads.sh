#!/bin/bash
set -uo pipefail

THREADS_SRC=${BASH_SOURCE[0]}
THREADS_DIR=$(cd "$(dirname "$THREADS_SRC")" 2>/dev/null && pwd -P)
if [ -r "$THREADS_DIR/lib-install-dir.sh" ]; then
  THREADS_LIB_DIR=$THREADS_DIR
else
  THREADS_LIB_DIR=$(dirname "$(readlink "$THREADS_SRC" 2>/dev/null || echo "$THREADS_SRC")")
fi

# shellcheck source=/dev/null
. "$THREADS_LIB_DIR/lib-install-dir.sh" || exit 1
resolve_install_dir "$THREADS_SRC" threads.sh

# shellcheck source=/dev/null
. "$THREADS_LIB_DIR/portable.sh" || exit 1
. "$THREADS_LIB_DIR/adapters.sh" || exit 1

CONFIG_FILE=${AUTODREAM_CONFIG:-$AUTODREAM_DIR/config}
if [ -f "$CONFIG_FILE" ]; then
  THREADS_INSTALL_DIR=$AUTODREAM_DIR
  THREADS_ENV_SNAPSHOT=$(export -p)
  set +u
  set -a
  # shellcheck source=/dev/null
  . "$CONFIG_FILE" 2>/dev/null || true
  set +a
  set -u
  eval "$THREADS_ENV_SNAPSHOT" 2>/dev/null || true
  unset THREADS_ENV_SNAPSHOT
  AUTODREAM_DIR=$THREADS_INSTALL_DIR
  unset THREADS_INSTALL_DIR
fi

STATE=${AUTODREAM_THREADS_STATE:-$AUTODREAM_DIR/threads.jsonl}
LOCK="$STATE.lock"
DROPPED_DAYS=${AUTODREAM_THREADS_DROPPED_DAYS:-7}

threads_error() { printf 'threads: %s\n' "$1" >&2; }

threads_valid_days() {
  case "$1" in ''|*[!0-9]*|??????????*) return 1 ;; esac
  [ "$((10#$1))" -gt 0 ] 2>/dev/null
}

threads_read_state() {
  if [ ! -e "$STATE" ]; then
    printf '[]\n'
    return 0
  fi
  if [ ! -f "$STATE" ] || [ ! -r "$STATE" ] || [ ! -s "$STATE" ]; then
    threads_error "cannot read valid state at $STATE"
    return 1
  fi
  if ! jq -e -s '
    all(.[];
      type == "object" and
      (.id | type == "string" and test("^t-[0-9a-f]{8}$")) and
      (.kind | type == "string" and ( . == "work" or . == "idea")) and
      (.repo | type == "string") and
      (.title | type == "string") and
      (.goal | type == "string") and
      (.sessions | type == "array") and
      (.status | type == "string" and ( . == "open" or . == "done" or . == "closed_by_sam")) and
      (.done_by == null or (.done_by | type == "string")) and
      (.last_seen | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
    ) and
    ([.[].id] | length == (unique | length))
  ' "$STATE" >/dev/null 2>&1; then
    threads_error "malformed state at $STATE"
    return 1
  fi
  jq -cs '.' "$STATE"
}

threads_acquire_lock() {
  local attempts=0 lock_mtime now age
  while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -d "$LOCK" ]; then
      lock_mtime=$(pstat_mtime "$LOCK") || lock_mtime=""
      now=$(pdate_epoch "$(date '+%Y-%m-%d %H:%M:%S')") || now=""
      if [ -n "$lock_mtime" ] && [ -n "$now" ]; then
        age=$((now - lock_mtime))
        if [ "$age" -gt 120 ]; then
          rmdir "$LOCK" 2>/dev/null || true
          continue
        fi
      fi
    fi
    if [ "$attempts" -ge 3 ]; then
      threads_error "lock is held at $LOCK"
      return 1
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  return 0
}

threads_release_lock() { rmdir "$LOCK" 2>/dev/null || true; }

threads_write_state() {
  local next_file=$1 temp_file
  temp_file=$(mktemp "$STATE.XXXXXX" 2>/dev/null) || return 1
  if cat "$next_file" > "$temp_file" 2>/dev/null && mv -f "$temp_file" "$STATE" 2>/dev/null; then
    return 0
  fi
  unlink "$temp_file" 2>/dev/null || true
  return 1
}

threads_is_dropped() {
  local as_of=$1 last_seen=$2 status=$3 outcome=$4 cutoff cutoff_epoch last_seen_epoch
  [ "$status" = open ] || return 1
  case "$outcome" in not_achieved|partially_achieved|unclear_from_transcript) ;; *) return 1 ;; esac
  cutoff=$(pdate_shift "$as_of" "-$DROPPED_DAYS" d) || return 1
  cutoff_epoch=$(pdate_epoch "$cutoff") || return 1
  last_seen_epoch=$(pdate_epoch "$last_seen") || return 1
  [ "$last_seen_epoch" -lt "$cutoff_epoch" ]
}

threads_annotate() {
  local as_of=$1
  local thread last_seen outcome status
  jq -c '.[]' | while IFS= read -r thread; do
    last_seen=$(printf '%s\n' "$thread" | jq -r '.last_seen')
    outcome=$(printf '%s\n' "$thread" | jq -r '(.sessions | sort_by(.date) | last // {}).outcome // empty')
    status=$(printf '%s\n' "$thread" | jq -r '.status')
    if threads_is_dropped "$as_of" "$last_seen" "$status" "$outcome"; then
      printf '%s\n' "$thread" | jq -c '.status = "dropped"'
    else
      printf '%s\n' "$thread"
    fi
  done | jq -cs '.'
}

threads_json_output() { jq -c '.'; }

threads_list() {
  local status_filter="" kind_filter="" repo_filter="" json=0 arg as_of state
  while [ "$#" -gt 0 ]; do
    arg=$1; shift
    case "$arg" in
      --status) [ "$#" -gt 0 ] || { threads_error "--status needs a value"; return 2; }; status_filter=$1; shift ;;
      --kind) [ "$#" -gt 0 ] || { threads_error "--kind needs a value"; return 2; }; kind_filter=$1; shift ;;
      --repo) [ "$#" -gt 0 ] || { threads_error "--repo needs a value"; return 2; }; repo_filter=$1; shift ;;
      --json) json=1 ;;
      *) threads_error "unknown list option: $arg"; return 2 ;;
    esac
  done
  if [ -n "$status_filter" ] && [ "$status_filter" != open ] && [ "$status_filter" != done ] && [ "$status_filter" != closed_by_sam ] && [ "$status_filter" != dropped ]; then
    threads_error "invalid status: $status_filter"
    return 2
  fi
  if [ -n "$kind_filter" ] && [ "$kind_filter" != work ] && [ "$kind_filter" != idea ]; then
    threads_error "invalid kind: $kind_filter"
    return 2
  fi
  threads_valid_days "$DROPPED_DAYS" || { threads_error "invalid AUTODREAM_THREADS_DROPPED_DAYS"; return 2; }
  DROPPED_DAYS=$((10#$DROPPED_DAYS))
  state=$(threads_read_state) || return 1
  as_of=$(pdate_shift "$(pdate_yesterday)" 1 d) || { threads_error "cannot determine current date"; return 1; }
  state=$(printf '%s\n' "$state" | threads_annotate "$as_of") || return 1
  printf '%s\n' "$state" | jq -c --arg status "$status_filter" --arg kind "$kind_filter" --arg repo "$repo_filter" '
    map(select(($status == "" or .status == $status) and
               ($kind == "" or .kind == $kind) and
               ($repo == "" or .repo == $repo)))
  ' | if [ "$json" -eq 1 ]; then cat; else jq -r '.[] | "\(.id)\t\(.status)\t\(.kind)\t\(.repo)\t\(.title)"'; fi
}

threads_search() {
  local query=$1 json=0 arg state as_of
  shift
  while [ "$#" -gt 0 ]; do
    arg=$1; shift
    case "$arg" in --json) json=1 ;; *) threads_error "unknown search option: $arg"; return 2 ;; esac
  done
  threads_valid_days "$DROPPED_DAYS" || { threads_error "invalid AUTODREAM_THREADS_DROPPED_DAYS"; return 2; }
  DROPPED_DAYS=$((10#$DROPPED_DAYS))
  state=$(threads_read_state) || return 1
  as_of=$(pdate_shift "$(pdate_yesterday)" 1 d) || { threads_error "cannot determine current date"; return 1; }
  state=$(printf '%s\n' "$state" | threads_annotate "$as_of") || return 1
  printf '%s\n' "$state" | jq -c --arg query "$query" '
    map(select([.id, .kind, .repo, .title, .goal, .status] | any(contains($query))))
  ' | if [ "$json" -eq 1 ]; then cat; else jq -r '.[] | "\(.id)\t\(.status)\t\(.kind)\t\(.repo)\t\(.title)"'; fi
}

threads_set_status() {
  local id=$1 status=$2 current_state next_file rc=0
  case "$id" in t-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) threads_error "invalid thread id: $id"; return 2 ;; esac
  mkdir -p "$(dirname "$STATE")" || { threads_error "cannot create state directory"; return 1; }
  threads_acquire_lock || return 1
  trap 'threads_release_lock' EXIT HUP INT TERM
  current_state=$(threads_read_state) || { threads_release_lock; trap - EXIT HUP INT TERM; return 1; }
  if ! printf '%s\n' "$current_state" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
    threads_error "unknown thread id: $id"
    threads_release_lock
    trap - EXIT HUP INT TERM
    return 1
  fi
  next_file=$(mktemp "${TMPDIR:-/tmp}/threads-next.XXXXXX") || { threads_release_lock; trap - EXIT HUP INT TERM; return 1; }
  if ! printf '%s\n' "$current_state" | jq -c --arg id "$id" --arg status "$status" '
    map(if .id == $id then
      if $status == "closed_by_sam" then .status = $status | .done_by = "sam"
      else .status = $status | del(.done_by)
      end
    else . end)
  ' | jq -c '.[]' > "$next_file"; then
    unlink "$next_file" 2>/dev/null || true
    threads_release_lock
    trap - EXIT HUP INT TERM
    return 1
  fi
  if ! threads_write_state "$next_file"; then
    threads_error "cannot atomically write $STATE"
    rc=1
  fi
  unlink "$next_file" 2>/dev/null || true
  threads_release_lock
  trap - EXIT HUP INT TERM
  return "$rc"
}

threads_valid_date() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) pdate_epoch "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

threads_cwd_allowed() {
  case "$1" in
    /*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    /tmp|/tmp/*|/private/tmp|/private/tmp/*) return 1 ;;
  esac
  case "$1" in
    "${TMPDIR:-/tmp}"|"${TMPDIR:-/tmp}"/*) return 1 ;;
  esac
  case "/$1/" in */scratchpad/*) return 1 ;; esac
  return 0
}

threads_refresh_has() {
  awk -F '\t' -v d="$1" -v h="$2" '($1 "") == (d "") && ("x" $2) == ("x" h) { found = 1 } END { exit !found }' \
    <<EOF_REFRESH
${THREADS_REFRESH_KEYS:-}
EOF_REFRESH
}

threads_collect_candidates() {
  local source_file=$1 state_json=$2 candidates_file=$3 unmeasured=0
  local seen_file="$candidates_file.seen" line date hash source path cwd repo nested count measured
  local findings facet goal outcome kind handle linked refresh
  : > "$candidates_file" || return 1
  : > "$seen_file" || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line" | jq -s -e 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 || continue
    date=$(printf '%s\n' "$line" | jq -r '.date // empty')
    hash=$(printf '%s\n' "$line" | jq -r '.hash // empty')
    source=$(printf '%s\n' "$line" | jq -r '.source // empty')
    path=$(printf '%s\n' "$line" | jq -r '.session_path // empty')
    cwd=$(printf '%s\n' "$line" | jq -r '.cwd // empty')
    repo=$(printf '%s\n' "$line" | jq -r '.repo // empty')
    nested=$(printf '%s\n' "$line" | jq -r '.nested // false')
    count=$(printf '%s\n' "$line" | jq -r '.user_message_count // 0')
    measured=$(printf '%s\n' "$line" | jq -r '.measured // false')
    threads_valid_date "$date" || continue
    case "$hash" in
      [0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]) ;;
      *) continue ;;
    esac
    threads_cwd_allowed "$cwd" || continue
    if [ "$measured" != true ]; then
      unmeasured=$((unmeasured + 1))
      continue
    fi
    [ "$nested" = false ] || continue
    case "$count" in ''|*[!0-9]*) continue ;; esac
    [ "$count" -ge 2 ] || continue
    [ -n "$path" ] || continue
    handle="$date:$hash"
    grep -Fqx "$handle" "$seen_file" && continue
    printf '%s\n' "$handle" >> "$seen_file"
    findings="$AUTODREAM_DIR/findings/$date/$hash.json"
    jq -s -e 'length == 1 and (.[0] | type == "object" and (.findings | type == "array") and (has("error") | not) and (.no_engine != true))' \
      "$findings" >/dev/null 2>&1 || continue
    facet=$(jq -c '
      def clean: gsub("[\\x00-\\x1F\\x7F]"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "");
      . as $f
      | (if (($f.underlying_goal | type) == "string" and ($f.underlying_goal | clean | length) > 0)
         then {goal:($f.underlying_goal | clean), kind:"work"}
         else
           (if ($f.notable_initiatives | type) == "array" then $f.notable_initiatives[0]
            elif ($f.notable_initiatives | type) == "string" then $f.notable_initiatives
            else empty end) as $idea
           | if ($idea | type) == "string" and ($idea | clean | length) > 0
             then {goal:($idea | clean), kind:"idea"} else empty end
         end)
      + {outcome:(if ($f.outcome | type) == "string" then $f.outcome else "" end)}
      | select(.outcome | IN("fully_achieved", "mostly_achieved", "partially_achieved", "not_achieved", "unclear_from_transcript"))
    ' "$findings" 2>/dev/null) || facet=""
    [ -n "$facet" ] || continue
    goal=$(printf '%s\n' "$facet" | jq -r '.goal')
    kind=$(printf '%s\n' "$facet" | jq -r '.kind')
    outcome=$(printf '%s\n' "$facet" | jq -r '.outcome')
    linked=$(printf '%s\n' "$state_json" | jq -e --arg d "$date" --arg h "$hash" \
      'any(.[]; any(.sessions[]?; .date == $d and .hash == $h))' >/dev/null 2>&1 && echo yes || echo no)
    refresh=$(threads_refresh_has "$date" "$hash" && echo yes || echo no)
    [ "$linked" != yes ] || [ "$refresh" = yes ] || continue
    jq -cn --arg handle "$handle" --arg date "$date" --arg hash "$hash" --arg source "$source" \
      --arg path "$path" --arg cwd "$cwd" --arg repo "$repo" --arg kind "$kind" \
      --arg goal "$goal" --arg outcome "$outcome" \
      '{handle:$handle,date:$date,hash:$hash,source:$source,session_path:$path,cwd:$cwd,repo:$repo,kind:$kind,goal:$goal,outcome:$outcome}' \
      >> "$candidates_file" || return 1
  done < "$source_file"
  rm -f "$seen_file"
  printf '%s' "$unmeasured"
}

threads_prompt_path() {
  local p
  for p in "$THREADS_LIB_DIR/../prompts/THREAD_LINKER.md" "$AUTODREAM_DIR/THREAD_LINKER.md"; do
    [ -r "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

threads_call_linker() {
  local request_file=$1 response_file=$2 engine=$3 model=$4 timeout_bin=$5 timeout_s=$6
  local rc line argc=0
  local -a argv=() envs=()
  [ -n "$timeout_bin" ] || { threads_error "linker skipped because no timeout binary is available"; return 1; }
  while IFS= read -r -d '' line; do argv+=("$line"); argc=$((argc + 1)); done < <(adapter_run "$engine" threads-argv "$model" 2>/dev/null)
  while IFS= read -r line; do [ -n "$line" ] && envs+=("$line"); done < <(adapter_run "$engine" l1-env 2>/dev/null)
  [ "$argc" -gt 0 ] || { threads_error "adapter $engine did not provide threads-argv"; return 1; }
  mkdir -p "$AUTODREAM_DIR/work" || { threads_error "cannot create linker work directory"; return 1; }
  if ( cd "$AUTODREAM_DIR/work" && env ${envs[@]+"${envs[@]}"} "$timeout_bin" -k 30 "$timeout_s" "${argv[@]}" ) \
       < "$request_file" > "$response_file" 2> "$response_file.err"; then
    return 0
  else
    rc=$?
  fi
  threads_error "linker call failed on $engine (exit $rc): $(head -c 240 "$response_file.err" 2>/dev/null | tr '\n' ' ')"
  return 1
}

threads_validate_response() {
  local candidates_file=$1 state_json=$2 response_file=$3 valid_file=$4 rejected_file=$5 unusable_file=$6
  python3 - "$candidates_file" "$state_json" "$response_file" "$valid_file" "$rejected_file" "$unusable_file" <<'PY'
import json
import re
import sys

candidates_path, state_text, response_path, valid_path, rejected_path, unusable_path = sys.argv[1:]
candidates = {}
with open(candidates_path, encoding="utf-8") as stream:
    for line in stream:
        if line.strip():
            item = json.loads(line)
            candidates[item["handle"]] = item
state = json.loads(state_text)
thread_ids = {item["id"] for item in state}
parsed = []
handle_counts = {}
rejected = 0
for line in open(response_path, encoding="utf-8"):
    if not line.strip():
        continue
    try:
        item = json.loads(line)
    except (ValueError, TypeError):
        rejected += 1
        continue
    if not isinstance(item, dict):
        rejected += 1
        continue
    handle = item.get("hash")
    if isinstance(handle, str) and handle in candidates:
        handle_counts[handle] = handle_counts.get(handle, 0) + 1
    parsed.append(item)

valid = []
for item in parsed:
    handle = item.get("hash")
    thread = item.get("thread")
    title = item.get("title")
    finished = item.get("finished")
    if (not isinstance(handle, str) or handle not in candidates
            or handle_counts.get(handle, 0) != 1
            or set(item) - {"hash", "thread", "title", "finished"}
            or not isinstance(thread, str)
            or (thread != "new" and (not re.fullmatch(r"t-[0-9a-f]{8}", thread) or thread not in thread_ids))
            or not isinstance(finished, bool)
            or ("title" in item and not isinstance(title, str))):
        rejected += 1
        continue
    valid.append(item)
with open(valid_path, "w", encoding="utf-8") as stream:
    for item in valid:
        stream.write(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n")
with open(rejected_path, "w", encoding="ascii") as stream:
    stream.write(str(rejected))
with open(unusable_path, "w", encoding="ascii") as stream:
    stream.write("1" if not parsed else "0")
PY
}

threads_prepare_requests() {
  local candidates_file=$1 groups_dir=$2 groups_file=$3 all_file=$4
  python3 - "$candidates_file" "$groups_dir" "$groups_file" "$all_file" <<'PY'
import json
import os
import sys

candidates_path, groups_dir, groups_path, all_path = sys.argv[1:]
items = []
with open(candidates_path, encoding="utf-8") as stream:
    for line in stream:
        if line.strip():
            item = json.loads(line)
            items.append({"hash": item["handle"], "date": item["date"], "kind": item["kind"],
                          "repo": item["repo"], "goal": item["goal"], "outcome": item["outcome"]})
items.sort(key=lambda item: (item["date"], item["hash"]))
with open(all_path, "w", encoding="utf-8") as stream:
    json.dump(items, stream, ensure_ascii=False, separators=(",", ":"))
os.makedirs(groups_dir, exist_ok=True)
groups = {}
for item in items:
    groups.setdefault(item["repo"], []).append(item)
with open(groups_path, "w", encoding="utf-8") as stream:
    for index, repo in enumerate(sorted(groups), 1):
        path = os.path.join(groups_dir, "group-%04d.json" % index)
        with open(path, "w", encoding="utf-8") as group_stream:
            json.dump(groups[repo], group_stream, ensure_ascii=False, separators=(",", ":"))
        stream.write(path + "\n")
PY
}

threads_write_linker_input() {
  local date=$1 state_json=$2 candidates_json=$3 prompt=$4 request_json_file=$5 input_file=$6 cutoff request
  cutoff=$(pdate_shift "$date" -90 d) || return 1
  jq -cn --arg date "$date" --arg cutoff "$cutoff" --slurpfile state <(printf '%s\n' "$state_json") \
    --slurpfile candidates "$candidates_json" '
      {date:$date,
       threads:[$state[0][] | if (.status == "open" and .last_seen >= $cutoff)
                then {id,title,repo,goal,last_seen}
                elif (.status == "done" or .status == "closed_by_sam") then {id,title,repo}
                else empty end],
       candidates:$candidates[0]}
    ' > "$request_json_file" || return 1
  {
    printf 'AUTODREAM_THREADS_LINKER\n'
    cat "$prompt"
    printf '\nAUTODREAM_THREADS_REQUEST\n'
    cat "$request_json_file"
    printf '\n'
  } > "$input_file" || return 1
  return 0
}

threads_select_candidate_rows() {
  local candidates_json=$1 candidates_file=$2 selected_file=$3
  python3 - "$candidates_json" "$candidates_file" "$selected_file" <<'PY'
import json
import sys

request_path, candidates_path, output_path = sys.argv[1:]
handles = {item["hash"] for item in json.load(open(request_path, encoding="utf-8"))}
with open(output_path, "w", encoding="utf-8") as output:
    for line in open(candidates_path, encoding="utf-8"):
        if line.strip():
            item = json.loads(line)
            if item["handle"] in handles:
                output.write(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
}

threads_merge_assignments() {
  local state_file=$1 candidates_file=$2 assignments_file=$3 output_file=$4 result_file=$5
  python3 - "$state_file" "$candidates_file" "$assignments_file" "$output_file" "$result_file" <<'PY'
import hashlib
import json
import re
import sys
import unicodedata

state_path, candidates_path, assignments_path, output_path, result_path = sys.argv[1:]
state = []
for line in open(state_path, encoding="utf-8"):
    if line.strip():
        state.append(json.loads(line))
candidates = {}
for line in open(candidates_path, encoding="utf-8"):
    if line.strip():
        item = json.loads(line)
        candidates[item["handle"]] = item
assignments = [json.loads(line) for line in open(assignments_path, encoding="utf-8") if line.strip()]
by_id = {item["id"]: item for item in state}
linked = rejected = close_refused = 0

def source_key(session):
    return session.get("date"), session.get("hash")

def safe_title(value, fallback):
    if not isinstance(value, str):
        value = fallback
    value = "".join(char for char in value if unicodedata.category(char) != "Cc")[:120].strip()
    return value or fallback[:120]

def new_id(candidate):
    seed = candidate["handle"]
    salt = 0
    while True:
        material = seed if salt == 0 else "%s:%d" % (seed, salt)
        ident = "t-" + hashlib.sha1(material.encode("utf-8")).hexdigest()[:8]
        existing = by_id.get(ident)
        if existing is None or not existing.get("sessions") or any(
                source_key(s) == (candidate["date"], candidate["hash"])
                for s in existing.get("sessions", [])):
            return ident
        salt += 1

for assignment in assignments:
    candidate = candidates.get(assignment["hash"])
    if candidate is None:
        rejected += 1
        continue
    date = candidate["date"]
    hash_value = candidate["hash"]
    for item in state:
        item["sessions"] = [s for s in item.get("sessions", []) if source_key(s) != (date, hash_value)]
    by_id = {item["id"]: item for item in state}
    if assignment["thread"] == "new":
        ident = new_id(candidate)
        thread = by_id.get(ident)
        if thread is None:
            thread = {"id": ident, "kind": candidate["kind"], "repo": candidate["repo"],
                     "title": safe_title(assignment.get("title"), candidate["goal"]),
                     "goal": candidate["goal"], "sessions": [], "status": "open",
                     "done_by": None, "last_seen": date}
            state.append(thread)
            by_id[ident] = thread
    else:
        ident = assignment["thread"]
        thread = by_id.get(ident)
        if thread is None:
            rejected += 1
            continue
    before_last_seen = max([s.get("date", "") for s in thread.get("sessions", [])] + [thread.get("last_seen", "")])
    if date >= before_last_seen:
        thread["goal"] = candidate["goal"]
        thread["title"] = safe_title(assignment.get("title"), candidate["goal"])
    if not thread.get("repo") and candidate["repo"]:
        thread["repo"] = candidate["repo"]
    session = {"date": date, "hash": hash_value, "session_path": candidate["session_path"],
               "outcome": candidate["outcome"]}
    thread.setdefault("sessions", []).append(session)
    thread["sessions"].sort(key=lambda item: (item.get("date", ""), item.get("hash", "")))
    thread["last_seen"] = max([s.get("date", "") for s in thread["sessions"]] + [thread.get("last_seen", "")])
    if assignment["finished"]:
        if candidate["outcome"] in ("fully_achieved", "mostly_achieved"):
            if thread["status"] == "open":
                thread["status"] = "done"
                thread["done_by"] = "linker"
        else:
            close_refused += 1
    linked += 1

state = [item for item in state if item.get("sessions") or item.get("status") != "open"]
state.sort(key=lambda item: item["id"])
with open(output_path, "w", encoding="utf-8") as output:
    for item in state:
        output.write(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n")
with open(result_path, "w", encoding="ascii") as output:
    output.write("%d %d %d" % (linked, rejected, close_refused))
PY
}

threads_cleanup_tmp() {
  local path=$1
  if command -v trash >/dev/null 2>&1; then
    trash "$path" >/dev/null 2>&1 && return 0
  fi
  [ -e "$path" ] || return 0
  find "$path" -depth -type f -exec unlink {} \; 2>/dev/null
  find "$path" -depth -type d -exec rmdir {} \; 2>/dev/null
}

threads_emit_stats() {
  printf 'threads_state: %s\n' "$1"
  printf 'threads_link: %s\n' "$2"
  printf 'threads_linked: %s\n' "$3"
  printf 'threads_rejected: %s\n' "$4"
  printf 'threads_close_refused: %s\n' "$5"
  printf 'threads_unmeasured: %s\n' "$6"
  printf 'threads_calls: %s\n' "$7"
  [ -z "${8:-}" ] || printf 'threads_skipped: %s\n' "$8"
}

threads_warn_unreadable() {
  local date=$1
  threads_error "state is unreadable; refusing to link or rewrite $STATE"
  if [ -x "$AUTODREAM_DIR/notify.sh" ]; then
    "$AUTODREAM_DIR/notify.sh" --warning "$date" "The dropped threads index could not be read. It was left unchanged and linking was skipped." threads \
      >/dev/null 2>&1 || true
  fi
}

threads_update() {
  local date=$1 tmp source_file state_json state_file candidates_file unmeasured prompt engine model timeout_s max_input timeout_bin
  local all_candidates groups_dir groups_file request_list request_candidates group_candidates request_json input_file response_file valid_file rejected_file unusable_file assignments_file
  local failed=0 rejected=0 close_refused=0 linked=0 calls=0 skipped="" link_status=not_needed size unusable index group rc merge_rejected
  threads_valid_date "$date" || { threads_error "invalid update date: $date"; return 2; }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/threads-update.XXXXXX" 2>/dev/null) || {
    threads_emit_stats ok failed 0 0 0 0 0
    return 0
  }
  source_file="$tmp/source.jsonl"
  state_file="$tmp/state.jsonl"
  assignments_file="$tmp/assignments.jsonl"
  : > "$assignments_file"
  cat > "$source_file" || {
    threads_cleanup_tmp "$tmp"
    threads_emit_stats ok failed 0 0 0 0 0
    return 0
  }
  if ! state_json=$(threads_read_state); then
    threads_warn_unreadable "$date"
    threads_cleanup_tmp "$tmp"
    threads_emit_stats unreadable failed 0 0 0 0 0
    return 0
  fi
  printf '%s\n' "$state_json" | jq -c '.[]' > "$state_file" || {
    threads_warn_unreadable "$date"
    threads_cleanup_tmp "$tmp"
    threads_emit_stats unreadable failed 0 0 0 0 0
    return 0
  }
  unmeasured=$(threads_collect_candidates "$source_file" "$state_json" "$tmp/candidates.jsonl") || unmeasured=0
  case "$unmeasured" in ''|*[!0-9]*) unmeasured=0 ;; esac
  candidates_file="$tmp/candidates.sorted.jsonl"
  if ! python3 - "$tmp/candidates.jsonl" "$candidates_file" <<'PY_SORT'
import json
import sys
source, destination = sys.argv[1:]
items = [json.loads(line) for line in open(source, encoding="utf-8") if line.strip()]
items.sort(key=lambda item: (item["date"], item["hash"]))
with open(destination, "w", encoding="utf-8") as output:
    for item in items:
        output.write(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n")
PY_SORT
  then
    threads_error "python3 could not sort candidate rows"
    threads_cleanup_tmp "$tmp"
    threads_emit_stats ok failed 0 0 0 "$unmeasured" 0
    return 0
  fi
  if [ ! -s "$candidates_file" ]; then
    threads_cleanup_tmp "$tmp"
    threads_emit_stats ok not_needed 0 0 0 "$unmeasured" 0
    return 0
  fi

  link_status=ok
  engine=${AUTODREAM_THREADS_ENGINE:-claude}
  model=${AUTODREAM_THREADS_MODEL:-claude-haiku-5-5}
  timeout_s=${AUTODREAM_THREADS_TIMEOUT:-300}
  max_input=${AUTODREAM_THREADS_MAX_INPUT:-65536}
  case "$timeout_s" in ''|*[!0-9]*) threads_error "AUTODREAM_THREADS_TIMEOUT must be a positive integer"; failed=1 ;; esac
  case "$max_input" in ''|*[!0-9]*) threads_error "AUTODREAM_THREADS_MAX_INPUT must be a positive integer"; failed=1 ;; esac
  if [ "$failed" -eq 0 ]; then
    timeout_s=$((10#$timeout_s))
    max_input=$((10#$max_input))
    [ "$timeout_s" -gt 0 ] || failed=1
    [ "$max_input" -gt 0 ] || failed=1
  fi
  case "$engine" in [abcdefghijklmnopqrstuvwxyz]*) ;; *) failed=1 ;; esac
  case "$engine" in *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) failed=1 ;; esac
  [ -n "$model" ] || failed=1
  if [ "$failed" -eq 0 ] && ! adapters_list 2>/dev/null | awk -v e="$engine" '$0 == e { found = 1 } END { exit !found }'; then
    threads_error "AUTODREAM_THREADS_ENGINE=$engine is not an accepted adapter"
    failed=1
  fi
  if [ "${AUTODREAM_THREADS_TIMEOUT_BIN+x}" = x ]; then
    timeout_bin=$AUTODREAM_THREADS_TIMEOUT_BIN
  else
    timeout_bin=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)
  fi
  if [ -z "$timeout_bin" ]; then
    threads_error "linker skipped because no timeout binary is available"
    failed=1
  fi
  prompt=$(threads_prompt_path) || prompt=""
  if [ -z "$prompt" ]; then
    threads_error "prompts/THREAD_LINKER.md was not found"
    failed=1
  fi
  if [ "$failed" -eq 1 ]; then
    threads_cleanup_tmp "$tmp"
    threads_emit_stats ok failed 0 0 0 "$unmeasured" 0
    return 0
  fi

  all_candidates="$tmp/request-all.json"
  groups_dir="$tmp/groups"
  groups_file="$tmp/groups.txt"
  threads_prepare_requests "$candidates_file" "$groups_dir" "$groups_file" "$all_candidates" || {
    threads_error "could not build linker candidate groups"
    threads_cleanup_tmp "$tmp"
    threads_emit_stats ok failed 0 0 0 "$unmeasured" 0
    return 0
  }
  request_list="$tmp/requests-to-call.txt"
  threads_write_linker_input "$date" "$state_json" "$all_candidates" "$prompt" "$tmp/all-request.json" "$tmp/all-input.txt" || failed=1
  size=$(LC_ALL=C wc -c < "$tmp/all-input.txt" 2>/dev/null | tr -d ' ')
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$failed" -eq 0 ] && [ "$size" -le "$max_input" ]; then
    printf '%s\n' "$all_candidates" > "$request_list"
  else
    if [ "$size" -gt "$max_input" ]; then
      threads_error "complete linker request is $size bytes; splitting candidates by repo hint"
    fi
    cp "$groups_file" "$request_list" 2>/dev/null || failed=1
  fi
  index=0
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    index=$((index + 1))
    request_candidates="$group"
    request_json="$tmp/request-$index.json"
    input_file="$tmp/input-$index.txt"
    response_file="$tmp/response-$index.jsonl"
    valid_file="$tmp/valid-$index.jsonl"
    rejected_file="$tmp/rejected-$index.txt"
    unusable_file="$tmp/unusable-$index.txt"
    group_candidates="$tmp/group-candidates-$index.jsonl"
    threads_select_candidate_rows "$request_candidates" "$candidates_file" "$group_candidates" || { failed=1; continue; }
    threads_write_linker_input "$date" "$state_json" "$request_candidates" "$prompt" "$request_json" "$input_file" || { failed=1; continue; }
    size=$(LC_ALL=C wc -c < "$input_file" | tr -d ' ')
    if [ "$size" -gt "$max_input" ]; then
      threads_error "repo-hint request is $size bytes, over AUTODREAM_THREADS_MAX_INPUT=$max_input"
      failed=1
      continue
    fi
    calls=$((calls + 1))
    if ! threads_call_linker "$input_file" "$response_file" "$engine" "$model" "$timeout_bin" "$timeout_s"; then
      failed=1
      continue
    fi
    if ! threads_validate_response "$group_candidates" "$state_json" "$response_file" "$valid_file" "$rejected_file" "$unusable_file"; then
      threads_error "could not validate linker output"
      failed=1
      continue
    fi
    rejected=$(($(cat "$rejected_file" 2>/dev/null || echo 0) + rejected))
    unusable=$(cat "$unusable_file" 2>/dev/null || echo 1)
    if [ "$unusable" = 1 ]; then
      threads_error "linker returned no usable JSON assignments"
      failed=1
      continue
    fi
    cat "$valid_file" >> "$assignments_file" || failed=1
  done < "$request_list"
  [ "$failed" -eq 0 ] || link_status=failed

  if [ -s "$assignments_file" ] && [ "$failed" -eq 0 ]; then
    mkdir -p "$(dirname "$STATE")" || {
      threads_error "cannot create thread state directory"
      link_status=failed
      threads_cleanup_tmp "$tmp"
      threads_emit_stats ok "$link_status" 0 "$rejected" "$close_refused" "$unmeasured" "$calls"
      return 0
    }
    if ! threads_acquire_lock; then
      skipped=locked
    else
      if ! state_json=$(threads_read_state); then
        threads_release_lock
        threads_warn_unreadable "$date"
        threads_cleanup_tmp "$tmp"
        threads_emit_stats unreadable failed 0 "$rejected" 0 "$unmeasured" "$calls"
        return 0
      fi
      rc=0
      printf '%s\n' "$state_json" | jq -c '.[]' > "$tmp/current-state.jsonl" || rc=1
      if [ "$rc" -eq 0 ] && threads_merge_assignments "$tmp/current-state.jsonl" "$candidates_file" "$assignments_file" "$tmp/merged.jsonl" "$tmp/merge-result.txt"; then
        IFS=' ' read -r linked merge_rejected close_refused < "$tmp/merge-result.txt"
        rejected=$((rejected + ${merge_rejected:-0}))
        if ! threads_write_state "$tmp/merged.jsonl"; then
          threads_error "could not atomically write thread state"
          link_status=failed
          linked=0
        fi
      else
        threads_error "could not merge thread assignments"
        link_status=failed
      fi
      threads_release_lock
    fi
  fi
  threads_cleanup_tmp "$tmp"
  threads_emit_stats ok "$link_status" "$linked" "$rejected" "$close_refused" "$unmeasured" "$calls" "$skipped"
}

threads_usage() {
  printf '%s\n' \
    'Usage: threads.sh list [--status STATUS] [--kind KIND] [--repo PATH] [--json]' \
    '       threads.sh search QUERY [--json]' \
    '       threads.sh update DATE' \
    '       threads.sh close ID' \
    '       threads.sh reopen ID' >&2
}

case "${1:-}" in
  list) shift; threads_list "$@" ;;
  update)
    shift
    [ "$#" -eq 1 ] || { threads_usage; exit 2; }
    threads_update "$1"
    ;;
  search)
    shift
    [ "$#" -gt 0 ] || { threads_usage; exit 2; }
    threads_search "$@"
    ;;
  close|reopen)
    action=$1; shift
    [ "$#" -eq 1 ] || { threads_usage; exit 2; }
    if [ "$action" = close ]; then threads_set_status "$1" closed_by_sam; else threads_set_status "$1" open; fi
    ;;
  *) threads_usage; exit 2 ;;
esac
