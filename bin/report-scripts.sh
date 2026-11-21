#!/usr/bin/env bash
# report-scripts.sh — run the allowlisted report commands and leave their output where L2 can read it.
#
# WHY THIS EXISTS
#
# Operator notes keep asking the nightly run to "run X and quote the rows". L2 holds Read and Glob
# only, so it cannot, and the ask failed without a word. This collector runs the commands BEFORE L2
# and writes each result to <findings-dir>/report-<name>.md. A new report is one line in the
# allowlist, never a change to run.sh or the prompt.
#
# THE ALLOWLIST
#
#   $AUTODREAM_DIR/report-scripts.conf      one entry per line, `#` starts a comment line:
#     <name> <absolute-or-~/ path> [args...]
#
#   Args are literal words split on whitespace. Nothing is evaluated: no quotes, no `$VAR`, no glob,
#   no `;`. A missing conf is "no reports", never an error. Only the operator edits the conf, so an
#   operator note (which can come from a phone or a transcript) can never widen what runs.
#
# THE ALLOWLIST IS SNAPSHOT BEFORE ANY MODEL RUNS
#
# An L1 worker reads untrusted transcripts and holds the Write tool, so it could rewrite the conf, or a
# script the conf names, and this collector would then run the result with the operator's privileges.
# run.sh therefore calls `snapshot` before the first model call and keeps the output in memory, then
# hands it back to `collect`. The snapshot is each entry's line plus the sha256 of its script. `collect`
# runs only what the snapshot lists, and refuses (status `changed`, nothing executed) a script whose
# hash differs now, or that did not exist when the snapshot was taken. A `collect` with no snapshot
# (by hand) reads the conf and checks nothing, because nothing has run since you wrote it.
#
# What the hash covers, and what it does not: only the file named as the entry's path is pinned. An
# entry such as `name /usr/bin/python3 ~/x.py` pins python3 and leaves x.py, and anything a script
# sources or reads, writable by a worker, so interpreter-style entries are unprotected: give the
# conf the script itself, not an interpreter plus a file. And only the same-run window is defended:
# a worker that plants a conf entry on night N gets it snapshotted as trusted on night N+1, because
# nothing tells a planted line from one the operator wrote.
#
# THE FAILURE IS THE CONTENT
#
# A non-zero exit, a timeout, a missing or non-executable script, a relative path: each still writes
# report-<name>.md, with FAILED on the first body line, so L2 reports the failure instead of seeing
# silence. Same principle as x-bookmarks.sh. The collector itself exits 0 whatever the entries do and
# never aborts the run; it exits 1 only when it cannot write the findings dir.
#
# report-index.txt is the one fixed path L2 reads (PROMPT.md forbids globbing the findings dir: a
# directory listing stops at 200 entries). It lists every entry, its status and its file.
#
# Usage:
#   report-scripts.sh snapshot                          print the snapshot (run.sh holds it in memory)
#   report-scripts.sh collect <findings-dir> [snapshot-file]
#
# Config (env):
#   AUTODREAM_DIR                 default $HOME/.claude/autodream
#   AUTODREAM_REPORT_TIMEOUT      seconds per entry, then killed            default 60
#   AUTODREAM_REPORT_MAX_BYTES    cap on one report's body                  default 100000
#                                 (a command is also limited to 4x this per file it writes, stdout
#                                 and stderr included, so a command that never stops printing cannot
#                                 fill the disk before its timeout)
#   AUTODREAM_REPORT_KILL_GRACE   seconds between the TERM at the timeout and a KILL   default 5
#   AUTODREAM_REPORT_TIMEOUT_BIN  the timeout binary; set and empty uses the built-in watchdog
#                                 (default: timeout, then gtimeout, then the watchdog)

