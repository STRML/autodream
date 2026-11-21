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
# Nothing an unavailable check says counts as proof of death: a failed ps or stat leaves the holder
# alive and the directory young, and only a regular file or symlink at the path is refused outright.
#
# A directory with no pid is a writer that has not recorded one yet, or debris from a version that
# never wrote one. It is left alone until it is older than LOCK_NOPID_AGE seconds (default 3,
# which covers the gap between the mkdir and the pid write; question-streaks.sh passes 120 to keep
# its old reclaim-by-age bound for those).
#
# threads.sh does not use this: it holds an flock on an open file, which the kernel releases with
# the process, so there is no lock to go stale.

# shellcheck disable=SC2034 # set here, read by the script that sourced this
LOCK_HOLDER=""

lock_warn() { if declare -F log >/dev/null 2>&1; then log "$1"; else printf '%s\n' "$1" >&2; fi; }

proc_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }

# 0 = alive or cannot tell, 1 = gone. Only the kernel's own answer for a pid that does not exist
# counts as gone: kill -0 fails the same way with EPERM for another user's live process, and a ps
# that also fails says nothing, so any other failure reads as alive.
lock_pid_alive() { # $1=pid
  local err
  err=$(LC_ALL=C kill -0 "$1" 2>&1) && return 0
  case "$err" in *"No such process"*) return 1 ;; esac
  return 0
}

# 0 = the lock's holder is alive, 1 = gone (stale), 2 = the holder has not written its pid yet.
# Only evidence of death says 1. A start time that cannot be read now (ps failed) proves nothing,
# so it reads as alive: reclaiming on a failed lookup would evict a live holder (#192 review).
lock_holder_state() { # $1=lock dir
  local pid start now
  pid=$(cat "$1/pid" 2>/dev/null) || pid=""
  [ -n "$pid" ] || return 2
  lock_pid_alive "$pid" || return 1
  start=$(cat "$1/start" 2>/dev/null) || start=""
  [ -n "$start" ] || return 0
  now=$(proc_start "$pid")
  [ -z "$now" ] || [ "$now" = "$start" ]
}

# 0 when the lock directory is at least $2 seconds old, and only then. A directory whose age cannot be
# read is not old: a failed stat on a lock a holder made a moment ago must not hand it to a contender.
# At least, not more than: the mtime is whole seconds, so a directory made just before three
# one-second waits reads exactly 3 and must count as old, as it did when this was a tries count.
lock_aged() { # $1=lock dir $2=seconds
  local mtime now
  mtime=$(pstat_mtime "$1" 2>/dev/null) || return 1
  case "$mtime" in ""|*[!0-9]*) return 1 ;; esac
  now=$(date +%s)
  [ $((now - mtime)) -ge "$2" ]
}

# 0 when this process holds the lock: the pid file is readable and names $$. A missing or
# unreadable file is not ours.
lock_owned() { # $1=lock dir
  [ "$(cat "$1/pid" 2>/dev/null)" = "$$" ]
}

# Record this process as the holder without ever writing over another process's record: the
# noclobber write fails when a pid file is already there (our directory was reclaimed and made
# again by someone else between our mkdir and this write).
write_owner() { # $1=lock dir
  ( set -C; printf '%s\n' "$$" > "$1/pid" ) 2>/dev/null || return 1
  lock_owned "$1" || return 1
  proc_start "$$" > "$1/start" 2>/dev/null
  return 0
}

