#!/bin/bash
# store_unchanged <dir> <marker>: did anything under <dir> change after <marker> was touched?
# Prints one line and returns 0 (nothing changed), 1 (something changed, or the directory could not be
# scanned) or 2 (there is no such directory, so there is nothing to compare). A scan that cannot look is
# never a pass: an unreadable store and a failed find both return 1.
store_unchanged() {
  local dir="$1" marker="$2" out rc
  if [ ! -e "$dir" ]; then
    printf 'no store at %s, nothing to compare\n' "$dir"
    return 2
  fi
  if ! [ -d "$dir" ] || ! [ -r "$dir" ] || ! [ -x "$dir" ]; then
    printf 'could not scan %s (not a readable directory)\n' "$dir"
    return 1
  fi
  out=$(find -H "$dir" -newer "$marker" -type f 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'could not scan %s (find exited %s): %s\n' "$dir" "$rc" "$(printf '%s' "$out" | head -c 200 | tr '\n' ' ')"
    return 1
  fi
  if [ -n "$out" ]; then
    printf 'files under %s changed: %s\n' "$dir" "$(printf '%s\n' "$out" | head -5 | tr '\n' ' ')"
    return 1
  fi
  printf 'nothing under %s changed\n' "$dir"
  return 0
}
