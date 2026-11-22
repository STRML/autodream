#!/bin/bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=bin/portable.sh
. "$REPO/bin/portable.sh"
# shellcheck source=tests/lib-tmp.sh
. "$HERE/lib-tmp.sh"
suite_tmp adweb
pass=0; fail=0
_run() {
  local output rc=0 counts p f
  output=$(tmo "${2:-90}" env PYTHONDONTWRITEBYTECODE=1 python3 "$HERE/$1") || rc=$?
  printf '%s\n' "$output"
  counts=$(printf '%s\n' "$output" | sed -n 's/^passed: \([0-9]*\)   failed: \([0-9]*\)$/\1 \2/p' | tail -1)
  if [ -z "$counts" ]; then fail=$((fail + 1)); return; fi
  read -r p f <<< "$counts"
  pass=$((pass + p)); fail=$((fail + f))
  if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then fail=$((fail + 1)); fi
}
_run autodream-web-data.py
_run autodream-web.py
_run autodream-web-browser.py 330
printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
