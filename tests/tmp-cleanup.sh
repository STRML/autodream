#!/bin/bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)

pass=0; fail=0
# shellcheck source=/dev/null
. "$HERE/lib-assert.sh"

# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp tmpclean

SUITES="adapter-contract lib-project adapters cookie-cadence preflight review-skip x-bookmarks run-all"

interrupt_suite() { # $1=suite -> sets $leftover, $alive
  local s="$1" root pid waited=0
  root=$(mktemp -d "$SUITE_TMP/$s.XXXXXX")
  set -m
  env -u RUNALL_SHARD -u RUNALL_LIST TMPDIR="$root" bash "$HERE/$s.sh" >/dev/null 2>&1 &
  pid=$!
  set +m
  while [ "$waited" -lt 2000 ]; do
    [ -n "$(ls -A "$root"/*/ 2>/dev/null)" ] && break
    sleep 0.005
    waited=$((waited + 1))
  done
  alive=0
  kill -TERM -- "-$pid" 2>/dev/null && alive=1
  wait "$pid" 2>/dev/null
  leftover=$(ls -A "$root" 2>/dev/null)
}

for s in $SUITES; do
  [ -f "$HERE/$s.sh" ] || { no "$s.sh exists"; continue; }
  tries=0
  while [ "$tries" -lt 5 ]; do
    interrupt_suite "$s"
    [ "$alive" = "1" ] && break
    tries=$((tries + 1))
  done
  if [ "$alive" != "1" ]; then
    no "$s was already gone when interrupted, so the check proves nothing"
  elif [ -n "$leftover" ]; then
    no "$s leaks its temp dir when interrupted (left: $leftover)"
  else
    ok "$s removes its temp dir when interrupted"
  fi
done

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
