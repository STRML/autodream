#!/bin/bash
# The mkdir lock shared by run.sh (the per-date run lock and the per-label remote sync lock) and
# question-streaks.sh. Source it; every function takes the lock directory as $1.
#
# `mkdir` is the lock: atomic on every filesystem here, and needs no flock. The directory holds
# its owner's pid and process start time. A holder that is alive keeps the lock however long it
# holds it: only a holder that is gone (or whose pid now belongs to another process) is reclaimed.
# question-streaks.sh used to reclaim by directory age, so a holder that stalled past the bound
# lost its lock to a second writer while still running, and its release then removed the second
# writer's lock (#192). Liveness, not age, decides, and release and every write under the lock
# re-check ownership.
#
# A directory with no pid is a writer that has not recorded one yet, or debris from a version that
# never wrote one. It is left alone until it is older than LOCK_NOPID_AGE seconds (default 3,
# which covers the gap between the mkdir and the pid write; question-streaks.sh passes 120 to keep
# its old reclaim-by-age bound for those).
#
# threads.sh does not use this: it holds an flock on an open file, which the kernel releases with
# the process, so there is no lock to go stale.

LOCK_HOLDER=""

lock_warn() { if declare -F log >/dev/null 2>&1; then log "$1"; else printf '%s\n' "$1" >&2; fi; }

proc_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }

# 0 = the lock's holder is alive, 1 = gone (stale), 2 = the holder has not written its pid yet.
lock_holder_state() { # $1=lock dir
  local pid start
  pid=$(cat "$1/pid" 2>/dev/null) || pid=""
  [ -n "$pid" ] || return 2
  kill -0 "$pid" 2>/dev/null || return 1
  start=$(cat "$1/start" 2>/dev/null) || start=""
  # No recorded start (ps unavailable): the live pid is all there is to go on.
  [ -z "$start" ] || [ "$(proc_start "$pid")" = "$start" ]
}

# 0 when the lock directory is older than $2 seconds. A directory whose age cannot be read is old.
lock_aged() { # $1=lock dir $2=seconds
  local mtime now
  mtime=$(pstat_mtime "$1" 2>/dev/null) || return 0
  now=$(date +%s)
  [ $((now - mtime)) -gt "$2" ]
}

# 0 when this process holds the lock: the pid file is readable and names $$. A missing or
# unreadable file is not ours.
lock_owned() { # $1=lock dir
  [ "$(cat "$1/pid" 2>/dev/null)" = "$$" ]
}

# Move the stale lock aside (rename is atomic, so one reclaimer wins) rather than rmdir it:
# a second reclaimer that judged the same stale holder must not delete the winner's NEW lock.
reclaim_lock() { # $1=lock dir $2=the pid judged stale ("" when none was ever written)
  local dead="$1.stale.$$"
  mv "$1" "$dead" 2>/dev/null || return 0
  if [ "$(cat "$dead/pid" 2>/dev/null)" = "$2" ]; then
    rm -rf "$dead"
    return 0
  fi
  # We moved a lock that a faster reclaimer had already replaced. Put it back.
  mv "$dead" "$1" 2>/dev/null || { lock_warn "WARNING: could not restore another run's lock from $dead"; return 0; }
}

# 0 = taken, 1 = another live holder has it (its pid in LOCK_HOLDER), 3 = the lock's directory
# cannot be made at all (a read-only state dir).
acquire_lock() { # $1=lock dir
  mkdir -p "$(dirname "$1")" 2>/dev/null || return 3
  local tries=0 st pid nopid_age="${LOCK_NOPID_AGE:-3}"
  case "$nopid_age" in ''|*[!0-9]*) nopid_age=3 ;; esac
  until mkdir "$1" 2>/dev/null; do
    pid=$(cat "$1/pid" 2>/dev/null) || pid=""
    lock_holder_state "$1"; st=$?
    [ "$st" -ne 0 ] || { LOCK_HOLDER="$pid"; return 1; }
    tries=$((tries + 1))
    if [ "$st" -eq 2 ] && ! lock_aged "$1" "$nopid_age"; then
      # A holder between its mkdir and its pid write, or an older writer's lock. Give the pid a
      # moment to appear; past that the directory is held by something we cannot name.
      [ "$tries" -le 3 ] || { LOCK_HOLDER="unknown"; return 1; }
      sleep 1; continue
    fi
    reclaim_lock "$1" "$pid"
    [ "$tries" -lt 8 ] || { LOCK_HOLDER="${pid:-unknown}"; return 1; }
  done
  printf '%s\n' "$$" > "$1/pid"
  proc_start "$$" > "$1/start"
  return 0
}

# acquire_lock, retried once a second while a live holder has it, for up to $2 seconds.
acquire_lock_wait() { # $1=lock dir $2=seconds
  local waited=0 rc
  while :; do
    rc=0; acquire_lock "$1" || rc=$?
    [ "$rc" -eq 1 ] || return "$rc"
    [ "$waited" -lt "$2" ] || return 1
    sleep 1; waited=$((waited + 1))
  done
}

# Only the owner removes it. 0 = released, 1 = not ours (left alone, whatever state it is in).
# run.sh installs this as an EXIT trap that a run which never took the lock reaches too, so a
# refusal is quiet here; a caller that took the lock and gets 1 has lost it and says so.
release_lock() { # $1=lock dir
  lock_owned "$1" || return 1
  rm -rf "$1"
}
