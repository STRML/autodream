#!/bin/bash
set -u

usage_invalid() { printf 'invalid (%s)\n' "$1"; exit 2; }
[ "$#" -eq 3 ] || usage_invalid "usage: remote-sync.sh <label> <ssh-target:path> <mirror-dir>"
label=$1 target=$2 mirror=$3

case "$label" in ''|.|..|*[!A-Za-z0-9._-]*) usage_invalid "label must match [A-Za-z0-9._-]+" ;; esac
case "$target" in *:*) ;; *) usage_invalid "target must be host:path" ;; esac
host=${target%%:*} path=${target#*:}
case "$host" in ''|-*|*[!A-Za-z0-9._@-]*) usage_invalid "bad host" ;; esac
case "$path" in ''|-*|*[!A-Za-z0-9._/~+-]*) usage_invalid "bad path" ;; esac
[ -n "$mirror" ] || usage_invalid "empty mirror dir"

command -v rsync >/dev/null 2>&1 || { echo "failed (rsync not found)"; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "failed (ssh not found)"; exit 1; }

here=${BASH_SOURCE[0]%/*}; [ "$here" != "${BASH_SOURCE[0]}" ] || here=.
lib="$here/err-cause.sh"
if [ ! -r "$lib" ] && [ -L "${BASH_SOURCE[0]}" ]; then
  real=$(readlink "${BASH_SOURCE[0]}")
  case "$real" in /*) ;; *) real="$here/$real" ;; esac
  lib="${real%/*}/err-cause.sh"
fi
# shellcheck source=/dev/null
. "$lib" 2>/dev/null || { echo "failed (err-cause.sh not found beside remote-sync.sh)"; exit 1; }

mkdir -p "${mirror%/*}" 2>/dev/null || { echo "failed (cannot create ${mirror%/*})"; exit 1; }
errf=$(mktemp "${TMPDIR:-/tmp}/remote-sync.XXXXXX") || { echo "failed (mktemp)"; exit 1; }
trap 'rm -f "$errf"' EXIT

rsync -rt --timeout=60 \
  -e 'ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' \
  --include='*/' --include='*.jsonl' --exclude='*' --prune-empty-dirs \
  "$host:${path%/}/" "${mirror%/}/" 2> "$errf"
rc=$?
cat "$errf" >&2
tool_lines=$(grep -E '^(open)?rsync[(:]|^ssh:|Permission denied|^Host key|Connection (refused|closed|reset|timed out)|Could not resolve|No route to host|Operation timed out' \
  "$errf" 2>/dev/null)
if [ -n "$tool_lines" ]; then
  cause=$(printf '%s\n' "$tool_lines" | err_cause_line /dev/stdin)
else
  cause=$(err_cause_line "$errf")
fi

case "$rc" in
  0) echo ok; exit 0 ;;
  24) printf 'partial (%s)\n' "${cause:-a file vanished during the copy}"; exit 0 ;;
  23)
    if grep -qE '(change_dir|link_stat) .* failed: No such file|\(l\)stat: No such file' "$errf"; then
      printf 'failed (%s)\n' "${cause:-remote path not found}"; exit 1
    fi
    printf 'partial (%s)\n' "${cause:-some files were not transferred}"; exit 0 ;;
  30|35) echo "failed (timeout)"; exit 1 ;;
  *) printf 'failed (%s)\n' "${cause:-rsync exited $rc}"; exit 1 ;;
esac
