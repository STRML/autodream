#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage: scheduler-label.sh <install-dir>
       scheduler-label.sh --plist <install-dir>

Decide which launchd label an install owns.

  <install-dir>
    stdout  the base label, on every path; the -review and .ondemand siblings suffix it
    exit 0  label decided
    exit 3  the default label is held by a plist running a different install. stdout
            still carries that label. A caller that would write the plist (install.sh)
            must abort on this status; autodream-now only borrows the label as a
            namespace and ignores it.

  --plist <install-dir>
    stdout  the path of the scheduled plist this install owns
    exit 0  found
    exit 1  this install has no scheduled job

Env: LAUNCH_AGENTS_DIR, PLISTBUDDY (tests point these at a sandbox).
EOF
}

set -euo pipefail

MODE=label
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --plist) MODE=plist; shift ;;
esac
TARGET="${1:?usage: scheduler-label.sh [--plist] <install-dir>}"
LA_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

norm_dir() {
  local d="${1%/}"
  ( cd "$d" 2>/dev/null && pwd -P ) || printf '%s\n' "$d"
}

TARGET_REAL="$(norm_dir "$TARGET")"
DEFAULT_LABEL="com.$(id -un | tr -dc 'a-zA-Z0-9').autodream"

runner_dir_of() {
  local plist="$1" i arg
  for i in 0 1 2 3 4 5; do
    arg="$("$PLISTBUDDY" -c "Print :ProgramArguments:$i" "$plist" 2>/dev/null)" || break
    case "$arg" in
      */run.sh) norm_dir "$(dirname "$arg")"; return 0 ;;
    esac
  done
  return 1
}

label=""
owner=""
conflict=""
for plist in "$LA_DIR"/*.plist; do
  [ -e "$plist" ] || continue
  l="$("$PLISTBUDDY" -c 'Print :Label' "$plist" 2>/dev/null)" || continue
  case "$l" in *.ondemand) continue ;; esac
  if rdir="$(runner_dir_of "$plist")" && [ "$rdir" = "$TARGET_REAL" ]; then
    label="$l"
    owner="$plist"
    break
  fi
  [ "$l" = "$DEFAULT_LABEL" ] && conflict="$plist"
done

if [ "$MODE" = plist ]; then
  [ -n "$owner" ] || exit 1
  printf '%s\n' "$owner"
  exit 0
fi

if [ -n "$label" ]; then
  printf '%s\n' "$label"
  exit 0
fi

if [ -n "$conflict" ]; then
  printf 'scheduler-label: %s is already scheduled by %s, which runs a different install.\n' \
    "$DEFAULT_LABEL" "$conflict" >&2
  printf 'scheduler-label: refusing to overwrite it. Give that job a distinct label, or re-run with --no-schedule.\n' >&2
  printf '%s\n' "$DEFAULT_LABEL"
  exit 3
fi

printf '%s\n' "$DEFAULT_LABEL"
