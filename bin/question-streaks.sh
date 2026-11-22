#!/bin/bash
set -uo pipefail

usage() {
  cat <<'EOF'
usage: question-streaks.sh update <report.md> [findings-dir]   count, escalate, notify
       question-streaks.sh status                              print current streaks
       question-streaks.sh clear all|<key>                     forget a streak once acted on

Counts how many consecutive reports have carried the same open question, and escalates the
ones that have gone unanswered too long.

Environment:
  AUTODREAM_DIR                    default $HOME/.claude/autodream
  AUTODREAM_QUESTION_STATE         streak store   default $AUTODREAM_DIR/question-streaks.tsv
  AUTODREAM_QUESTION_ESCALATE_AT   escalate at N consecutive reports   default 3
  AUTODREAM_QUESTION_LOCK_WAIT     seconds to wait for a held lock   default 15
  AUTODREAM_NOTIFY_DRYRUN          1 = never post a banner

Exit: always 0 on `update`, so this bookkeeping helper never costs a night its report.
`clear` reports a failed write.
EOF
}

_src="${BASH_SOURCE[0]}"
sibling() {
  local p; p="$(dirname "$_src")/$1"
  [ -r "$p" ] || p="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/$1"
  printf '%s' "$p"
}

# shellcheck source=/dev/null
. "$(sibling portable.sh)"
# shellcheck source=/dev/null
. "$(sibling lib-install-dir.sh)"
resolve_install_dir "$_src"
_rf="$(sibling report-format.sh)"
_ll="$(sibling lib-flock.sh)"
for _p in "$_rf" "$_ll"; do
  [ -r "$_p" ] && continue
  echo "question-streaks: $(basename "$_p") not found beside $_src or its link target; streaks not touched" >&2
  [ "${1:-}" = update ] && exit 0
  exit 1
done
# shellcheck source=/dev/null
. "$_rf"
# shellcheck source=/dev/null
. "$_ll"
STATE="${AUTODREAM_QUESTION_STATE:-$AUTODREAM_DIR/question-streaks.tsv}"
ESCALATE_AT="${AUTODREAM_QUESTION_ESCALATE_AT:-3}"

case "$ESCALATE_AT" in ''|*[!0-9]*) ESCALATE_AT=3 ;; esac
[ "$ESCALATE_AT" -ge 1 ] || ESCALATE_AT=3

key_of() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed 's/^ //; s/ $//' \
    | shasum | cut -c1-12
}

titles_of() {
  report_questions "$1" 2>/dev/null \
    | sed -n '/^<!-- *autodream:open-questions/q;p' \
    | grep -oE '^[[:space:]]*[0-9]+[.)][[:space:]]*\*\*[^*]+\*\*' \
    | sed 's/^[[:space:]]*[0-9]*[.)][[:space:]]*\*\*//; s/\*\*$//'
}

LOCK="$STATE.flock"
LEGACY_LOCK="$STATE.lock"

rows_of() { awk '!/^#/ && NF' "$STATE" 2>/dev/null; }
nrows()   { rows_of | wc -l | tr -d ' '; }
streak_field() {
  awk -F'\t' -v k="$1" -v n="$2" '$1"" == k"" {print $n; exit}' "$STATE" 2>/dev/null
}
newest_of() {
  awk -F'\t' '/^#last\t/ {print $2} !/^#/ && NF>=4 {print $4}' "$STATE" 2>/dev/null \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -1
}
unreadable_state() { [ -e "$STATE" ] && { [ ! -f "$STATE" ] || [ ! -r "$STATE" ]; }; }
write_state() {
  local t; t=$(mktemp "$STATE.XXXXXX" 2>/dev/null) || return 1
  if ( { [ -z "$2" ] || printf '#last\t%s\n' "$2"; } && cat "$1" ) > "$t" 2>/dev/null \
     && mv -f "$t" "$STATE" 2>/dev/null; then
    return 0
  fi
  rm -f "$t" 2>/dev/null
  return 1
}
take_lock() {
  local max="${AUTODREAM_QUESTION_LOCK_WAIT:-15}"
  case "$max" in ''|*[!0-9]*|?????*) max=15 ;; esac
  flock_acquire "$LOCK" "$((10#$max))" "$LEGACY_LOCK"
}
drop_lock() { flock_release; }
lock_message() {
  case "$1" in
    1) echo "another run holds $LOCK" ;;
    5) echo "another run holds $LEGACY_LOCK (an older version's lock)" ;;
    2) echo "cannot lock $LOCK (it cannot be opened, or the kernel refused the lock)" ;;
    3) echo "python3 is required to lock $LOCK" ;;
    *) echo "this process already holds a lock (a caller bug)" ;;
  esac
}
lock_is_permanent() { case "$1" in 2|3|4) return 0 ;; *) return 1 ;; esac; }

