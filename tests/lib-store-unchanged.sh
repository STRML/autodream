#!/bin/bash
# Did a directory tree change between two moments? Two functions, because "changed" includes a file that
# is gone, a file that is new, and a file reached only through a symlinked directory below the root: a
# check that lists files newer than a marker sees none of the first and not all of the others.
#
#   store_snapshot <dir> <out>   writes one "size mtime_ns path" line per regular file under <dir>, following
#                                symlinks at every level, sorted. Returns 0 (written), 1 (could not scan) or
#                                2 (no such directory). Prints a reason on 1 and 2.
#   store_unchanged <before> <after>   0 when the two snapshots are identical, 1 with the differences printed.
#
# A store the snapshot cannot read is never a pass: path_state's "cannot tell" and an unreadable directory
# both return 1.
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
