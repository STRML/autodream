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

threads_usage() {
  printf '%s\n' \
    'Usage: threads.sh list [--status STATUS] [--kind KIND] [--repo PATH] [--json]' \
    '       threads.sh search QUERY [--json]' \
    '       threads.sh close ID' \
    '       threads.sh reopen ID' >&2
}

case "${1:-}" in
  list) shift; threads_list "$@" ;;
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
