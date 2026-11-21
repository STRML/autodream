#!/bin/bash
# One flock(2) for the scripts that serialize a read-modify-write on a state file: question-streaks.sh
# and threads.sh. Source it, then:
#
#   flock_acquire <lock file> <seconds> [<legacy lock directory>]
#   flock_release
#
# The shell opens the lock file on fd 9 and a short python3 call takes LOCK_EX|LOCK_NB on that open
# file description, retrying until the deadline. The kernel releases the lock when the description is
# closed, which happens when the process ends however it ends, so there is nothing to judge, reclaim,
# age out or put back. The mkdir lock this replaces was reclaimed by contenders that judged its holder
# gone, and a shell cannot make "judge, then take away" atomic: four gate rounds on #192 each found
# another interleaving.
#
# Return codes of flock_acquire:
#   0 taken
#   1 held by another process for the whole wait
#   2 cannot lock: the file cannot be opened, or the lock call failed for a reason other than contention
#   3 python3 is not on PATH
#   4 this process already holds a lock (a second `exec 9>>` would close the first description and
#     drop the first lock, so a double acquire is refused rather than allowed to unlock the outer one)
#   5 an older version's lock directory is still live (see below)
#
# The legacy directory is the one age judgment left. An older writer held it as a mkdir lock, so a
# directory younger than 300 s is read as that writer still running, one whose age cannot be read is
# read as live, and an older one is ignored and never removed. It is checked inside the same deadline
# loop, after the flock is taken. An old writer that creates its directory after the check, or one
# stalled past 300 s, is not covered: the upgrade window bounds both.
#
# Every child started while the lock is held inherits fd 9 and so keeps the lock alive if it outlives
# the holder. Run any child that can run long (a notification, a browser) with `9>&-`.

FLOCK_HELD=""

flock_acquire() { # $1=lock file $2=seconds $3=legacy lock directory
  local file="$1" wait="${2:-0}" legacy="${3:-}" rc
  [ -z "$FLOCK_HELD" ] || return 4
  command -v python3 >/dev/null 2>&1 || return 3
  if ! { exec 9>>"$file"; } 2>/dev/null; then
    return 2
  fi
  python3 -c '
import fcntl, os, stat, sys, time
legacy = sys.argv[2]

def legacy_live():
    if not legacy:
        return False
    try:
        st = os.stat(legacy)
    except FileNotFoundError:
        return False
    except OSError:
        return True
    if not stat.S_ISDIR(st.st_mode):
        return False
    return time.time() - st.st_mtime < 300

try:
    deadline = time.time() + float(sys.argv[1])
    while True:
        try:
            fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if not legacy_live():
                sys.exit(0)
            fcntl.flock(9, fcntl.LOCK_UN)
            code = 15
        except BlockingIOError:
            code = 11
        if time.time() >= deadline:
            sys.exit(code)
        time.sleep(0.2)
except SystemExit:
    raise
except BaseException:
    sys.exit(2)
' "$wait" "$legacy"
  rc=$?
  case "$rc" in
    0) ;;
    11) exec 9>&-; return 1 ;;
    15) exec 9>&-; return 5 ;;
    *) exec 9>&-; return 2 ;;
  esac
  FLOCK_HELD="$file"
  return 0
}

flock_release() {
  exec 9>&-
  FLOCK_HELD=""
  return 0
}
