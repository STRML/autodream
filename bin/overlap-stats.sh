#!/bin/bash
set -u

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <findings_dir> [window_seconds]" >&2
  exit 2
fi

findings_dir="$1"
window="${2:-1800}"

if [ ! -d "$findings_dir" ]; then
  printf '{"overlap_events":0,"sessions_with_overlap":0}\n'
  exit 0
fi

build_session_list() {
  local f id
  for f in "$findings_dir"/*.stats.json; do
    [ -e "$f" ] || continue
    id=$(basename "$f" .stats.json)
    jq -c --arg id "$id" 'select(.is_advisor != true and .isSidechain != true and .nested != true) | {id: $id, ts: (.user_turn_timestamps // [])}' "$f" 2>/dev/null
  done
}

build_session_list | jq -s --argjson w "$window" '
  def has_overlap($a; $b; $w):
    ($a | length) as $la | ($b | length) as $lb
    | if $la == 0 or $lb == 0 then false
      else
        { i: 0, j: 0, found: false }
        | until(
            .found or (.i >= $la) or (.j >= $lb);
            ($a[.i]) as $x | ($b[.j]) as $y
            | (($x - $y) | if . < 0 then -. else . end) as $d
            | if $d <= $w then .found = true
              elif $x < $y then .i += 1
              else .j += 1
              end
          )
        | .found
      end;

  [ .[] | select((.ts | length) > 0) ] as $sessions
  | ($sessions | length) as $n
  | reduce range(0; $n) as $i (
      { events: 0, involved: {} };
      reduce range($i + 1; $n) as $j (
        .;
        if has_overlap($sessions[$i].ts; $sessions[$j].ts; $w)
        then
          .events += 1
          | .involved[$sessions[$i].id] = true
          | .involved[$sessions[$j].id] = true
        else . end
      )
    )
  | { overlap_events: .events, sessions_with_overlap: (.involved | keys | length) }
'
