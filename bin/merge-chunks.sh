#!/bin/bash
set -u

usage() { echo "usage: $0 --check FILE | --session PATH [--elided N] CHUNK.json ..." >&2; exit 2; }

CHUNK_OK='length == 1 and (.[0] | (type == "object") and (has("error") | not) and ((.findings | type) == "array"))'
chunk_ok() { [ -s "$1" ] && jq -s -e "$CHUNK_OK" "$1" >/dev/null 2>&1; }

if [ "${1:-}" = "--check" ]; then
  [ "$#" -eq 2 ] || usage
  chunk_ok "$2" && exit 0
  exit 1
fi

session=""; elided=0; files=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --session) [ "$#" -ge 2 ] || usage; session="$2"; shift 2 ;;
    --elided)  [ "$#" -ge 2 ] || usage; elided="$2"; shift 2 ;;
    --) shift; break ;;
    -*) usage ;;
    *) files+=("$1"); shift ;;
  esac
done
while [ "$#" -gt 0 ]; do files+=("$1"); shift; done
[ -n "$session" ] && [ "${#files[@]}" -gt 0 ] || usage
case "$elided" in ''|*[!0-9]*) usage ;; esac
elided=$((10#$elided))

for f in "${files[@]}"; do
  chunk_ok "$f" || { echo "merge-chunks: $f is not a usable chunk answer; refusing to merge around it" >&2; exit 3; }
done

jq -s --arg session "$session" --argjson elided "$elided" '
  def sev: if . == "high" then 0 elif . == "medium" then 1 elif . == "low" then 2 else 3 end;
  def arr: if type == "array" then . else [] end;
  def objs: arr | map(select(type == "object"));
  def strs: arr | map(select(type == "string"));
  def num: if type == "number" then . else 0 end;
  def sig($all; $k): [$all[] | .satisfaction_signals | (if type == "object" then .[$k] else null end) | num] | add;
  def clean: gsub("[\\x00-\\x1F\\x7F]"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "");
  def idea_identity: [.idea,.quote] | map(clean | ascii_downcase);
  def uniq_ordered: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
  def dedupe: reduce .[] as $f ({seen: {}, out: []};
      ((($f.category // "") | tostring) + "|" + (($f.what // "") | tostring)) as $k
      | if $k != "|" and .seen[$k] then . else (.seen[$k] = true | .out += [$f]) end) | .out;
  . as $all
  | ($all[0] + {
      session_path: $session,
      underlying_goal: ([$all[].underlying_goal | select(type == "string" and length > 0)] | .[0]),
      outcome: ([$all[].outcome | select(type == "string" and length > 0)] | .[-1]),
      notable_initiatives: ([$all[].notable_initiatives | strs | .[]] | uniq_ordered),
      instructions_given: ([$all[].instructions_given | strs | .[]] | uniq_ordered | .[0:3]),
      deferred_ideas: ([$all[].deferred_ideas | arr | .[]
        | select(type == "object"
          and (.idea | type == "string" and length > 0 and length <= 120 and (contains("\n") | not))
          and (.quote | type == "string" and length > 0 and length < 200))
        | select(.idea | clean | length > 0)]
        | reduce .[] as $idea ([]; if any(.[]; idea_identity == ($idea | idea_identity)) then . else . + [$idea] end)
        | .[0:3]),
      satisfaction_signals: {
        happy: sig($all; "happy"),
        satisfied: sig($all; "satisfied"),
        dissatisfied: sig($all; "dissatisfied"),
        frustrated: sig($all; "frustrated")
      },
      findings: ([$all | to_entries[] | .key as $i | (.value.findings | objs)[] | . + {chunk: ($i + 1)}]
                 | sort_by(.severity | sev) | dedupe | .[0:10]),
      meta: {chunks: ($all | length), chunks_elided: $elided}
    })' "${files[@]}"
