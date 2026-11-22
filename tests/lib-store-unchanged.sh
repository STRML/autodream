#!/bin/bash
HERE_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE_LIB/../bin/lib-path-state.sh"

store_snapshot() {
  local dir="$1" out="$2" st
  path_state "$dir"; st=$?
  if [ "$st" -eq 1 ]; then printf 'no store at %s, nothing to compare\n' "$dir"; return 2; fi
  if [ "$st" -eq 2 ]; then printf 'cannot tell whether %s exists (an unreachable path)\n' "$dir"; return 1; fi
  if ! [ -d "$dir" ] || ! [ -r "$dir" ] || ! [ -x "$dir" ]; then
    printf 'could not scan %s (not a readable directory)\n' "$dir"; return 1
  fi
  command -v python3 >/dev/null 2>&1 || { printf 'python3 is needed to snapshot %s\n' "$dir"; return 1; }
  if ! python3 - "$dir" > "$out.raw" 2> "$out.err" <<'PY'
import os, sys
root = sys.argv[1]
seen, errs = set(), []
def onerr(e):
    errs.append(str(e))
for d, dirs, files in os.walk(root, followlinks=True, onerror=onerr):
    real = os.path.realpath(d)
    if real in seen:
        dirs[:] = []
        continue
    seen.add(real)
    for f in files:
        p = os.path.join(d, f)
        try:
            st = os.stat(p)
        except OSError as exc:
            errs.append(str(exc))
            continue
        print("%d %d %s" % (st.st_size, st.st_mtime_ns, p))
if errs:
    sys.stderr.write("; ".join(errs[:3]) + "\n")
    sys.exit(1)
PY
  then
    printf 'could not scan %s: %s\n' "$dir" "$(head -c 200 "$out.err" | tr '\n' ' ')"
    rm -f "$out.raw" "$out.err"
    return 1
  fi
  sort "$out.raw" > "$out"; rm -f "$out.raw" "$out.err"
  return 0
}

store_unchanged() {
  local before="$1" after="$2" d
  d=$(diff "$before" "$after" 2>&1) && return 0
  printf 'the store changed: %s\n' "$(printf '%s\n' "$d" | grep '^[<>]' | head -5 | tr '\n' ' ')"
  return 1
}

store_verdict() {
  local dir="$1" brc="$2" bmsg="$3" bfile="$4" afile="$5" msg arc
  case "$brc" in
    0) ;;
    2) printf '%s\n' "$bmsg"; return 2 ;;
    *) printf '%s\n' "$bmsg"; return 1 ;;
  esac
  msg=$(store_snapshot "$dir" "$afile"); arc=$?
  if [ "$arc" -ne 0 ]; then
    printf 'the store at %s was there before the call and could not be scanned after it (%s)\n' "$dir" "$msg"
    return 1
  fi
  msg=$(store_unchanged "$bfile" "$afile") || { printf '%s\n' "$msg"; return 1; }
  printf 'nothing under %s changed (no file added, removed or modified)\n' "$dir"
  return 0
}