cmd_update() {
  local report="${1:?usage: question-streaks.sh update <report.md> [findings-dir]}"
  local findings="${2:-}"
  [ -s "$report" ] || { echo "question-streaks: no report at $report; nothing to count"; return 0; }
  local date; date=$(basename "$report" .md)

  mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
  local lrc=0
  take_lock || lrc=$?
  if [ "$lrc" -ne 0 ]; then
    echo "question-streaks: $(lock_message "$lrc"); skipping this update"
    lock_is_permanent "$lrc" && show_notification "streak updates are DOWN: $(lock_message "$lrc")"
    return 0
  fi
  local tmp=""
  trap 'drop_lock; [ -n "$tmp" ] && rm -rf "$tmp"' RETURN

  if unreadable_state; then
    echo "question-streaks: cannot read $STATE; leaving streaks untouched"
    return 0
  fi
  local newest; newest=$(newest_of)
  if [ -n "$newest" ] && [ "$date" \< "$newest" ]; then
    echo "question-streaks: $date is older than the last counted report ($newest); leaving streaks untouched"
    return 0
  fi
  local same_date=0
  [ -n "$newest" ] && [ "$date" = "$newest" ] && same_date=1

  tmp="$(mktemp -d)" || return 0

  titles_of "$report" > "$tmp/titles" 2>/dev/null || : > "$tmp/titles"
  local n marker; n=$(wc -l < "$tmp/titles" | tr -d ' '); marker=$(report_marker_count "$report")

  if [ -z "$marker" ]; then
    echo "question-streaks: $date has no open-questions marker, so the report is incomplete; streaks not updated"
    return 0
  fi

  if [ "$marker" -ne "$n" ]; then
    echo "question-streaks: WARNING $date says $marker open question(s) but $n parsed — the title format changed; streaks not updated"
    post_banner "$date" 1 "parser broke: $marker question(s), $n parsed — escalation is DOWN"
    return 0
  fi

  if [ "$n" -eq 0 ]; then
    echo "question-streaks: no open questions in $date; clearing $(nrows) streak(s)"
    write_state /dev/null "$date" || echo "question-streaks: could not write $STATE; streaks untouched (continuing)"
    return 0
  fi

  : > "$tmp/next"; : > "$tmp/escalations"
  local escalated=0
  while IFS= read -r title; do
    [ -n "$title" ] || continue
    local k count first
    k=$(key_of "$title")
    count=$(streak_field "$k" 2)
    first=$(streak_field "$k" 3)
    case "${count:-}" in ''|*[!0-9]*) count=0 ;; esac
    if [ "$same_date" -ne 1 ] || [ "$count" -eq 0 ]; then count=$(( count + 1 )); fi
    [ -n "$first" ] || first="$date"
    printf '%s\t%s\t%s\t%s\t%s\n' "$k" "$count" "$first" "$date" "$title" >> "$tmp/next"
    if [ "$count" -ge "$ESCALATE_AT" ]; then
      printf '%s consecutive reports (since %s): %s\n' "$count" "$first" "$title" >> "$tmp/escalations"
      escalated=$(( escalated + 1 ))
    fi
  done < "$tmp/titles"

  write_state "$tmp/next" "$date" || { echo "question-streaks: could not write $STATE; streaks untouched (continuing)"; return 0; }

  echo "question-streaks: $n question(s) in $date, $escalated at or past $ESCALATE_AT consecutive"
  [ "$escalated" -eq 0 ] && return 0

  {
    printf '# Open questions autodream has now asked %s+ times\n\n' "$ESCALATE_AT"
    printf 'These have survived several reports unanswered. Either act on one or tell the\n'
    printf 'nightly to stop asking; a question that repeats at constant volume stops being read.\n\n'
    cat "$tmp/escalations"
  } > "$tmp/block"

  cat "$tmp/block"
  [ -n "$findings" ] && [ -d "$findings" ] && cp "$tmp/block" "$findings/question-escalations.txt" 2>/dev/null || true

  if [ "$same_date" -eq 1 ]; then
    echo "question-streaks: rebuild of $date; escalation written but no banner re-posted"
  else
    post_banner "$date" "$escalated" "$(head -1 "$tmp/escalations" | cut -c1-90)"
  fi
  return 0
}

