#!/usr/bin/env bash
# autodream-focus.sh — tag a turn for the nightly autodream run to take a close look at.
#
# The Claude Code mod (mods/autodream-focus) tags a turn from a button on the row. OMP and
# Codex cannot draw one, so they tag through this script instead, and it is the one place
# that knows how to write $AUTODREAM_DIR/tags.jsonl safely for them:
#
#   tag   one turn, given its harness, session, row id, speaker and text (the OMP extension
#         calls this with what it already holds)
#   last  the newest session of a harness for a directory, and its last reply (what you run
#         from a second terminal for Codex, which has nothing to hook into)
#   path  the tags file this script writes, as it resolves it (the environment, then the install's
#         config): the Claude mod and the OMP picker ask here, so they read the file that is written
#
# bin/vault-notes.sh turns pending tags into notes for L2 (see its header). The line this
# writes is the mod's, plus `harness` and, when known, `transcript` (the session file, so
# the nightly run can open a session that is not a Claude one).
#
# WHY IT IS CAREFUL
#
# - Pressing it again on the same turn takes the tag back, as the button does.
# - Only a tags file that does not exist is empty. One that exists and cannot be read is a
#   refusal with nothing written, because the write replaces the whole file and reading
#   "unreadable" as "empty" would replace every tag with the one being added.
# - Lines it does not understand are written back as they stood (a torn last line gets its newline).
# - Adding a tag is one append, so it cannot drop another writer's line. Taking a tag back replaces
#   the file (a temp file in the same directory and one rename) and is the only write that does.
# - `tag` runs under flock(2) on $TAGS_FILE.lock, taken by a python3 wrapper that re-runs this script,
#   because three harnesses can tag at once. The kernel owns the lock: nothing can go stale.
#
# Usage:
#   autodream-focus.sh tag --harness claude|omp|codex --session ID --uuid ROW --role user|assistant
#                          [--cwd DIR] [--transcript FILE] [--text TEXT]   (text on stdin if omitted)
#   autodream-focus.sh last --harness omp|codex [--cwd DIR] [--file SESSION] [--role assistant|user] [--dry-run]
#   autodream-focus.sh path
#
# Exit: 0 done, 1 refused (nothing written), 2 usage, 3 jq or python3 missing.
#
# Config (env):
#   AUTODREAM_DIR         default: next to this script when it carries an install marker, else
#                         $HOME/.claude/autodream
#   AUTODREAM_TAGS_FILE   default $AUTODREAM_DIR/tags.jsonl
#   CODEX_HOME            default $HOME/.codex
#   PI_CODING_AGENT_DIR    OMP agent directory, default $HOME/.omp/agent
set -euo pipefail

TEXT_CAP=2000

AUTODREAM_DIR="${AUTODREAM_DIR:-}"
if [ -z "$AUTODREAM_DIR" ]; then
  _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  if [ -n "$_here" ] && { [ -f "$_here/config" ] || [ -f "$_here/PROMPT.md" ]; }; then
    AUTODREAM_DIR="$_here"
  else
    AUTODREAM_DIR="$HOME/.claude/autodream"
  fi
fi
# The collector (bin/vault-notes.sh) reads $AUTODREAM_DIR/config, so a tags file named only there is
# the one it reads. This writer resolves it the same way, with the same guards: the caller's exports
# win over the file (the snapshot is replayed after), and a bad config line cannot kill the script.
AUTODREAM_CONFIG="${AUTODREAM_CONFIG:-$AUTODREAM_DIR/config}"
if [ -f "$AUTODREAM_CONFIG" ]; then
  _env_snapshot=$(export -p)
  set +eu
  set -a
  # shellcheck disable=SC1090
  . "$AUTODREAM_CONFIG" 2>/dev/null || true
  set +a
  eval "$_env_snapshot" 2>/dev/null
  set -eu
  unset _env_snapshot
fi
TAGS_FILE="${AUTODREAM_TAGS_FILE:-$AUTODREAM_DIR/tags.jsonl}"

# Installed copies are symlinks into the repo's bin/, so the helpers are found next to the
# link (installed tree) or next to its target (repo checkout).
_self_dir="$(dirname "${BASH_SOURCE[0]}")"
_real_dir="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")"
_pp="$_self_dir/portable.sh"
[ -r "$_pp" ] || _pp="$_real_dir/portable.sh"
# shellcheck source=/dev/null
. "$_pp"
LINEARIZE="$_self_dir/adapters/omp/linearize.sh"
[ -r "$LINEARIZE" ] || LINEARIZE="$_real_dir/../adapters/omp/linearize.sh"
LOCK="$TAGS_FILE.lock"

