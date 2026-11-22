#!/usr/bin/env bash
set -u

hours=36
while [ $# -gt 0 ]; do
  case "$1" in
    --since-hours) [ $# -ge 2 ] || { echo "stop-check-counts: --since-hours takes a number" >&2; exit 2; }; hours="$2"; shift 2 ;;
    *) echo "usage: stop-check-counts.sh [--since-hours N]" >&2; exit 2 ;;
  esac
done
case "$hours" in ''|*[!0-9]*) echo "stop-check-counts: --since-hours takes a whole number of hours, got '$hours'" >&2; exit 2 ;; esac

log="${STOP_CHECK_VERDICTS:-$HOME/.claude/stop-check/verdicts.jsonl}"
now="${STOP_CHECK_NOW:-$(date +%s)}"
case "$now" in ''|*[!0-9]*) echo "stop-check-counts: STOP_CHECK_NOW must be epoch seconds" >&2; exit 2 ;; esac
command -v jq >/dev/null 2>&1 || { echo "stop-check-counts: jq not found" >&2; exit 1; }
[ -r "$log" ] || { echo "stop-check-counts: no verdict log at $log" >&2; exit 1; }

jq -nrR --argjson now "$now" --argjson hours "$hours" '
  def frac: ((capture("\\.(?<f>[0-9]+)Z$") | .f) // null) | if . == null then 0 else ("0." + .) | tonumber end;
  def ts: frac as $f | (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) + $f;
  def day: (. / 86400 | floor) * 86400;
  def weekstart: day | . - ((gmtime[6] + 6) % 7) * 86400;
  def iso: strftime("%Y-%m-%dT%H:%M:%SZ");
  [inputs | select(test("\\S"))] as $lines
  | [ $lines[]
      | (try fromjson catch null)
      | select(type == "object" and (.kind | type) == "string" and (.at | type) == "string")
      | . as $o
      | (try ($o.at | ts) catch null) as $t
      | select($t != null)
      | {kind: (if ($o.kind | test("^[a-z]+$")) then $o.kind else "other" end), t: $t} ] as $good
  | ($now - $hours * 3600) as $cutoff
  | ($good | map(select(.t >= $cutoff and .t <= $now))) as $recent
  | ($now | weekstart) as $thisweek
  | ([range(0; 8)] | map($thisweek - . * 7 * 86400) | reverse) as $weeks
  | ($good | map(select((.t | weekstart) >= $weeks[0] and (.t | weekstart) <= $thisweek and .t <= $now))) as $inweeks
  | ($inweeks | map(.kind) | unique) as $kinds
  | "meta\t\($hours)\t\($cutoff | iso)\t\($now | iso)\t\(($lines | length) - ($good | length))\t\($good | map(select(.t > $now)) | length)",
    ($recent | group_by(.kind) | map({k: .[0].kind, n: length}) | sort_by(-.n, .k)[] | "kind\t\(.k)\t\(.n)"),
    "total\t\($recent | length)",
    "wkh\t\($kinds | join("\t"))",
    ($weeks[] as $w
      | ($inweeks | map(select((.t | weekstart) == $w))) as $rows
      | "wk\t\($w | strftime("%Y-%m-%d"))\t\(($kinds | map(. as $k | $rows | map(select(.kind == $k)) | length)) + [$rows | length] | map(tostring) | join("\t"))")
' "$log" | awk -F'\t' '
  $1 == "meta" {
    printf "stop-check verdicts, last %sh (%s to %s)\n", $2, $3, $4
    bad = $5; future = $6
    printf "%-12s %s\n", "kind", "count"
    next
  }
  $1 == "kind"  { printf "%-12s %d\n", $2, $3; next }
  $1 == "total" {
    printf "%-12s %d\n", "total", $2
    printf "unparseable lines skipped: %d\n", bad
    printf "dated after now (not counted): %d\n\n", future
    next
  }
  $1 == "wkh" {
    line = sprintf("%-12s", "week")
    for (i = 2; i <= NF; i++) line = line sprintf(" %7s", $i)
    print line sprintf(" %7s", "total")
    next
  }
  $1 == "wk" {
    line = sprintf("%-12s", $2)
    for (i = 3; i <= NF; i++) line = line sprintf(" %7d", $i)
    print line
  }
  END { }
'
stages=("${PIPESTATUS[@]}")
[ "${stages[0]}" -eq 0 ] || exit "${stages[0]}"
exit "${stages[1]}"
