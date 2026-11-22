#!/bin/bash
set -u

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

usage() {
  cat <<'EOF'
Issue #39 measurement: how long does a pasted X auth_token/ct0 pair actually last?

The bookmark fetcher authenticates with cookies the user pastes by hand. Whether re-pasting
is a monthly chore or a yearly one decides whether automating the capture is worth its
moving parts.

Walks findings/<date>/x-bookmarks.md in date order and reports how many days ran between
the first working night after a paste and the first night the cookies were rejected.

Reads artifacts only: no model calls, no network, no credentials. Safe to re-run.

Usage:
  cookie-cadence.sh                       every dated dir under the findings root
  cookie-cadence.sh --days 30             trailing 30
  cookie-cadence.sh --quiet               summary only, no per-date table

Environment:
  AUTODREAM_DIR  default: $HOME/.claude/autodream
EOF
}

AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"
DAYS=0
QUIET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --days)
      [ "$#" -ge 2 ] || { echo "--days needs a value" >&2; exit 2; }
      case "$2" in ''|*[!0-9]*) echo "--days needs a positive integer, got: $2" >&2; exit 2 ;; esac
      [ "$2" -gt 0 ] || { echo "--days needs a positive integer, got: $2" >&2; exit 2; }
      DAYS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

FINDINGS_ROOT="$AUTODREAM_DIR/findings"
[ -d "$FINDINGS_ROOT" ] || { echo "no findings root at $FINDINGS_ROOT" >&2; exit 1; }

DATES=()
while IFS= read -r d; do
  [ -n "$d" ] && DATES+=("$(basename "$d")")
done < <(find "$FINDINGS_ROOT" -maxdepth 1 -type d -name '2[0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]' | sort)

[ "${#DATES[@]}" -gt 0 ] || { echo "no dated findings dirs found" >&2; exit 1; }
if [ "$DAYS" -gt 0 ] && [ "${#DATES[@]}" -gt "$DAYS" ]; then
  DATES=("${DATES[@]: -$DAYS}")
fi

epoch_of() { pdate_epoch "$1"; }

days_between() {
  local a b
  a=$(epoch_of "$1"); b=$(epoch_of "$2")
  [ -n "$a" ] && [ -n "$b" ] || return 0
  echo $(( (b - a) / 86400 ))
}

classify() {
  local f="$1" head
  [ -r "$f" ] || { echo absent; return; }
  head=$(head -n 1 "$f" 2>/dev/null)
  case "$head" in
    '# x-bookmarks: not configured'*) echo none ;;
    '# x-bookmarks: fetch failed'*)
      case "$head" in
        *'cookies are expired'*|*'expired or invalid'*) echo auth ;;
        *) echo other ;;
      esac ;;
    '') echo absent ;;
    *) echo ok ;;
  esac
}

[ "$QUIET" -eq 1 ] || printf '%-12s %-8s  %s\n' DATE STATUS DETAIL

LIVES=()
run_start=""
last_ok=""
observed_auth=0
ok_nights=0

for d in "${DATES[@]}"; do
  f="$FINDINGS_ROOT/$d/x-bookmarks.md"
  status=$(classify "$f")
  detail=""
  case "$status" in
    ok)
      ok_nights=$((ok_nights + 1))
      [ -n "$run_start" ] || { run_start="$d"; detail="credentials working"; }
      last_ok="$d" ;;
    auth)
      observed_auth=$((observed_auth + 1))
      if [ -n "$run_start" ]; then
        span=$(days_between "$run_start" "$d")
        LIVES+=("$run_start:$d:${span:-?}")
        detail="cookies rejected after ${span:-?} day(s) of working nights"
      else
        detail="cookies rejected, with no working night before it in this window"
      fi
      run_start=""; last_ok="" ;;
    other)  detail="fetch broke for an unrelated reason; says nothing about the cookies" ;;
    none)   detail="no credentials configured" ;;
    absent) detail="no x-bookmarks.md (the run predates the feature, or never got there)" ;;
  esac
  [ "$QUIET" -eq 1 ] || printf '%-12s %-8s  %s\n' "$d" "$status" "$detail"
done

echo
if [ "$ok_nights" -eq 0 ]; then
  echo "No night in this window fetched bookmarks successfully. There is nothing to"
  echo "measure here; that is not the same as a measured cadence."
  exit 0
fi

if [ "${#LIVES[@]}" -gt 0 ]; then
  echo "Observed credential lifetimes:"
  total=0; counted=0
  for life in "${LIVES[@]}"; do
    start="${life%%:*}"; rest="${life#*:}"; end="${rest%%:*}"; span="${rest#*:}"
    printf '  %s -> %s   %s day(s)\n' "$start" "$end" "$span"
    case "$span" in ''|*[!0-9]*) ;; *) total=$((total + span)); counted=$((counted + 1)) ;; esac
  done
  if [ "$counted" -gt 0 ]; then
    printf 'Mean over %s expiry event(s): %s day(s)\n' "$counted" \
      "$(awk -v t="$total" -v c="$counted" 'BEGIN{printf "%.1f", t/c}')"
  fi
else
  echo "No expiry has been observed yet."
fi

if [ -n "$run_start" ] && [ -n "$last_ok" ]; then
  span=$(days_between "$run_start" "$last_ok")
  printf 'Current credentials have worked since %s, %s day(s) and counting (a lower bound, not a lifetime).\n' \
    "$run_start" "${span:-?}"
fi

CREDS_FILE="$AUTODREAM_DIR/x-credentials"
if [ -f "$CREDS_FILE" ]; then
  pasted=$(date -r "$CREDS_FILE" '+%Y-%m-%d' 2>/dev/null)
  [ -n "$pasted" ] && printf 'Credentials file last written: %s\n' "$pasted"
fi

echo
if [ "$observed_auth" -eq 0 ]; then
  echo "VERDICT: no cadence yet. Re-run once an expiry has actually happened; until then"
  echo "there is no basis for deciding whether to automate the cookie capture."
elif [ "${#LIVES[@]}" -lt 2 ]; then
  echo "VERDICT: one expiry is an anecdote. Treat the number above as an order of"
  echo "magnitude and re-run after the next one."
else
  echo "VERDICT: enough expiries to act on. A short cadence (weeks) makes the"
  echo "Chrome cookie-harvest approach rejected during design worth revisiting."
fi
