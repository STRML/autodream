#!/bin/bash
set -u

[ "$#" -eq 2 ] || { echo "linearize: usage: linearize.sh <src> <dst>" >&2; exit 1; }
src="$1"
dst="$2"

[ -r "$src" ] || { echo "linearize: cannot read $src" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "linearize: jq not found" >&2; exit 1; }
[ ! -d "$dst" ] || { echo "linearize: $dst is a directory" >&2; exit 1; }

if ! head -n 4 "$src" | jq -R -s -e '
      [ split("\n")[] | (try fromjson catch null) | select(type == "object") ]
      | any(.[]; .type == "session" and (.id | type) == "string")
    ' >/dev/null 2>&1; then
  echo "linearize: no omp session header in $src" >&2
  exit 2
fi

parent_candidate="$(dirname "$src").jsonl"
nested=false
parent=""
if [ -f "$parent_candidate" ]; then nested=true; parent="$parent_candidate"; fi
case "$(basename "$(dirname "$src")")" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z_*) nested=true ;;
esac
case "$(basename "$src")" in
  __advisor.jsonl|__advisor-*.jsonl) is_advisor=true ;;
  *) is_advisor=false ;;
esac

t=$(mktemp "$dst.tmp.XXXXXX" 2>/dev/null) || { echo "linearize: cannot create a temp beside $dst" >&2; exit 1; }

if ! jq -R -s -c \
      --arg src "$src" --argjson nested "$nested" --arg parent "$parent" \
      --argjson advisor "$is_advisor" '
  def bail($m): ($m + ": " + $src) | halt_error(4);

  [ split("\n")[] | select(test("^[[:space:]]*$") | not) | (try fromjson catch {"__autodream_bad": true}) ] as $rows
  | if any($rows[]; type == "object" and has("__autodream_bad")) then bail("unparseable line") else . end
  | if any($rows[]; type != "object") then bail("non-object line") else . end
  | ([ $rows[] | select(.type == "session") ] | first) as $head
  | [ $rows[] | select(.type != "session" and .type != "title") ] as $entries
  | if any($entries[]; (.id | type) != "string") then bail("entry without a string id") else . end
  | ($entries | length) as $n
  # Ids index the tree below, so a repeated id would let the later entry silently replace
  # the earlier one and put the walk on a chain the file does not show.
  | if ([ $entries[].id ] | length) != ([ $entries[].id ] | unique | length) then bail("duplicate entry id") else . end
  | ($entries | map({(.id): .}) | add // {}) as $by_id
  | (if $n == 0 then null else $entries[$n - 1].id end) as $leaf
  | ([ limit($n; $leaf | recurse(
           ($by_id[.].parentId // null) as $p
           | if $p == null then empty else $p end;
           true)) ]) as $ids
  # `recurse` follows a dangling parent id to a missing entry, which shows up below as
  # an id with no record. A cycle revisits an id, which the uniqueness check catches.
  | if ($ids | length) != ($ids | unique | length) then bail("parent cycle") else . end
  | if any($ids[]; $by_id[.] == null) then bail("dangling parentId") else . end
  | ([ $ids[] | $by_id[.] ] | reverse) as $chain
  | if ($chain | length) > 0 and (($chain[0].parentId // null) != null)
    then bail("chain does not reach a root (parent chain longer than the entries)") else . end
  | [{
      type: "autodream_meta",
      source: "omp",
      source_path: $src,
      nested: $nested,
      is_advisor: $advisor,
      parent_session_file: (if $parent == "" then null else $parent end),
      session_id: ($head.id // null),
      cwd: ($head.cwd // null),
      title: ($head.title // null),
      started_at: ($head.timestamp // null),
      entries: $n,
      on_path: ($chain | length),
      dropped: ($n - ($chain | length))
    }] + $chain
  | .[]
' "$src" > "$t" 2>/dev/null; then
  rm -f "$t"
  echo "linearize: refusing $src (unparseable line or broken entry tree)" >&2
  exit 4
fi

if [ ! -s "$t" ]; then
  rm -f "$t"
  echo "linearize: no output for $src" >&2
  exit 3
fi

mv -f "$t" "$dst" 2>/dev/null || { rm -f "$t"; exit 3; }
[ -f "$dst" ] || { rm -f "$dst/$(basename "$t")" 2>/dev/null; exit 3; }
