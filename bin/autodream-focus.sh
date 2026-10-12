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
# - The write is a temp file in the same directory and one rename, under a lock, because
#   three harnesses can tag at once and the mod's own writes are not locked at all.
#
# Usage:
#   autodream-focus.sh tag --harness claude|omp|codex --session ID --uuid ROW --role user|assistant
#                          [--cwd DIR] [--transcript FILE] [--text TEXT]   (text on stdin if omitted)
#   autodream-focus.sh last --harness omp|codex [--cwd DIR] [--file SESSION] [--role assistant|user] [--dry-run]
#
# Exit: 0 done, 1 refused (nothing written), 2 usage, 3 jq missing.
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
TAGS_FILE="${AUTODREAM_TAGS_FILE:-$AUTODREAM_DIR/tags.jsonl}"
LOCK="$TAGS_FILE.lock"

say()  { printf '%s\n' "$*"; }
die()  { local rc="$1"; shift; printf 'autodream-focus: %s\n' "$*" >&2; exit "$rc"; }
usage() { sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die 3 "jq is required"

acquire_lock() {
  local i=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -d "$LOCK" ]; then
      local age; age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || date +%s) ))
      if [ "$age" -gt 60 ]; then rmdir "$LOCK" 2>/dev/null || true; continue; fi
    fi
    i=$(( i + 1 ))
    [ "$i" -gt 20 ] && return 1
    sleep 0.25
  done
  return 0
}
release_lock() { rmdir "$LOCK" 2>/dev/null || true; }

# One cleanup for the lock and the scratch file, registered once. It must not name a function's
# local: an EXIT trap runs after the function has returned, where `set -u` makes the reference
# a fatal error that skips the rest of the trap, and a lock left behind blocks every later tag.
TMP=""
HAVE_LOCK=0
cleanup() {
  [ -z "$TMP" ] || rm -f "$TMP"
  [ "$HAVE_LOCK" = 0 ] || release_lock
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
  [ "$have_text" = 1 ] || text="$(cat)"
  [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || die 1 "that turn has no text, so there is nothing to tag"

  local id="$session:$uuid"

  mkdir -p "$(dirname "$TAGS_FILE")" 2>/dev/null || die 1 "cannot create $(dirname "$TAGS_FILE"); nothing was changed"
  acquire_lock || die 1 "another tag is being written and did not finish; nothing was changed"
  HAVE_LOCK=1

  # Only a file that is not there is empty.
  if [ -e "$TAGS_FILE" ] && { [ ! -f "$TAGS_FILE" ] || [ ! -r "$TAGS_FILE" ]; }; then
    die 1 "cannot read $TAGS_FILE; nothing was changed"
  fi

  TMP="$(mktemp "$TAGS_FILE.XXXXXX")" || die 1 "cannot write next to $TAGS_FILE; nothing was changed"
  local tmp="$TMP"

  # 1-based numbers of the lines that already tag this turn (any number, in case of a hand edit).
  local drop=""
  if [ -s "$TAGS_FILE" ]; then
    drop="$(jq -R -n -r --arg id "$id" \
      '[inputs] | to_entries[] | select(.value | try (fromjson | type == "object" and .id == $id) catch false) | .key + 1' \
      "$TAGS_FILE")" || die 1 "cannot parse $TAGS_FILE; nothing was changed"
  fi

  if [ -n "$drop" ]; then
    awk -v drop="$(printf '%s' "$drop" | tr '\n' ' ')" \
      'BEGIN { n = split(drop, a, " "); for (i = 1; i <= n; i++) d[a[i]] = 1 } !(NR in d)' \
      "$TAGS_FILE" > "$tmp" || die 1 "could not rewrite $TAGS_FILE; nothing was changed"
    mv -f "$tmp" "$TAGS_FILE" || die 1 "could not replace $TAGS_FILE; nothing was changed"
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

  {
    if [ -s "$TAGS_FILE" ]; then
      cat "$TAGS_FILE"
      # A torn last line has no newline; the new tag must not be glued onto it.
      [ -z "$(tail -c1 "$TAGS_FILE")" ] || printf '\n'
    fi
    printf '%s\n' "$line"
  } > "$tmp" || die 1 "could not write the tag; nothing was changed"
  mv -f "$tmp" "$TAGS_FILE" || die 1 "could not replace $TAGS_FILE; nothing was changed"
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
  # Sorted by mtime, newest first, bounded: a bucket holds hundreds of sessions.
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
  done < <(find "$root" -mindepth "$depth" -maxdepth "$depth" -type f -name "$find_name" -mtime -14 \
             -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -80 | cut -d' ' -f2-)
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
      session="$(head -1 "$file" | jq -r '.payload.id // .payload.session_id // empty')"
      # A user message has no id in a Codex rollout, so its timestamp stands in; the turns Codex
      # injects as user messages (environment context, instructions) start with `<`.
      picked="$(jq -c -s --arg role "$role" '
        map(select(.type == "response_item" and .payload.type == "message" and .payload.role == $role)
            | {id: (.payload.id // .timestamp), text: ([.payload.content[]? | .text // empty] | join("\n"))}
            | select(.text != "" and ($role == "assistant" or (.text | startswith("<") | not)))) | last // empty' "$file")" ;;
    omp)
      session="$(head -5 "$file" | jq -r 'select(.type == "session") | .id // empty' | head -1)"
      picked="$(jq -c -s --arg role "$role" '
        map(select(.type == "message" and .message.role == $role)
            | {id: .id, text: (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end)}
            | select(.text != "")) | last // empty' "$file")" ;;
  esac
  [ -n "$session" ] || die 1 "$file has no session id, so it is not a $harness session"
  [ -n "$picked" ] || die 1 "no $role message with text in $file"

  local uuid text
  uuid="$(printf '%s' "$picked" | jq -r '.id')"
  text="$(printf '%s' "$picked" | jq -r '.text')"

  if [ "$dry" = 1 ]; then
    say "would tag $session:$uuid ($role) from $file"
    printf '%s\n' "$text" | head -3 | sed 's/^/  > /'
    return 0
  fi
  cmd_tag --harness "$harness" --session "$session" --uuid "$uuid" --role "$role" --cwd "$cwd" --transcript "$file" --text "$text"
  say "  from $file"
}

case "${1:-}" in
  tag)  shift; cmd_tag "$@" ;;
  last) shift; cmd_last "$@" ;;
  *)    usage ;;
esac
