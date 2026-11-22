#!/bin/bash
FLOCK_HELD=""

flock_acquire() { # $1=lock file $2=seconds $3=legacy lock directory
  local file="$1" wait="${2:-0}" legacy="${3:-}" res
  [ -z "$FLOCK_HELD" ] || return 4
  command -v python3 >/dev/null 2>&1 || return 3
  if [ -e "$file" ] && [ ! -f "$file" ]; then
    return 2
  fi
  if ! { exec 9>>"$file"; } 2>/dev/null; then
    return 2
  fi
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