# Take a stale lock away. Reclaimers are serialized by a gate directory (lock.reclaim): one at a time
# judges the lock again under the gate and moves it aside, so no reclaimer can move a lock that a faster
# one has already replaced, and no lock is ever moved and then put back (every put-back was a window in
# which a record landed on another holder's path, review rounds 1 to 3 of #192). A gate left by a
# reclaimer that died is an empty directory with no meaning and is cleared once it is 30 seconds old.
# The one judgment that can still be wrong is a pid-less directory whose holder was merely slower than
# the age bound; that holder finds lock_owned false at its next check instead of sharing the lock.
# Only a real directory is moved: a regular file or symlink at the path is not a lock.
reclaim_lock() { # $1=lock dir $2=the pid judged stale ("" when none was ever written)
  [ -d "$1" ] && [ ! -L "$1" ] || return 0
  local gate="$1.reclaim" cur dead
  if [ -d "$gate" ] && lock_aged "$gate" 30; then rmdir "$gate" 2>/dev/null; fi
  mkdir "$gate" 2>/dev/null || return 0
  cur=$(cat "$1/pid" 2>/dev/null) || cur=""
  if [ "$cur" = "$2" ] && { [ -z "$2" ] || ! lock_pid_alive "$2"; }; then
    dead="$1.stale.$$.$SECONDS$RANDOM"
    mv "$1" "$dead" 2>/dev/null && rm -rf "$dead"
  fi
  rmdir "$gate" 2>/dev/null
  return 0
}

# 0 = taken, 1 = another live holder has it (its pid in LOCK_HOLDER), 3 = the lock cannot be made
# at all: a read-only state dir, or something other than a directory at the lock path.
# $2 is how many seconds to give a directory whose pid has not appeared yet (default 3).
acquire_lock() { # $1=lock dir [$2=seconds]
  mkdir -p "$(dirname "$1")" 2>/dev/null || return 3
  local tries=0 st pid nopid_age="${LOCK_NOPID_AGE:-3}" pwait="${2:-3}"
  case "$nopid_age" in ''|*[!0-9]*) nopid_age=3 ;; esac
  case "$pwait" in ''|*[!0-9]*) pwait=3 ;; esac
  while :; do
    if mkdir "$1" 2>/dev/null; then
      write_owner "$1" && return 0
      tries=$((tries + 1))
      [ "$tries" -lt 8 ] || return 3
      continue
    fi
    [ -d "$1" ] && [ ! -L "$1" ] || return 3
    pid=$(cat "$1/pid" 2>/dev/null) || pid=""
    lock_holder_state "$1"; st=$?
    [ "$st" -ne 0 ] || { LOCK_HOLDER="$pid"; return 1; }
    tries=$((tries + 1))
    if [ "$st" -eq 2 ] && ! lock_aged "$1" "$nopid_age"; then
      # A holder between its mkdir and its pid write, or an older writer's lock. Give the pid a
      # moment to appear; past that the directory is held by something we cannot name.
      [ "$tries" -le "$pwait" ] || { LOCK_HOLDER="unknown"; return 1; }
      sleep 1; continue
    fi
    reclaim_lock "$1" "$pid"
    [ "$tries" -lt 8 ] || { LOCK_HOLDER="${pid:-unknown}"; return 1; }
    # Still there: another reclaimer holds the gate. Give it a moment instead of spinning.
    [ ! -d "$1" ] || sleep 1
  done
}

# acquire_lock, retried once a second while another holder has it, until $2 seconds have passed.
# The deadline is the wall clock and each try is told how much of it is left, so a lock whose pid
# has not appeared yet cannot stretch the wait past it.
acquire_lock_wait() { # $1=lock dir $2=seconds
  local deadline=$((SECONDS + $2)) rc left
  while :; do
    left=$((deadline - SECONDS))
    [ "$left" -ge 0 ] || left=0
    [ "$left" -le 3 ] || left=3
    rc=0; acquire_lock "$1" "$left" || rc=$?
    [ "$rc" -eq 1 ] || return "$rc"
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 1
  done
}

# Only the owner removes it. 0 = released, 1 = not ours (left alone, whatever state it is in).
# run.sh installs this as an EXIT trap that a run which never took the lock reaches too, so a
# refusal is quiet here; a caller that took the lock and gets 1 has lost it and says so.
release_lock() { # $1=lock dir
  lock_owned "$1" || return 1
  rm -rf "$1"
}