say()  { printf '%s\n' "$*"; }
die()  { local rc="$1"; shift; printf 'autodream-focus: %s\n' "$*" >&2; exit "$rc"; }
usage() { sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die 3 "jq is required"

# The tags file is written by one process at a time, and the lock is the kernel's, not a file this
# script judges. `tag` re-runs itself under a small python wrapper that takes flock(2) on
# $TAGS_FILE.lock and then execs the script with the lock still held; the kernel drops it when that
# process exits or dies, however it ends. There is no stale lock to detect (so no age rule, no owner
# pid, no reclaim claim for two waiters to race over), and a writer suspended for any length of time
# still holds it. A waiter polls without blocking and gives up after five seconds, saying so.
LOCKER_PY='
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o600)
deadline = time.time() + 5
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except OSError:
        if time.time() >= deadline:
            sys.stderr.write("autodream-focus: another tag is being written and did not finish; nothing was changed\n")
            sys.exit(1)
        time.sleep(0.05)
os.set_inheritable(fd, True)
os.execv(sys.argv[2], sys.argv[2:])
'

hold_lock_and_rerun() { # args: the subcommand and its arguments, run again with the lock held
  command -v python3 >/dev/null 2>&1 || die 3 "python3 is required (it holds the lock on the tags file)"
  mkdir -p "$(dirname "$TAGS_FILE")" 2>/dev/null || die 1 "cannot create $(dirname "$TAGS_FILE"); nothing was changed"
  AUTODREAM_FOCUS_LOCKED=1 exec python3 -c "$LOCKER_PY" "$LOCK" "$BASH" "${BASH_SOURCE[0]}" "$@"
}

fingerprint() { if [ -f "$TAGS_FILE" ]; then cksum < "$TAGS_FILE" 2>/dev/null || echo unreadable; else echo absent; fi; }

# One cleanup for the scratch files, registered once. It must not name a function's local: an EXIT
# trap runs after the function has returned, where `set -u` makes the reference a fatal error that
# skips the rest of the trap.
TMP=""
LIVE=""
cleanup() {
  [ -z "$TMP" ] || rm -f "$TMP"
  [ -z "$LIVE" ] || rm -f "$LIVE"
}
trap cleanup EXIT

# ---- tag ----

