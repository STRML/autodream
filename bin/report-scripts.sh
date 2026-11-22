#!/usr/bin/env bash
set -u
set -f   # args are literal words: a `*` in the conf must never glob

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
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
TIMEOUT_S=$((10#$TIMEOUT_S)); MAX_BYTES=$((10#$MAX_BYTES)); KILL_GRACE=$((10#$KILL_GRACE))
[ "$TIMEOUT_S" -gt 0 ] || TIMEOUT_S=60
[ "$MAX_BYTES" -gt 0 ] || MAX_BYTES=100000
[ "$KILL_GRACE" -gt 0 ] || KILL_GRACE=5
FILE_LIMIT_KB=$((MAX_BYTES * 4 / 1024 + 1))

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

expand_path() {
  case "$1" in
    \~/*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

hash_of() {
  case "$1" in /*) ;; *) printf -- '-'; return 0 ;; esac
  [ -f "$1" ] && [ -r "$1" ] || { printf -- '-'; return 0; }
  shasum -a 256 -- "$1" 2>/dev/null | cut -d' ' -f1 | grep -E '^[0-9a-f]{64}$' || printf -- '-'
}

tree_pids() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do tree_pids "$c"; done
  printf '%s\n' "$1"
}

settle_tree() {
  local p alive i=0 limit=$((KILL_GRACE * 10))
  while [ "$i" -lt "$limit" ]; do
    alive=0
    for p in $(cat "$1" 2>/dev/null); do if kill -0 "$p" 2>/dev/null; then alive=1; fi; done
    [ "$alive" = 0 ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  for p in $(cat "$1" 2>/dev/null); do kill -s KILL "$p" 2>/dev/null || true; done
}

run_bounded() {
  local secs="$1" flag="$2" pid wd rc; shift 2
  "$@" & pid=$!
  ( trap 'kill "${sp:-}" 2>/dev/null; exit 0' TERM
    sleep "$secs" & sp=$!; wait "$sp" || exit 0
    tree=$(tree_pids "$pid")
    printf '%s\n' "$tree" > "$flag"
    for p in $tree; do kill -s TERM "$p" 2>/dev/null || true; done
    sleep "$KILL_GRACE" & sp=$!; wait "$sp" || exit 0
    for p in $tree; do kill -s KILL "$p" 2>/dev/null || true; done ) >/dev/null 2>&1 & wd=$!
  wait "$pid"; rc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  if [ -s "$flag" ]; then settle_tree "$flag"; fi
  return "$rc"
}

entry_hash() {
  local path="$1" h f fh a parts=""; shift
  h=$(hash_of "$path")
  if [ "$h" = "-" ]; then printf -- '-'; return 0; fi
  for a in "$@"; do
    f=$(expand_path "$a")
    case "$f" in /*) ;; *) f="$HOME/$f" ;; esac
    [ -f "$f" ] || continue
    fh=$(hash_of "$f")
    if [ "$fh" = "-" ]; then printf -- '-'; return 0; fi
    parts="$parts$f $fh"$'\n'
  done
  if [ -z "$parts" ]; then printf '%s' "$h"; return 0; fi
  printf '%s\n%s' "$h" "$parts" | shasum -a 256 2>/dev/null | cut -d' ' -f1 | grep -E '^[0-9a-f]{64}$' || printf -- '-'
}

snapshot() {
  [ -f "$CONF" ] || { printf '#absent\n'; return 0; }
  printf '#present\n'
  local line w2
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    [ $# -gt 0 ] || continue
    case "$1" in '#'*) continue ;; esac
    w2="${2:-}"
    if [ $# -ge 3 ]; then
      printf '%s\t%s\n' "$(entry_hash "$(expand_path "$w2")" "${@:3}")" "$line"
    else
      printf '%s\t%s\n' "$(entry_hash "$(expand_path "$w2")")" "$line"
    fi
  done < "$CONF"
}

collect() {
  local fdir="${1:-}" snapfile="${2:-}" checked=1
  [ -n "$fdir" ] && [ -d "$fdir" ] && [ -w "$fdir" ] || { echo "report-scripts: findings dir not writable: $fdir" >&2; return 1; }
  local work; work=$(mktemp -d "${TMPDIR:-/tmp}/report-scripts.XXXXXX") || { echo "report-scripts: no temp dir" >&2; return 1; }
  find "$fdir" -maxdepth 1 \( -name 'report-*.md' -o -name report-index.txt \) -exec rm -f {} + \
    || { echo "report-scripts: could not remove the earlier report files in $fdir" >&2; rm -rf "$work"; return 1; }

  local rows="$work/rows" n=0 line want lineno=0 name path cmd_text rc reason status out err lname wfail=0 now tflag
  local -a words args
  : > "$rows"
  local seen=" "

  if [ -z "$snapfile" ]; then
    snapfile="$work/snapshot"; checked=0
    snapshot > "$snapfile" || printf '#unavailable\n' > "$snapfile"
  fi
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
        now=$(entry_hash "$path" ${args[@]+"${args[@]}"})
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

      tflag="$work/timeout.$n"; : > "$tflag"
      ( ulimit -f "$FILE_LIMIT_KB" 2>/dev/null; cd "$HOME" 2>/dev/null || cd /; run_bounded "$TIMEOUT_S" "$tflag" "$path" ${args[@]+"${args[@]}"} ) < /dev/null > "$out" 2> "$err"
      rc=$?
      if [ -s "$tflag" ]; then
        status=timeout; reason="FAILED: timed out after ${TIMEOUT_S}s and was stopped (exit $rc)"
      elif [ "$rc" -eq 153 ]; then
        status=failed; reason="FAILED: output exceeded the ${FILE_LIMIT_KB} KB per-file limit and was stopped (exit 153, SIGXFSZ)"
      elif [ "$rc" -ne 0 ]; then
        status=failed; reason="FAILED: exited $rc"
      fi
      if write_report "$fdir" "$name" "$cmd_text" "exit $rc" "$reason" "$out" "$err"; then
        printf '%s\t%s\t%s/report-%s.md\t%s\n' "$name" "$status" "$fdir" "$name" "$cmd_text" >> "$rows"
      else
        wfail=1; printf '%s\twrite-failed\t-\tcould not write report-%s.md\n' "$name" "$name" >> "$rows"
      fi
    done < "$snapfile"   # its first line is the #present marker, which the loop skips as a comment
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
    cat "$rows" >> "$idx" || wfail=1
    [ "$(wc -l < "$rows" | tr -d ' ')" = "$n" ] || wfail=1
  fi
  cp "$idx" "$fdir/.report-index.tmp" && mv "$fdir/.report-index.tmp" "$fdir/report-index.txt" || wfail=1
  rm -rf "$work"
  return "$wfail"
}

write_report() {
  local fdir="$1" name="$2" cmd="$3" exit_text="$4" failure="$5" out="$6" err="$7"
  local tmp="$fdir/.report-$name.tmp" size=0
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