show_notification() {
  [ "${AUTODREAM_NOTIFY_DRYRUN:-0}" = "1" ] && { echo "question-streaks: dry run, no banner"; return 0; }
  command -v osascript >/dev/null 2>&1 || { echo "question-streaks: no osascript; banner skipped"; return 0; }
  local msg
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  osascript -e "display notification \"$msg\" with title \"Autodream — still unanswered\"" >/dev/null 2>&1 9>&- \
    && echo "question-streaks: posted banner" \
    || echo "question-streaks: banner post failed (continuing)"
  return 0
}
post_banner() {
  local plural=""; [ "$2" -ne 1 ] && plural="s"
  show_notification "$2 question$plural unanswered $ESCALATE_AT+ nights: $3"
}

cmd_status() {
  unreadable_state && { echo "question-streaks: cannot read $STATE" >&2; return 1; }
  [ "$(nrows)" -gt 0 ] || { echo "question-streaks: no streaks recorded ($STATE)"; return 0; }
  printf '%-14s %-6s %-12s %-12s %s\n' KEY COUNT FIRST LAST TITLE
  rows_of | awk -F'\t' '{ printf "%-14s %-6s %-12s %-12s %s\n", $1, $2, $3, $4, $5 }'
  return 0
}

cmd_clear() {
  local what="${1:?usage: question-streaks.sh clear all|<key>}"
  if [ "$what" != "all" ] && ! [[ "$what" =~ ^[0-9a-f]{12}$ ]]; then
    echo "question-streaks: FAILED to clear: '$what' is not a streak key (12 lowercase hex characters; status lists them)" >&2
    return 1
  fi
  [ -d "$(dirname "$STATE")" ] || { echo "question-streaks: nothing to clear"; return 0; }
  local lrc=0
  take_lock || lrc=$?
  if [ "$lrc" -ne 0 ]; then
    echo "question-streaks: FAILED to clear: $(lock_message "$lrc")" >&2
    return 1
  fi
  trap 'drop_lock' RETURN
  unreadable_state && { echo "question-streaks: FAILED to clear: cannot read $STATE" >&2; return 1; }
  [ "$(nrows)" -gt 0 ] || { echo "question-streaks: nothing to clear"; return 0; }
  if [ "$what" != "all" ] && ! rows_of | awk -F'\t' -v k="$what" '$1"" == k"" {f=1} END {exit !f}'; then
    echo "question-streaks: FAILED to clear: no streak with key $what (status lists the keys)" >&2
    return 1
  fi
  local tmp; tmp="$(mktemp)" || { echo "question-streaks: FAILED to stage a rewrite of $STATE" >&2; return 1; }
  rows_of | awk -F'\t' -v k="$what" 'k"" != "all" && $1"" != k""' > "$tmp"
  if write_state "$tmp" "$(newest_of)"; then
    rm -f "$tmp"; echo "question-streaks: cleared $what"; return 0
  fi
  rm -f "$tmp"
  echo "question-streaks: FAILED to clear $what from $STATE" >&2; return 1
}

case "${1:-}" in
  update) shift; cmd_update "$@" ;;
  status) shift; cmd_status "$@" ;;
  clear)  shift; cmd_clear  "$@" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
