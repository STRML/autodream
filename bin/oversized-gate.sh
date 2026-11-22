#!/bin/bash
set -u

usage() {
  cat <<'EOF'
# Issue #12 measurement gate: what share of oversized transcripts still failed to triage?
#
# The gate is a trailing-window judgment: size failures divided by oversized sessions
# that have no silent, provider, or unclassified failure. A sustained share >= 5% over
# a week opens #12. run.sh records one night at a time, and an old runner (#29) may omit
# the counters, so this recomputes the window from sidecars, findings, and .err artifacts.
#
# It reads only artifacts. No model calls, no network, safe to re-run.
#
# Usage:
#   oversized-gate.sh                       # trailing 7 dated dirs under the findings root
#   oversized-gate.sh --days 14             # trailing 14
#   oversized-gate.sh <findings-dir>...     # exactly these dirs
#
# Environment:
#   AUTODREAM_DIR         default: $HOME/.claude/autodream
#   AUTODREAM_SLIM_BYTES  oversized threshold, matches run.sh   default: 262144
EOF
}

HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

_og_src="${BASH_SOURCE[0]}"; _og_hops=0
while [ -L "$_og_src" ] && [ "$_og_hops" -lt 8 ]; do
  _og_dir=$(cd "$(dirname "$_og_src")" && pwd) || break
  _og_src=$(readlink "$_og_src") || break
  case $_og_src in /*) ;; *) _og_src="$_og_dir/$_og_src" ;; esac
  _og_hops=$((_og_hops + 1))
done
_og_real=""
[ -L "$_og_src" ] || _og_real=$(cd "$(dirname "$_og_src")" 2>/dev/null && pwd) || _og_real=""
# shellcheck source=/dev/null
if [ -r "$HERE/lib-project.sh" ]; then . "$HERE/lib-project.sh"
elif [ -n "$_og_real" ] && [ -r "$_og_real/lib-project.sh" ]; then . "$_og_real/lib-project.sh"
else
  echo "oversized-gate: lib-project.sh not found beside this script or its real location" >&2; exit 2
fi

AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
self="${BASH_SOURCE[0]}"; hops=0
while [ -L "$self" ] && [ "$hops" -lt 8 ]; do
  link_dir=$(cd "$(dirname "$self")" && pwd) || break
  self=$(readlink "$self") || break
  case $self in /*) ;; *) self="$link_dir/$self" ;; esac
  hops=$((hops + 1))
done
REAL_DIR=$(cd "$(dirname "$self")" 2>/dev/null && pwd) || REAL_DIR=""
FAILURE_CLASS=""
for candidate in "$SCRIPT_DIR" "$REAL_DIR" "$AUTODREAM_DIR"; do
  [ -n "$candidate" ] && [ -r "$candidate/failure-class.sh" ] && { FAILURE_CLASS="$candidate/failure-class.sh"; break; }
done
if [ -z "$FAILURE_CLASS" ]; then
  printf 'fatal: required failure classifier not found next to %s, %s or %s\n' "$SCRIPT_DIR" "${REAL_DIR:-?}" "$AUTODREAM_DIR" >&2
  exit 1
fi
# shellcheck source=./failure-class.sh
. "$FAILURE_CLASS"
THRESHOLD="${AUTODREAM_SLIM_BYTES:-262144}"
DAYS=7
DIRS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --days)
      [ "$#" -ge 2 ] || { echo "--days needs a value" >&2; exit 2; }
      case "$2" in ''|*[!0-9]*) echo "--days needs a positive integer, got: $2" >&2; exit 2 ;; esac
      [ "$2" -gt 0 ] || { echo "--days needs a positive integer, got: $2" >&2; exit 2; }
      DAYS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) DIRS+=("$1"); shift ;;
  esac
done

if [ "${#DIRS[@]}" -eq 0 ]; then
  root="$AUTODREAM_DIR/findings"
  [ -d "$root" ] || { echo "no findings root at $root" >&2; exit 1; }
  while IFS= read -r d; do
    [ -n "$d" ] && DIRS+=("$d")
  done < <(find "$root" -maxdepth 1 -type d -name '2[0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]' \
    | sort | tail -n "$DAYS")
fi

[ "${#DIRS[@]}" -gt 0 ] || { echo "no dated findings dirs found" >&2; exit 1; }

table_row() {
  printf '%-12s %7s %10s %9s %7s %8s %8s %8s  %s\n' "$@"
}

total_oversized=0
total_errored=0
total_silent=0
total_provider=0
total_unclassified=0
total_deferred=0
total_nolist=0
total_unmeasurable=0
dates_measured=0

table_row \
  DATE SESSIONS OVERSIZED ERRORED SILENT PROVIDER UNCLASS SHARE SOURCE
for d in "${DIRS[@]}"; do
  date_label=$(basename "$d")
  list="$d/sessions.txt"
  if [ ! -r "$list" ]; then
    table_row "$date_label" - - - - - - - "no sessions.txt"
    total_nolist=$((total_nolist + 1))
    continue
  fi
  if grep -qx 'network_deferred: yes' "$d/run-stats.txt" 2>/dev/null; then
    table_row "$date_label" - - - - - - - "network-deferred run, excluded"
    total_deferred=$((total_deferred + 1))
    continue
  fi

  sessions=0; oversized=0; errored=0; silent=0; provider=0; unclassified=0
  from_sidecar=0; unmeasurable=0
  while IFS= read -r session; do
    [ -n "$session" ] || continue
    sessions=$((sessions + 1))
    hash=$(session_hash "$session") || { unmeasurable=$((unmeasurable + 1)); continue; }
    sidecar="$d/$hash.stats.json"
    size=""
    [ -s "$sidecar" ] && size=$(jq -r '.transcript_bytes | numbers | floor' "$sidecar" 2>/dev/null)
    case "$size" in ''|*[!0-9]*) size="" ;; esac
    if [ -n "$size" ]; then
      from_sidecar=$((from_sidecar + 1))
    else
      size=$(wc -c < "$session" 2>/dev/null | tr -d ' ')
      case "$size" in ''|*[!0-9]*) size="" ;; esac
      if [ -z "$size" ]; then
        unmeasurable=$((unmeasurable + 1))
        continue
      fi
    fi
    if [ "$size" -gt "$THRESHOLD" ]; then
      oversized=$((oversized + 1))
      findings="$d/$hash.json"
      if [ -f "$findings" ] && jq -e 'type == "object" and has("error")' "$findings" >/dev/null 2>&1; then
        errored=$((errored + 1))
        failure_class=$(classify_failure "$findings.err")
        case "$failure_class" in
          silent) silent=$((silent + 1)) ;;
          provider) provider=$((provider + 1)) ;;
          unclassified) unclassified=$((unclassified + 1)) ;;
        esac
      fi
    fi
  done < "$list"

  total_oversized=$((total_oversized + oversized))
  total_errored=$((total_errored + errored))
  total_silent=$((total_silent + silent))
  total_provider=$((total_provider + provider))
  total_unclassified=$((total_unclassified + unclassified))
  total_unmeasurable=$((total_unmeasurable + unmeasurable))
  if [ $((sessions - unmeasurable)) -gt 0 ]; then
    dates_measured=$((dates_measured + 1))
  fi

  measured=$((oversized - silent - provider - unclassified))
  size_errored=$((errored - silent - provider - unclassified))
  if [ "$measured" -gt 0 ]; then
    share=$(awk -v e="$size_errored" -v o="$measured" 'BEGIN{printf "%.1f%%", 100*e/o}')
  else
    share="n/a"
  fi
  source_note="$from_sidecar/$sessions from sidecars"
  [ "$unmeasurable" -gt 0 ] && source_note="$source_note, $unmeasurable unmeasurable"
  table_row \
    "$date_label" "$sessions" "$oversized" "$errored" "$silent" "$provider" "$unclassified" "$share" "$source_note"
done

echo
[ "$total_deferred" -gt 0 ] && echo "Excluded $total_deferred network-deferred date(s): no worker ran for part of those corpora."
[ "$total_nolist" -gt 0 ] && echo "Excluded $total_nolist date(s) with no sessions.txt."
if [ "$dates_measured" -eq 0 ]; then
  echo "No date in this window could be measured. The gate has no evidence either way."
  exit 0
fi
if [ "$total_oversized" -eq 0 ]; then
  echo "No oversized transcripts in this window. The gate has nothing to measure;"
  echo "that is not the same as a measured 0% and should not close #12 on its own."
  [ "$total_unmeasurable" -gt 0 ] && echo "$total_unmeasurable session(s) could not be sized at all, so some may have been oversized."
  exit 0
fi

printf 'Window: %s oversized, %s errored, %s silent, %s provider, %s unclassified' \
  "$total_oversized" "$total_errored" "$total_silent" "$total_provider" "$total_unclassified"
[ "$total_unmeasurable" -gt 0 ] && printf ' (%s session(s) unmeasurable, excluded)' "$total_unmeasurable"
printf '\n'

measured=$((total_oversized - total_silent - total_provider - total_unclassified))
size_errored=$((total_errored - total_silent - total_provider - total_unclassified))
if [ "$measured" -eq 0 ]; then
  echo "The window measured nothing about size after excluding silent, provider, and"
  echo "unclassified failures. Fix those causes, then re-measure."
  exit 0
fi

share=$(awk -v e="$size_errored" -v o="$measured" 'BEGIN{printf "%.2f", 100*e/o}')
printf 'Size-attributable: %s errored of %s, %s%%\n' "$size_errored" "$measured" "$share"
if [ "$size_errored" -eq 0 ]; then
  bound=$(awk -v n="$measured" 'BEGIN{printf "%.1f", 100*3/n}')
  echo "Zero failures in $measured samples; 95% upper bound about $bound% (rule of three)."
fi
if awk -v s="$share" 'BEGIN{exit !(s + 0 >= 5)}'; then
  echo "GATE OPEN: at or above the 5% threshold. Issue #12 (chunk-summarize) is unblocked."
else
  echo "GATE CLOSED: below the 5% threshold. The existing fallback stack is coping."
fi
