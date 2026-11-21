#!/bin/bash
# Unit tests for bin/lib-lock.sh: the one mkdir lock that run.sh (per-date run lock, per-label
# remote sync lock) and question-streaks.sh share (issue #192).
#
# A lock here is a directory holding its owner's pid and process start time. The failure matrix:
#
#   state                                    acquire                      release / owner check
#   free                                     takes it, writes pid+start   removes it
#   live holder (even one that stalled)      refuses, names the pid       -
#   holder gone, or its pid reused           reclaims                     -
#   dir with no pid, younger than the age    refuses (a holder is mid-    -
#                                            write or an old writer)
#   dir with no pid, older than the age      reclaims (debris)            -
#   lock replaced by another holder          -                            leaves it, returns 1
#   pid file missing or unreadable           -                            not ours: leaves it, returns 1
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp liblock
# shellcheck source=/dev/null
. "$REPO/bin/portable.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_eq(){ [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }

LIB="$REPO/bin/lib-lock.sh"
if [ ! -r "$LIB" ]; then
  printf '  FAIL - %s is missing; the rest of this suite would be vacuous\n' "$LIB"
  printf '\npassed: 0   failed: 1\n'
  exit 1
fi
# shellcheck source=/dev/null
. "$LIB"
for fn in acquire_lock acquire_lock_wait release_lock lock_owned lock_holder_state reclaim_lock proc_start; do
  if ! declare -F "$fn" >/dev/null 2>&1; then
    printf '  FAIL - %s is not defined; the rest of this suite would be vacuous\n' "$fn"
    printf '\npassed: 0   failed: 1\n'
    exit 1
  fi
done

D="$SUITE_TMP/locks"; mkdir -p "$D"
LOCK_ERR="$SUITE_TMP/lock.err"

# A process that owns a lock the way a real holder does: it takes it in its own shell, so the
# pid in the file is its own, and holds until killed.
start_holder() { # $1=lock dir -> prints the holder's pid once the lock is taken
  bash -c '. "$1"; acquire_lock "$2" || exit 9; exec sleep 300' _ "$LIB" "$1" >/dev/null 2>&1 &
  local pid=$!
  local i=0
  while [ ! -s "$1/start" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  printf '%s' "$pid"
}
stop_holder() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; return 0; }
age_dir() { touch -t 200001010000 "$1"; }   # a directory whose mtime is far in the past

echo "# lib-lock: take and release"
acquire_lock "$D/a.lock"; rc=$?
assert_eq "$rc" "0" "a free lock is taken"
assert_eq "$(cat "$D/a.lock/pid")" "$$" "the lock records this process's pid"
if [ -n "$(ps -o lstart= -p $$ 2>/dev/null)" ]; then
  [ -s "$D/a.lock/start" ] && ok "and its start time" || no "and its start time"
fi
lock_owned "$D/a.lock" && ok "lock_owned says it is ours" || no "lock_owned says it is ours"
release_lock "$D/a.lock"; rc=$?
assert_eq "$rc" "0" "release by the owner succeeds"
[ ! -e "$D/a.lock" ] && ok "and removes the directory" || no "and removes the directory"
acquire_lock "$D/no/such/parent/b.lock"; rc=$?
assert_eq "$rc" "0" "the lock's parent directory is made when missing"
release_lock "$D/no/such/parent/b.lock"

echo "# lib-lock: a live holder is never reclaimed, however old its lock looks (#192)"
holder=$(start_holder "$D/live.lock")
age_dir "$D/live.lock"
acquire_lock "$D/live.lock"; rc=$?
assert_eq "$rc" "1" "a live holder keeps the lock"
assert_eq "$LOCK_HOLDER" "$holder" "and acquire names its pid"
assert_eq "$(cat "$D/live.lock/pid")" "$holder" "the holder's lock was left alone"
release_lock "$D/live.lock"; rc=$?
assert_eq "$rc" "1" "release by a process that does not own it is refused"
[ -d "$D/live.lock" ] && ok "and leaves the holder's lock standing" || no "and leaves the holder's lock standing"
acquire_lock_wait "$D/live.lock" 1; rc=$?
assert_eq "$rc" "1" "acquire_lock_wait gives up after its budget while the holder lives"
stop_holder "$holder"

echo "# lib-lock: a dead holder, or a reused pid, is reclaimed"
holder=$(start_holder "$D/dead.lock"); stop_holder "$holder"
acquire_lock "$D/dead.lock"; rc=$?
assert_eq "$rc" "0" "a lock whose holder is gone is reclaimed"
assert_eq "$(cat "$D/dead.lock/pid")" "$$" "and now records the new owner"
release_lock "$D/dead.lock"
holder=$(start_holder "$D/reuse.lock")
printf 'Mon Jan  1 00:00:00 1990\n' > "$D/reuse.lock/start"
acquire_lock "$D/reuse.lock"; rc=$?
assert_eq "$rc" "0" "a live pid with a different start time is a stale lock"
release_lock "$D/reuse.lock"
stop_holder "$holder"

echo "# lib-lock: the owner check refuses a lock that is no longer ours"
holder=$(start_holder "$D/stolen.lock")   # B owns it
lock_owned "$D/stolen.lock"; rc=$?
assert_eq "$rc" "1" "another process's lock is not ours"
rm -f "$D/stolen.lock/pid"
lock_owned "$D/stolen.lock"; rc=$?
assert_eq "$rc" "1" "a missing pid file is not ours"
release_lock "$D/stolen.lock"; rc=$?
assert_eq "$rc" "1" "release with no pid file is refused"
[ -d "$D/stolen.lock" ] && ok "and does not remove the directory" || no "and does not remove the directory"
stop_holder "$holder"
if [ "$(id -u)" -ne 0 ]; then
  mkdir "$D/unreadable.lock"; printf '%s\n' "$$" > "$D/unreadable.lock/pid"; chmod 000 "$D/unreadable.lock/pid"
  lock_owned "$D/unreadable.lock"; rc=$?
  assert_eq "$rc" "1" "an unreadable pid file is not ours"
  release_lock "$D/unreadable.lock"; rc=$?
  assert_eq "$rc" "1" "release with an unreadable pid file is refused"
  [ -d "$D/unreadable.lock" ] && ok "and leaves the directory" || no "and leaves the directory"
  chmod 600 "$D/unreadable.lock/pid"; rm -rf "$D/unreadable.lock"
fi

echo "# lib-lock: a directory with no pid belongs to a writer that has not recorded it, or to debris"
mkdir "$D/bare.lock"
LOCK_NOPID_AGE=120 acquire_lock "$D/bare.lock"; rc=$?
assert_eq "$rc" "1" "a young pid-less directory is refused when the age bound is 120s"
[ -d "$D/bare.lock" ] && ok "and is left in place" || no "and is left in place"
age_dir "$D/bare.lock"
LOCK_NOPID_AGE=120 acquire_lock "$D/bare.lock"; rc=$?
assert_eq "$rc" "0" "an old pid-less directory is reclaimed as debris"
assert_eq "$(cat "$D/bare.lock/pid")" "$$" "and re-taken by the reclaimer"
release_lock "$D/bare.lock"

echo "# lib-lock: reclaiming never removes a lock another reclaimer already replaced"
holder=$(start_holder "$D/race.lock")
reclaim_lock "$D/race.lock" "999999"
assert_eq "$(cat "$D/race.lock/pid")" "$holder" "a reclaimer that judged a different pid puts the winner's lock back"
stop_holder "$holder"

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
