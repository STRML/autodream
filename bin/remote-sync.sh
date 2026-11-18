#!/bin/bash
# Pull one remote host's Claude Code transcripts into a local mirror (#226).
#
#   remote-sync.sh <label> <ssh-target:path> <mirror-dir>
#
# One way only: rsync over ssh reads the remote and writes the mirror, so nothing runs on the
# remote but sshd and a live session there never writes to a network filesystem. It asks for
# *.jsonl (transcripts and subagent sidecars) and nothing else, keeps mtimes (-t), because
# enumeration's lower bound is the file mtime, and never deletes: a transcript removed on the
# remote stays in the mirror. rsync writes each file to a dot-named temp and renames it, so a copy
# killed mid-file leaves the old file whole plus a `.name.jsonl.XXXXXX` temp, which is not
# `*.jsonl` and is never enumerated.
#
# Prints exactly one status line on stdout:
#   ok
#   partial (<cause>)   rsync 24 (a file vanished mid-copy), or 23 for a file it could not read
#   failed (<cause>)    everything else, a remote root that does not exist included
#   invalid (<why>)     the label or the target was refused before any ssh
# The cause is the first meaningful line of rsync's stderr (ssh's own error comes first when the
# connection fails), cleaned like the changelog's git causes. Exit 0 for ok and partial, 1 for
# failed, 2 for invalid. rsync's whole stderr also goes to this script's stderr.
set -u

usage_invalid() { printf 'invalid (%s)\n' "$1"; exit 2; }
[ "$#" -eq 3 ] || usage_invalid "usage: remote-sync.sh <label> <ssh-target:path> <mirror-dir>"
label=$1 target=$2 mirror=$3

# The label names a directory under remote/ and a lock, so it is a plain name and never . or ..
case "$label" in ''|.|..|*[!A-Za-z0-9._-]*) usage_invalid "label must match [A-Za-z0-9._-]+" ;; esac
case "$target" in *:*) ;; *) usage_invalid "target must be host:path" ;; esac
host=${target%%:*} path=${target#*:}
# A host that starts with - would reach ssh as an option. The path reaches the remote shell
# (openrsync does not quote it), so it is held to the characters a projects path needs.
case "$host" in ''|-*|*[!A-Za-z0-9._@-]*) usage_invalid "bad host" ;; esac
case "$path" in ''|-*|*[!A-Za-z0-9._/~+-]*) usage_invalid "bad path" ;; esac
[ -n "$mirror" ] || usage_invalid "empty mirror dir"

# Builtins only up to here, so a PATH without rsync or ssh is reported, not crashed on.
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

# Only the parent: rsync makes the mirror itself, so a first sync that fails leaves no empty mirror
# for the run to scan.
mkdir -p "${mirror%/*}" 2>/dev/null || { echo "failed (cannot create ${mirror%/*})"; exit 1; }
errf=$(mktemp "${TMPDIR:-/tmp}/remote-sync.XXXXXX") || { echo "failed (mktemp)"; exit 1; }
trap 'rm -f "$errf" "$errf.tool"' EXIT

# BatchMode: no password or passphrase prompt, which under launchd would hang the night.
# ConnectTimeout bounds a host that is asleep; the keepalives and --timeout bound a stalled copy.
rsync -rt --timeout=60 \
  -e 'ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' \
  --include='*/' --include='*.jsonl' --exclude='*' --prune-empty-dirs \
  "$host:${path%/}/" "${mirror%/}/" 2> "$errf"
rc=$?
cat "$errf" >&2
# An ssh config's Match exec or ProxyCommand can print its own noise ahead of the real error
# (a killed `nc -z` probe prints a bash "Alarm clock" line), so a line from rsync or ssh wins.
grep -E '^(open)?rsync[(:]|^ssh:|Permission denied|^Host key|Connection (refused|closed|reset|timed out)|Could not resolve|No route to host|Operation timed out' \
  "$errf" > "$errf.tool" 2>/dev/null
if [ -s "$errf.tool" ]; then cause=$(err_cause_line "$errf.tool"); else cause=$(err_cause_line "$errf"); fi

case "$rc" in
  0) echo ok; exit 0 ;;
  24) printf 'partial (%s)\n' "${cause:-a file vanished during the copy}"; exit 0 ;;
  23)
    # 23 is "some files were not transferred", which both rsyncs also return when the source
    # root itself does not exist. That is a host with nothing to read, not a partial copy.
    if grep -qE '(change_dir|link_stat) .* failed: No such file|\(l\)stat: No such file' "$errf"; then
      printf 'failed (%s)\n' "${cause:-remote path not found}"; exit 1
    fi
    printf 'partial (%s)\n' "${cause:-some files were not transferred}"; exit 0 ;;
  30|35) echo "failed (timeout)"; exit 1 ;;
  *) printf 'failed (%s)\n' "${cause:-rsync exited $rc}"; exit 1 ;;
esac
