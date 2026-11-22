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
# directory younger than 300 s is read as that writer still running (5), one whose state cannot be
# read (a symlink loop, a permission error) is cannot-lock (2), a permanent state to report and not a
# live writer, and an older one is ignored and never removed. It is checked inside the same deadline
# loop, after the flock is taken. An old writer that creates its directory after the check, or one
# stalled past 300 s, is not covered: the upgrade window bounds both.
#
# Every child started while the lock is held inherits fd 9 and so keeps the lock alive if it outlives
# the holder. The short-lived ones (awk, jq, mktemp, cp) are accepted: a hung one under a killed writer
# keeps the lock, and the next run skips loudly instead of racing it. Run any child that can run long (a
# notification, a browser) with `9>&-`.

FLOCK_HELD=""

flock_acquire() { # $1=lock file $2=seconds $3=legacy lock directory
  local file="$1" wait="${2:-0}" legacy="${3:-}" res
  [ -z "$FLOCK_HELD" ] || return 4
  command -v python3 >/dev/null 2>&1 || return 3
  # Opening a FIFO for writing blocks until a reader appears, before any deadline exists. Only a
  # regular file (or none yet) is a lock file.
  if [ -e "$file" ] && [ ! -f "$file" ]; then
    return 2
  fi
  if ! { exec 9>>"$file"; } 2>/dev/null; then
    return 2
  fi
  # The answer is a word on stdout, not an exit code: a python3 that is broken, or a stand-in that
  # exits with a number this file uses, must read as cannot-lock, never as a live holder.
  res=$(python3 -c '
import fcntl, os, stat, sys, time
legacy = sys.argv[2]

def legacy_state():
    # "none" no older writer, "live" one is running, "unknown" the directory cannot be read (a symlink loop,
    # a permission error): not proof of a writer, and a permanent state to report, not to skip quietly.
    if not legacy:
        return "none"
    try:
        st = os.stat(legacy)
    except FileNotFoundError:
        return "none"
    except OSError:
        return "unknown"
    if not stat.S_ISDIR(st.st_mode):
        return "none"
    return "live" if time.time() - st.st_mtime < 300 else "none"

try:
    end = time.monotonic() + float(sys.argv[1])
    while True:
        try:
            fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
            seen = legacy_state()
            if seen == "none":
                print("flock-ok")
                sys.exit(0)
            fcntl.flock(9, fcntl.LOCK_UN)
            if seen == "unknown":
                print("flock-unknown")
                sys.exit(0)
            word = "flock-legacy"
        except BlockingIOError:
            word = "flock-held"
        left = end - time.monotonic()
        if left <= 0:
            print(word)
            sys.exit(0)
        time.sleep(min(0.2, left))
except SystemExit:
    raise
except BaseException:
    sys.exit(2)
' "$wait" "$legacy" 2>/dev/null) || res=""
  case "$res" in
    flock-ok) FLOCK_HELD="$file"; return 0 ;;
    flock-held) exec 9>&-; return 1 ;;
    flock-legacy) exec 9>&-; return 5 ;;
    flock-unknown) exec 9>&-; return 2 ;;
    *) exec 9>&-; return 2 ;;
  esac
}

flock_release() {
  exec 9>&-
  FLOCK_HELD=""
  return 0
}