cmd_tag() {
  local harness="" session="" uuid="" role="" cwd="" transcript="" text="" have_text=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --harness)    [ $# -ge 2 ] || usage; harness="$2"; shift 2 ;;
      --session)    [ $# -ge 2 ] || usage; session="$2"; shift 2 ;;
      --uuid)       [ $# -ge 2 ] || usage; uuid="$2"; shift 2 ;;
      --role)       [ $# -ge 2 ] || usage; role="$2"; shift 2 ;;
      --cwd)        [ $# -ge 2 ] || usage; cwd="$2"; shift 2 ;;
      --transcript) [ $# -ge 2 ] || usage; transcript="$2"; shift 2 ;;
      --text)       [ $# -ge 2 ] || usage; text="$2"; have_text=1; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$session" ] && [ -n "$uuid" ] || usage
  case "$harness" in claude|omp|codex) ;; *) usage ;; esac
  case "$role" in user|assistant) ;; *) usage ;; esac
  [ "$have_text" = 1 ] || text="$(cat)" || die 1 "could not read the turn text from stdin; nothing was changed"
  [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || die 1 "that turn has no text, so there is nothing to tag"

  # The nightly run reads this from another working directory, so a relative path is resolved now.
  case "$transcript" in
    ''|/*) ;;
    *) transcript="$(cd "$(dirname "$transcript")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$transcript")")" \
         || die 1 "cannot resolve the transcript path $transcript; nothing was changed" ;;
  esac

  local id="$session:$uuid"

  mkdir -p "$(dirname "$TAGS_FILE")" 2>/dev/null || die 1 "cannot create $(dirname "$TAGS_FILE"); nothing was changed"

  # Only a file that is not there is empty.
  if [ -e "$TAGS_FILE" ] && { [ ! -f "$TAGS_FILE" ] || [ ! -r "$TAGS_FILE" ]; }; then
    die 1 "cannot read $TAGS_FILE; nothing was changed"
  fi

  # 1-based numbers of the lines that already tag this turn (any number, in case of a hand edit).
  local drop=""
  if [ -s "$TAGS_FILE" ]; then
    drop="$(jq -R -n -r --arg id "$id" \
      '[inputs] | to_entries[] | select(.value | try (fromjson | type == "object" and .id == $id) catch false) | .key + 1' \
      "$TAGS_FILE")" || die 1 "cannot parse $TAGS_FILE; nothing was changed"
  fi

  # Taking a tag back is the one write that replaces the file. Every cooperating writer is held off by
  # the lock; the fingerprint, checked again just before the rename, is for a writer that takes no lock
  # (a copy of the old mod that rewrites the file itself): it refuses rather than publish a copy that
  # drops that writer's tag. Adding a tag never needs it: that is an append (below).
  if [ -n "$drop" ]; then
    local before; before="$(fingerprint)"
    TMP="$(mktemp "$TAGS_FILE.XXXXXX")" || die 1 "cannot write next to $TAGS_FILE; nothing was changed"
    awk -v drop="$(printf '%s' "$drop" | tr '\n' ' ')" \
      'BEGIN { n = split(drop, a, " "); for (i = 1; i <= n; i++) d[a[i]] = 1 } !(NR in d)' \
      "$TAGS_FILE" > "$TMP" || die 1 "could not rewrite $TAGS_FILE; nothing was changed"
    [ "$(fingerprint)" = "$before" ] || die 1 "$TAGS_FILE changed while it was being rewritten; nothing was changed"
    mv -f "$TMP" "$TAGS_FILE" || die 1 "could not replace $TAGS_FILE; nothing was changed"
    say "untagged $id"
    return 0
  fi

  local at line
  at="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  line="$(jq -cn --arg id "$id" --arg session "$session" --arg uuid "$uuid" --arg role "$role" \
    --arg text "$text" --arg cwd "$cwd" --arg at "$at" --arg harness "$harness" --arg transcript "$transcript" \
    --argjson cap "$TEXT_CAP" \
    '{id: $id, session: $session, uuid: $uuid, role: $role,
      text: (if ($text | length) > $cap then ($text[0:$cap] + "…") else $text end),
      cwd: $cwd, taggedAt: $at, harness: $harness}
     + (if $transcript == "" then {} else {transcript: $transcript} end)')" || die 1 "could not build the tag"

  # An append, not a copy and a rename: one O_APPEND write adds the line without reading or replacing
  # anything, so it cannot drop another writer's tag even if that writer takes no lock, and there is no
  # copy of the file to come out partial. A torn last line has no newline, so the write starts with one
  # and the new tag is not glued onto it (the newline and the line are one write).
  local last="" lead=""
  if [ -s "$TAGS_FILE" ]; then
    last="$(tail -c1 "$TAGS_FILE")" || die 1 "could not read $TAGS_FILE; nothing was changed"
    if [ -n "$last" ]; then lead=$'\n'; fi
  fi
  printf '%s%s\n' "$lead" "$line" >> "$TAGS_FILE" || die 1 "could not write the tag to $TAGS_FILE; nothing may have been changed"
  say "tagged $id"
}

# ---- last ----

# Newest session file of a harness whose recorded cwd is one of $2/$3, on stdout; nothing if none.
newest_session() { # $1=harness $2=cwd $3=physical cwd
  local harness="$1" want1="$2" want2="$3" root depth find_name f got
  case "$harness" in
    codex) root="${CODEX_HOME:-$HOME/.codex}/sessions"; depth=4; find_name='rollout-*.jsonl' ;;
    omp)   root="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/sessions"; depth=2; find_name='*.jsonl' ;;
  esac
  [ -d "$root" ] || return 0
  # Sorted by mtime, newest first, and read until one records the wanted directory. No count limit
  # before that match: a limit across the whole root would stop before a recent session of this
  # directory whenever other directories' sessions are newer. The 14-day window is the bound.
  local cand m
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$harness" in
      codex) got="$(head -1 "$f" 2>/dev/null | jq -r '.payload.cwd // empty' 2>/dev/null || true)" ;;
      omp)   got="$(head -5 "$f" 2>/dev/null | jq -r 'select(.type == "session") | .cwd // empty' 2>/dev/null | head -1 || true)" ;;
    esac
    if [ -n "$got" ] && { [ "$got" = "$want1" ] || [ "$got" = "$want2" ]; }; then
      printf '%s' "$f"
      return 0
    fi
  done < <(find "$root" -mindepth "$depth" -maxdepth "$depth" -type f -name "$find_name" -mtime -14 2>/dev/null \
             | while IFS= read -r cand; do m="$(pstat_mtime "$cand")" && printf '%s %s\n' "$m" "$cand"; done \
             | sort -rn | cut -d' ' -f2-)
  return 0
}

cmd_last() {
  local harness="" cwd="$PWD" file="" role="assistant" dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --harness) [ $# -ge 2 ] || usage; harness="$2"; shift 2 ;;
      --cwd)     [ $# -ge 2 ] || usage; cwd="$2"; shift 2 ;;
      --file)    [ $# -ge 2 ] || usage; file="$2"; shift 2 ;;
      --role)    [ $# -ge 2 ] || usage; role="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      *) usage ;;
    esac
  done
  case "$harness" in omp|codex) ;; *) usage ;; esac
  case "$role" in user|assistant) ;; *) usage ;; esac

  if [ -z "$file" ]; then
    local phys; phys="$(cd "$cwd" 2>/dev/null && pwd -P || printf '%s' "$cwd")"
    file="$(newest_session "$harness" "$cwd" "$phys")"
    [ -n "$file" ] || die 1 "no recent $harness session recorded for $cwd (last 14 days); pass --file to name one"
  fi
  [ -r "$file" ] || die 1 "cannot read $file"

  local session picked
  case "$harness" in
    codex)
      session="$(head -1 "$file" | jq -rR 'fromjson? | .payload.id // .payload.session_id // empty')" || session=""
      # A person's turn is its own record: an `item_completed` UserMessage (older builds: an
      # `event_msg` user_message). The `response_item` messages with role user are what Codex injects
      # (instructions, environment context), whatever their text starts with, so they are never read.
      picked="$(jq -c -s --arg role "$role" '
        def text: [.[]? | .text // empty] | join("\n");
        map(if $role == "assistant" then
              select(.type == "response_item" and .payload.type == "message" and .payload.role == "assistant")
              | {id: (.payload.id // .timestamp), text: (.payload.content | text)}
            else
              select(.type == "event_msg" and ((.payload.type == "item_completed" and .payload.item.type == "UserMessage")
                                               or .payload.type == "user_message"))
              | if .payload.type == "user_message"
                then {id: (.payload.id // .timestamp), text: (.payload.message // "")}
                else {id: (.payload.item.id // .timestamp), text: (.payload.item.content | text)} end
            end
            | select(.text != "")) | last // empty' "$file")" \
        || die 1 "$file is not readable JSON lines; nothing was changed" ;;
    omp)
      session="$(head -5 "$file" | jq -rR 'fromjson? | select(.type == "session") | .id // empty' | head -1)" || session=""
      [ -n "$session" ] || die 1 "$file has no session id, so it is not a $harness session"
      # The file is a tree that keeps every branch the user backed out of; read only the live
      # chain, and refuse rather than fall back to the raw file when it cannot be walked.
      [ -r "$LINEARIZE" ] || die 1 "cannot find adapters/omp/linearize.sh next to this script"
      # LIVE is a global the EXIT trap removes: a 0600 copy of the transcript must go whichever
      # step below ends the script.
      LIVE="$(mktemp "${TMPDIR:-/tmp}/autodream-focus.XXXXXX")" || die 1 "cannot write a scratch file in ${TMPDIR:-/tmp}; nothing was changed"
      bash "$LINEARIZE" "$file" "$LIVE" 2>/dev/null \
        || die 1 "$file could not be read as a single OMP conversation; nothing was changed"
      # A user-role message attributed to the agent (a steering or injected turn) is not the human's.
      picked="$(jq -c -s --arg role "$role" '
        map(select(.type == "message" and .message.role == $role and .message.attribution != "agent")
            | {id: .id, text: (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end)}
            | select(.text != "")) | last // empty' "$LIVE")" \
        || die 1 "$file could not be read as OMP messages; nothing was changed" ;;
  esac
  [ -n "$session" ] || die 1 "$file has no session id, so it is not a $harness session"
  [ -n "$picked" ] || die 1 "no $role message with text in $file"

  local uuid text
  uuid="$(printf '%s' "$picked" | jq -r '.id')" || die 1 "cannot read the turn picked from $file; nothing was changed"
  text="$(printf '%s' "$picked" | jq -r '.text')" || die 1 "cannot read the turn picked from $file; nothing was changed"

  if [ "$dry" = 1 ]; then
    say "would tag $session:$uuid ($role) from $file"
    printf '%s\n' "$text" | head -3 | sed 's/^/  > /'
    return 0
  fi
  # The tag is its own run of this script, which takes the lock: this one only read session files.
  "$BASH" "${BASH_SOURCE[0]}" tag --harness "$harness" --session "$session" --uuid "$uuid" --role "$role" --cwd "$cwd" --transcript "$file" --text "$text"
  say "  from $file"
}

case "${1:-}" in
  tag)
    shift
    if [ "${AUTODREAM_FOCUS_LOCKED:-}" != 1 ]; then hold_lock_and_rerun tag "$@"; fi
    cmd_tag "$@" ;;
  last) shift; cmd_last "$@" ;;
  path) printf '%s\n' "$TAGS_FILE" ;;
  *)    usage ;;
esac
