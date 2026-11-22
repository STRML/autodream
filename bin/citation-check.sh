#!/bin/bash
set -uo pipefail

report="${1:-}"
fdir="${2:-}"

if [ -z "$report" ] || [ -z "$fdir" ]; then
  echo "usage: $0 <report.md> <findings-dir>" >&2
  exit 2
fi
[ -s "$report" ] || { echo "citation-check: report not readable: $report" >&2; exit 2; }
[ -d "$fdir" ]   || { echo "citation-check: findings dir not readable: $fdir" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "citation-check: jq not available" >&2; exit 2; }

hashes=$(sed 's/[^0-9a-f]/ /g' "$report" 2>/dev/null \
         | tr ' ' '\n' \
         | grep -xE '[0-9a-f]{12}' \
         | sort -u)
total=0; unresolved=0; gated=0; by_path=0
unresolved_list=""; gated_list=""

session_paths="$(jq -r -s '[ .[] | select(type == "object") | .session_path // empty ] | .[]' \
                   "$fdir"/*.json 2>/dev/null || true)"

mark_unresolved() {
  unresolved=$((unresolved + 1))
  unresolved_list="${unresolved_list:+$unresolved_list,}$1"
}

for h in $hashes; do
  total=$((total + 1))
  f="$fdir/$h.json"
  if [ ! -s "$f" ]; then
    if printf '%s\n' "$session_paths" | grep -qF "$h" 2>/dev/null; then
      by_path=$((by_path + 1))
    else
      mark_unresolved "$h"
    fi
    continue
  fi
  verdict=$(jq -r 'if (.skipped // "") == "below_noise_gate" then "gated" else "ok" end' "$f" 2>/dev/null) || verdict="bad"
  case "$verdict" in
    gated)
      gated=$((gated + 1))
      gated_list="${gated_list:+$gated_list,}$h"
      ;;
    ok) ;;
    *)
      mark_unresolved "$h"
      ;;
  esac
done

printf 'citations_total: %s\n' "$total"
printf 'citations_unresolved: %s\n' "$unresolved"
printf 'citations_to_gated: %s\n' "$gated"
printf 'citations_resolved_by_path: %s\n' "$by_path"
printf 'citations_unresolved_list: %s\n' "$unresolved_list"
printf 'citations_to_gated_list: %s\n' "$gated_list"
exit 0