set -u
set -f   # args are literal words: a `*` in the conf must never glob

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
# Installed copies are symlinks: a merge updates them before install.sh links a new helper.
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"
CONF="$AUTODREAM_DIR/report-scripts.conf"
TIMEOUT_S="${AUTODREAM_REPORT_TIMEOUT:-60}"
MAX_BYTES="${AUTODREAM_REPORT_MAX_BYTES:-100000}"
case "$TIMEOUT_S" in ''|*[!0-9]*) TIMEOUT_S=60 ;; esac
case "$MAX_BYTES" in ''|*[!0-9]*) MAX_BYTES=100000 ;; esac
KILL_GRACE="${AUTODREAM_REPORT_KILL_GRACE:-5}"
case "$KILL_GRACE" in ''|*[!0-9]*) KILL_GRACE=5 ;; esac
# 10#: a value with a leading zero (08) is a number here, not a bad octal that aborts the collector.
TIMEOUT_S=$((10#$TIMEOUT_S)); MAX_BYTES=$((10#$MAX_BYTES)); KILL_GRACE=$((10#$KILL_GRACE))
[ "$TIMEOUT_S" -gt 0 ] || TIMEOUT_S=60
[ "$MAX_BYTES" -gt 0 ] || MAX_BYTES=100000
[ "$KILL_GRACE" -gt 0 ] || KILL_GRACE=5
FILE_LIMIT_KB=$((MAX_BYTES * 4 / 1024 + 1))
if [ -n "${AUTODREAM_REPORT_TIMEOUT_BIN+x}" ]; then TIMEOUT_BIN="$AUTODREAM_REPORT_TIMEOUT_BIN"
else TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"; fi

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# $1=path as written in the conf -> the absolute path it means ("~/" is HOME, anything else is kept)
expand_path() {
  case "$1" in
    \~/*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# $1=expanded path -> sha256 of the file, or "-" when it is not a readable absolute-path file
hash_of() {
  case "$1" in /*) ;; *) printf -- '-'; return 0 ;; esac
  [ -f "$1" ] && [ -r "$1" ] || { printf -- '-'; return 0; }
  shasum -a 256 -- "$1" 2>/dev/null | cut -d' ' -f1 | grep -E '^[0-9a-f]{64}$' || printf -- '-'
}

# $1=signal name, $2=pid -> the signal to the process and every descendant, children first
kill_tree() {
  local c
  for c in $(pgrep -P "$2" 2>/dev/null); do kill_tree "$1" "$c"; done
  kill -s "$1" "$2" 2>/dev/null
}

# $1=seconds, rest=command -> runs it bounded: TERM at the timeout, KILL KILL_GRACE seconds later.
# A command that traps or ignores TERM must not be able to hold the nightly run, and the processes
# it started must not outlive it (the timeout binary signals the whole group; the watchdog walks the tree).
run_bounded() {
  local secs="$1" pid wd rc; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" -k "$KILL_GRACE" "$secs" "$@"; return $?; fi
  "$@" & pid=$!
  # The watchdog traps TERM and takes its own sleep with it, so a command that finishes in time
  # leaves nothing behind, and a watchdog woken at that moment cannot fire at a recycled pid.
  ( trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    sleep "$secs" & sp=$!; wait "$sp" || exit 0
    kill_tree TERM "$pid"
    sleep "$KILL_GRACE" & sp=$!; wait "$sp" || exit 0
    kill_tree KILL "$pid" ) >/dev/null 2>&1 & wd=$!
  wait "$pid"; rc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return "$rc"
}

# Prints "#present" or "#absent" for the conf, then "<sha256 or ->\t<conf line>" per entry line.
snapshot() {
  [ -f "$CONF" ] || { printf '#absent\n'; return 0; }
  printf '#present\n'
  local line w2
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    [ $# -gt 0 ] || continue
    case "$1" in '#'*) continue ;; esac
    w2="${2:-}"
    printf '%s\t%s\n' "$(hash_of "$(expand_path "$w2")")" "$line"
  done < "$CONF"
}

collect() {
  local fdir="${1:-}" snapfile="${2:-}" checked=1
  [ -n "$fdir" ] && [ -d "$fdir" ] && [ -w "$fdir" ] || { echo "report-scripts: findings dir not writable: $fdir" >&2; return 1; }
  local work; work=$(mktemp -d "${TMPDIR:-/tmp}/report-scripts.XXXXXX") || { echo "report-scripts: no temp dir" >&2; return 1; }
  # A rerun of the same date must not leave the report of an entry that has left the conf.
  find "$fdir" -maxdepth 1 \( -name 'report-*.md' -o -name report-index.txt \) -exec rm -f {} + \
    || { echo "report-scripts: could not remove the earlier report files in $fdir" >&2; rm -rf "$work"; return 1; }

  local rows="$work/rows" n=0 line want lineno=0 name path cmd_text rc t0 reason status out err lname wfail=0 now
  local -a words args
  : > "$rows"
  local seen=" "

  # No snapshot means a manual run: read the conf now and skip the hash check.
  if [ -z "$snapfile" ]; then snapfile="$work/snapshot"; snapshot > "$snapfile"; checked=0; fi
  local state; state=$(sed -n 1p "$snapfile" 2>/dev/null)

  if [ "$state" = "#present" ]; then
    while IFS=$'\t' read -r want line || [ -n "$line" ]; do
      case "$want" in '#'*) continue ;; esac
      lineno=$((lineno + 1))
      read -r -a words <<< "$line"
      [ "${#words[@]}" -gt 0 ] || continue
      n=$((n + 1))
      name="${words[0]}"
      if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        printf '(entry %s)\tinvalid\t-\tname "%s" is not [A-Za-z0-9._-]\n' "$lineno" "$name" >> "$rows"; continue
      fi
      # Compared lowercased: Foo and foo are one file on a case-insensitive filesystem.
      lname=$(printf '%s' "$name" | tr 'A-Z' 'a-z')
      case "$seen" in *" $lname "*)
        printf '%s\tinvalid\t-\tduplicate name (names are compared ignoring case), the first entry keeps its file\n' "$name" >> "$rows"; continue ;;
      esac
      seen="$seen$lname "
      if [ "${#words[@]}" -lt 2 ]; then
        if write_report "$fdir" "$name" "(no command)" "not run" "FAILED: the entry has a name and no script path" "" ""; then
          printf '%s\tinvalid\t%s/report-%s.md\tno script path\n' "$name" "$fdir" "$name" >> "$rows"
        else
          wfail=1; printf '%s\twrite-failed\t-\tcould not write report-%s.md\n' "$name" "$name" >> "$rows"
        fi
        continue
      fi
      path=$(expand_path "${words[1]}")
      args=("${words[@]:2}")
      cmd_text="${words[*]:1}"

      status=ok; reason=""; rc=0; out="$work/out.$n"; err="$work/err.$n"; : > "$out"; : > "$err"
      case "$path" in
        /*) ;;
        *) status=invalid; reason="FAILED: not an absolute path ($path); write the full path or ~/..." ;;
      esac
      if [ "$status" = ok ] && [ ! -f "$path" ]; then status=missing; reason="FAILED: script not found: $path"; fi
      if [ "$status" = ok ] && [ ! -x "$path" ]; then status=missing; reason="FAILED: script is not executable: $path"; fi
      if [ "$status" = ok ] && [ "$checked" = 1 ]; then
        # Fail closed: run only when both hashes are real sha256 values and equal. A "-" on both
        # sides (hashing failed twice) must never read as "unchanged".
        now=$(hash_of "$path")
        if ! printf '%s' "$want" | grep -Eq '^[0-9a-f]{64}$' || [ "$now" != "$want" ]; then
          status=changed; reason="FAILED: the script changed since this run started, did not exist then, or could not be hashed; not run: $path"
        fi
      fi
      if [ "$status" != ok ]; then
        if write_report "$fdir" "$name" "$cmd_text" "not run" "$reason" "" ""; then
          printf '%s\t%s\t%s/report-%s.md\t%s\n' "$name" "$status" "$fdir" "$name" "${reason#FAILED: }" >> "$rows"
        else
          wfail=1; printf '%s\twrite-failed\t-\tcould not write report-%s.md\n' "$name" "$name" >> "$rows"
        fi
        continue
      fi

      t0=$SECONDS
      ( ulimit -f "$FILE_LIMIT_KB" 2>/dev/null; cd "$HOME" 2>/dev/null || cd /; run_bounded "$TIMEOUT_S" "$path" ${args[@]+"${args[@]}"} ) < /dev/null > "$out" 2> "$err"
      rc=$?
      if [ "$rc" -ne 0 ]; then
        if [ $((SECONDS - t0)) -ge "$TIMEOUT_S" ] && { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ "$rc" -eq 143 ]; }; then
          status=timeout; reason="FAILED: timed out after ${TIMEOUT_S}s and was killed"
        elif [ "$rc" -eq 153 ]; then
          status=failed; reason="FAILED: output exceeded the ${FILE_LIMIT_KB} KB per-file limit and was stopped (exit 153, SIGXFSZ)"
        else
          status=failed; reason="FAILED: exited $rc"
        fi
      fi
      if write_report "$fdir" "$name" "$cmd_text" "exit $rc" "$reason" "$out" "$err"; then
        printf '%s\t%s\t%s/report-%s.md\t%s\n' "$name" "$status" "$fdir" "$name" "$cmd_text" >> "$rows"
      else
        wfail=1; printf '%s\twrite-failed\t-\tcould not write report-%s.md\n' "$name" "$name" >> "$rows"
      fi
    done < <(sed 1d "$snapfile")
  fi

  local idx="$work/index"
  if [ "$n" -eq 0 ]; then
    case "$state" in
      '#present') printf '# report-scripts: none configured (%s has no entries)\n' "$CONF" > "$idx" ;;
      '#absent') printf '# report-scripts: none configured (no %s)\n' "$CONF" > "$idx" ;;
      *) printf '# report-scripts: unavailable (the allowlist %s could not be snapshotted before the run, so nothing was run)\n' "$CONF" > "$idx" ;;
    esac
  else
    printf '# report-scripts: %s entries from %s; columns: name, status, file, detail\n' "$n" "$CONF" > "$idx"
    cat "$rows" >> "$idx"
  fi
  cp "$idx" "$fdir/.report-index.tmp" && mv "$fdir/.report-index.tmp" "$fdir/report-index.txt" || wfail=1
  rm -rf "$work"
  return "$wfail"
}

# write_report <fdir> <name> <command text> <exit text> <failure line or ""> <stdout file or ""> <stderr file or "">
write_report() {
  local fdir="$1" name="$2" cmd="$3" exit_text="$4" failure="$5" out="$6" err="$7"
  local tmp="$fdir/.report-$name.tmp" size=0
  # Every write is checked on its own: the status of a brace group is its last command, and a
  # full disk can fail an earlier write while a later one succeeds.
  printf '# report-%s: %s | %s | %s\n' "$name" "$cmd" "$exit_text" "$(utc_now)" > "$tmp" || return 1
  if [ -n "$failure" ]; then printf '%s\n' "$failure" >> "$tmp" || return 1; fi
  if [ -n "$out" ] && [ -f "$out" ]; then
    size=$(wc -c < "$out" | tr -d ' ')
    if [ "$size" -gt "$MAX_BYTES" ]; then
      head -c "$MAX_BYTES" "$out" >> "$tmp" || return 1
      printf '\n[truncated at %s of %s bytes]\n' "$MAX_BYTES" "$size" >> "$tmp" || return 1
    else
      cat "$out" >> "$tmp" || return 1
    fi
  fi
  if [ -n "$failure" ] && [ -n "$err" ] && [ -s "$err" ]; then
    printf -- '--- stderr (last 20 lines) ---\n' >> "$tmp" || return 1
    tail -n 20 "$err" | head -c 4000 >> "$tmp" || return 1
  fi
  mv "$tmp" "$fdir/report-$name.md"
}

case "${1:-}" in
  snapshot) snapshot; exit $? ;;
  collect) shift; collect "$@"; exit $? ;;
  *) echo "usage: report-scripts.sh snapshot | collect <findings-dir> [snapshot-file]" >&2; exit 64 ;;
esac
