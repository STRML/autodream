#!/bin/bash
set -u

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

TS_DEF='def ts: (try .timestamp catch null)
  | select(type == "string")
  | try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch empty;'

usage() {
  cat <<'EOF'
usage: session-window.sh bounds DATE NEXT_DATE         print "START_EPOCH END_EPOCH"
       session-window.sh in-window FILE START END      exit 0 yes, 1 no, 2 error
       session-window.sh needs-slice FILE START END    exit 0 yes, 1 no, 2 error
       session-window.sh slice FILE START END          in-window lines on stdout (unmodified, bar one parentId)
       session-window.sh day-file FILE START END OUT   exit 0 wrote OUT, 1 no slice needed, 2 error

Local-day window over a session transcript: a record belongs to the day its top-level
`.timestamp` (ISO-8601 UTC string) falls in, [START, END) in epoch seconds. Contract:
tests/session-window.sh.
EOF
}

die_usage() { usage >&2; exit 2; }

is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

cmd="${1:-}"
case "$cmd" in
  bounds)
    [ "$#" -eq 3 ] || die_usage
    a=$(pdate_epoch "$2 00:00:00") || exit 1
    b=$(pdate_epoch "$3 00:00:00") || exit 1
    is_int "$a" && is_int "$b" && [ "$b" -gt "$a" ] || exit 1
    printf '%s %s\n' "$a" "$b"
    ;;
  in-window|needs-slice|slice|day-file)
    if [ "$cmd" = day-file ]; then [ "$#" -eq 5 ] || die_usage; else [ "$#" -eq 4 ] || die_usage; fi
    f="$2"; s="$3"; e="$4"
    is_int "$s" || die_usage
    is_int "$e" || die_usage
    [ -r "$f" ] || exit 2
    case "$cmd" in
      in-window)
        state=$(jq -R -n --argjson s "$s" --argjson e "$e" "$TS_DEF"'
          last(label $done | foreach (inputs | fromjson? | select(type == "object") | ts) as $t
            (0; if . == 2 then 2 elif ($t >= $s and $t < $e) then 2 else 1 end;
             ., (select(. == 2) | break $done))) // 0' "$f" 2>/dev/null) || exit 2
        case "$state" in
          2) exit 0 ;;
          1) exit 1 ;;
          0) ;;
          *) exit 2 ;;
        esac
        mt=$(pstat_mtime "$f") || exit 0
        case "$mt" in ''|*[!0-9]*) exit 0 ;; esac
        [ "$mt" -lt "$e" ] && exit 0
        exit 1
        ;;
      needs-slice)
        hit=$(jq -R -n --argjson s "$s" --argjson e "$e" "$TS_DEF"'
          first(inputs | fromjson? | select(type == "object") | ts | select(. < $s or . >= $e))' "$f" 2>/dev/null) || exit 2
        [ -n "$hit" ] && exit 0
        exit 1
        ;;
      slice)
        jq -R -n -r --argjson s "$s" --argjson e "$e" "$TS_DEF"'
          foreach inputs as $l ({kept: {}, out: null};
            (try ($l | fromjson) catch null) as $o
            | if ($o | type) != "object" then .out = null
              elif $o.type == "autodream_meta" then .out = $l
              else
                ([$o | ts][0]) as $t
                | if $t == null or $t < $s or $t >= $e then .out = null
                  else
                    (if ($o.parentId | type) == "string" and (.kept[$o.parentId] | not)
                       then ($o | .parentId = null | tojson) else $l end) as $line
                    | .out = $line
                    | (if ($o.id | type) == "string" then .kept[$o.id] = true else . end)
                  end
              end;
            .out | select(. != null))' "$f" 2>/dev/null || exit 2
        ;;
      day-file)
        out="$5"
        [ ! -d "$out" ] || exit 2
        bash "$0" needs-slice "$f" "$s" "$e"; rc=$?
        [ "$rc" -eq 0 ] || exit "$rc"
        t=$(mktemp "$out.tmp.XXXXXX" 2>/dev/null) || exit 2
        if bash "$0" slice "$f" "$s" "$e" > "$t" && [ -s "$t" ]; then
          touch -r "$f" "$t" 2>/dev/null
          mv -f "$t" "$out" 2>/dev/null || { rm -f "$t"; exit 2; }
          [ -f "$out" ] || { rm -f "$out/$(basename "$t")" 2>/dev/null; exit 2; }
          exit 0
        fi
        rm -f "$t"
        exit 2
        ;;
    esac
    ;;
  -h|--help) usage ;;
  *) die_usage ;;
esac
