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
#   report-scripts.sh collect <findings-dir>
#
# Config (env):
#   AUTODREAM_DIR                 default $HOME/.claude/autodream
#   AUTODREAM_REPORT_TIMEOUT      seconds per entry, then killed            default 60
#   AUTODREAM_REPORT_MAX_BYTES    cap on one report's body                  default 100000

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
case "$TIMEOUT_S" in ''|*[!0-9]*|0) TIMEOUT_S=60 ;; esac
case "$MAX_BYTES" in ''|*[!0-9]*|0) MAX_BYTES=100000 ;; esac

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

collect() {
  local fdir="${1:-}"
  [ -n "$fdir" ] && [ -d "$fdir" ] && [ -w "$fdir" ] || { echo "report-scripts: findings dir not writable: $fdir" >&2; return 1; }
  local work; work=$(mktemp -d "${TMPDIR:-/tmp}/report-scripts.XXXXXX") || { echo "report-scripts: no temp dir" >&2; return 1; }
  # A rerun of the same date must not leave the report of an entry that has left the conf.
  find "$fdir" -maxdepth 1 \( -name 'report-*.md' -o -name report-index.txt \) -exec rm -f {} +

  local rows="$work/rows" n=0 line lineno=0 name path cmd_text rc t0 reason status out err
  local -a words args
  : > "$rows"
  local seen=" "

  if [ -f "$CONF" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))
      read -r -a words <<< "$line"
      [ "${#words[@]}" -gt 0 ] || continue
      case "${words[0]}" in '#'*) continue ;; esac
      n=$((n + 1))
      name="${words[0]}"
      if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        printf '(line %s)\tinvalid\t-\tname "%s" is not [A-Za-z0-9._-]\n' "$lineno" "$name" >> "$rows"; continue
      fi
      case "$seen" in *" $name "*)
        printf '%s\tinvalid\t-\tduplicate name, the first entry keeps report-%s.md\n' "$name" "$name" >> "$rows"; continue ;;
      esac
      seen="$seen$name "
      if [ "${#words[@]}" -lt 2 ]; then
        write_report "$fdir" "$name" "(no command)" "not run" "FAILED: the entry has a name and no script path" "" ""
        printf '%s\tinvalid\t%s/report-%s.md\tno script path\n' "$name" "$fdir" "$name" >> "$rows"; continue
      fi
      path="${words[1]}"
      args=("${words[@]:2}")
      cmd_text="${words[*]:1}"
      case "$path" in "~/"*) path="$HOME/${path#\~/}" ;; esac

      status=ok; reason=""; rc=0; out="$work/out.$n"; err="$work/err.$n"; : > "$out"; : > "$err"
      case "$path" in
        /*) ;;
        *) status=invalid; reason="FAILED: not an absolute path ($path); write the full path or ~/..." ;;
      esac
      if [ "$status" = ok ] && [ ! -f "$path" ]; then status=missing; reason="FAILED: script not found: $path"; fi
      if [ "$status" = ok ] && [ ! -x "$path" ]; then status=missing; reason="FAILED: script is not executable: $path"; fi
      if [ "$status" != ok ]; then
        write_report "$fdir" "$name" "$cmd_text" "not run" "$reason" "" ""
        printf '%s\t%s\t%s/report-%s.md\t%s\n' "$name" "$status" "$fdir" "$name" "${reason#FAILED: }" >> "$rows"; continue
      fi

      t0=$SECONDS
      ( cd "$HOME" 2>/dev/null || cd /; tmo "$TIMEOUT_S" "$path" ${args[@]+"${args[@]}"} ) < /dev/null > "$out" 2> "$err"
      rc=$?
      if [ "$rc" -ne 0 ]; then
        if [ $((SECONDS - t0)) -ge "$TIMEOUT_S" ] && { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ "$rc" -eq 143 ]; }; then
          status=timeout; reason="FAILED: timed out after ${TIMEOUT_S}s and was killed"
        else
          status=failed; reason="FAILED: exited $rc"
        fi
      fi
      write_report "$fdir" "$name" "$cmd_text" "exit $rc" "$reason" "$out" "$err"
      printf '%s\t%s\t%s/report-%s.md\t%s\n' "$name" "$status" "$fdir" "$name" "$cmd_text" >> "$rows"
    done < "$CONF"
  fi

  local idx="$work/index"
  if [ "$n" -eq 0 ]; then
    if [ -f "$CONF" ]; then
      printf '# report-scripts: none configured (%s has no entries)\n' "$CONF" > "$idx"
    else
      printf '# report-scripts: none configured (no %s)\n' "$CONF" > "$idx"
    fi
  else
    printf '# report-scripts: %s entries from %s; columns: name, status, file, detail\n' "$n" "$CONF" > "$idx"
    cat "$rows" >> "$idx"
  fi
  cp "$idx" "$fdir/.report-index.tmp" && mv "$fdir/.report-index.tmp" "$fdir/report-index.txt"
  rm -rf "$work"
  return 0
}

# write_report <fdir> <name> <command text> <exit text> <failure line or ""> <stdout file or ""> <stderr file or "">
write_report() {
  local fdir="$1" name="$2" cmd="$3" exit_text="$4" failure="$5" out="$6" err="$7"
  local tmp="$fdir/.report-$name.tmp" size=0
  {
    printf '# report-%s: %s | %s | %s\n' "$name" "$cmd" "$exit_text" "$(utc_now)"
    [ -n "$failure" ] && printf '%s\n' "$failure"
    if [ -n "$out" ] && [ -f "$out" ]; then
      size=$(wc -c < "$out" | tr -d ' ')
      if [ "$size" -gt "$MAX_BYTES" ]; then
        head -c "$MAX_BYTES" "$out"
        printf '\n[truncated at %s of %s bytes]\n' "$MAX_BYTES" "$size"
      else
        cat "$out"
      fi
    fi
    if [ -n "$failure" ] && [ -n "$err" ] && [ -s "$err" ]; then
      printf -- '--- stderr (last 20 lines) ---\n'
      tail -n 20 "$err" | head -c 4000
    fi
  } > "$tmp" && mv "$tmp" "$fdir/report-$name.md"
}

case "${1:-}" in
  collect) shift; collect "$@"; exit $? ;;
  *) echo "usage: report-scripts.sh collect <findings-dir>" >&2; exit 64 ;;
esac
