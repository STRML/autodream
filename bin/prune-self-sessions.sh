#!/bin/bash
set -u

usage() {
  cat <<'EOF'
# Find (and optionally delete) autodream's OWN session transcripts.
#
# Every `claude --print` worker autodream spawns used to persist its own session
# JSONL into ~/.claude/projects/-Users-<you>/. The next night's run would then
# triage those as if they were real sessions — ~190 self-generated files/night,
# ~90% of the corpus, pure noise and wasted model spend. run.sh now passes
# --no-session-persistence so new runs leave no full transcript, and now runs workers
# from an isolated cwd so even the residual AI-title stub lands in a bucket run.sh
# wipes. Older runs predating those fixes still littered the real session bucket with
# both full transcripts AND one-line ai-title stubs; this script cleans up both and is
# the single source of truth for the "is this one of ours?" predicate (run.sh
# calls `--filter`).
#
# Usage:
#   prune-self-sessions.sh                 # list self-sessions under $PROJECTS_DIR (dry run)
#   prune-self-sessions.sh --delete        # delete them
#   prune-self-sessions.sh --quiet         # just the summary line, no per-file paths
#   prune-self-sessions.sh /path/projects  # scan a specific projects dir
#   prune-self-sessions.sh --filter        # stdin: session paths; stdout: only NON-self ones
#   prune-self-sessions.sh --is-self F     # exit 0 if F is one of ours, 1 if not
#
# Env:
#   PROJECTS_DIR   default $HOME/.claude/projects
EOF
}

SELF_RE='"(content":"|text":")(Session transcript to analyze \(literal absolute path\)|Findings directory to aggregate \(literal absolute path\)|SESSION_PATH=|FINDINGS_DIR=)'

first_user_turn() {
  grep -m1 -E '"type":"user"|"type":"message".*"message":\{"role":"user"' "$1" 2>/dev/null
}

is_self_title() {
  first_user_turn "$1" | grep -q . && return 1
  local t
  t=$(sed -n 's/.*"aiTitle":"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1)
  [ -n "$t" ] || return 1
  printf '%s' "$t" | grep -qiE 'aggregate.*findings|findings.*(into|report)' && return 0
  printf '%s' "$t" | grep -qiE 'session triage|triage.*findings|findings.*extraction' && return 0
  printf '%s' "$t" | grep -qiE '(analyz|triag|process|review|debug).*(session|transcript)' \
    && printf '%s' "$t" | grep -qiE 'findings|transcript|triage|analysis|extract|emit|structured' \
    && return 0
  return 1
}

is_self() {
  first_user_turn "$1" | grep -qE "$SELF_RE" && return 0
  is_self_title "$1"
}

if [ "${1:-}" = "--is-self" ]; then
  [ -n "${2:-}" ] || { echo "usage: $0 --is-self <session.jsonl>" >&2; exit 2; }
  is_self "$2" && exit 0
  exit 1
fi

if [ "${1:-}" = "--filter" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_self "$f" || printf '%s\n' "$f"
  done
  exit 0
fi

DELETE=0; QUIET=0; SCAN_DIR=""
for a in "$@"; do
  case "$a" in
    --delete) DELETE=1 ;;
    --quiet)  QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) SCAN_DIR="$a" ;;
  esac
done
PROJECTS_DIR="${SCAN_DIR:-${PROJECTS_DIR:-$HOME/.claude/projects}}"

[ -d "$PROJECTS_DIR" ] || { echo "no such projects dir: $PROJECTS_DIR" >&2; exit 1; }

count=0; bytes=0
while IFS= read -r f; do
  is_self "$f" || continue
  count=$((count + 1))
  sz=$(wc -c < "$f" 2>/dev/null | tr -d ' '); bytes=$((bytes + ${sz:-0}))
  [ "$QUIET" = 1 ] || echo "$f"
  [ "$DELETE" = 1 ] && rm -f "$f"
done < <(find "$PROJECTS_DIR" -type f -name '*.jsonl' 2>/dev/null)

mb=$(( bytes / 1048576 ))
if [ "$DELETE" = 1 ]; then
  echo "deleted $count autodream-own session file(s) (~${mb} MB) under $PROJECTS_DIR"
else
  echo "found $count autodream-own session file(s) (~${mb} MB) under $PROJECTS_DIR  (re-run with --delete to remove)"
fi
