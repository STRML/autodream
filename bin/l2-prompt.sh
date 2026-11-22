#!/bin/bash
l2_system_prompt() {
  local self dir f
  self="${BASH_SOURCE[0]}"
  if [ -L "$self" ]; then
    f=$(readlink "$self")
    case "$f" in /*) self="$f" ;; *) self="$(dirname "$self")/$f" ;; esac
  fi
  dir=$(cd -P "$(dirname "$self")" 2>/dev/null && pwd) || dir=""
  for f in "$dir/../prompts/L2_SYSTEM.txt" "${AUTODREAM_DIR:-}/L2_SYSTEM.txt"; do
    if [ -r "$f" ] && grep -q '[^[:space:]]' "$f" 2>/dev/null; then cat "$f"; return 0; fi
  done
  echo "l2-prompt: prompts/L2_SYSTEM.txt not found or empty (looked beside ${dir:-the lib} and in AUTODREAM_DIR=${AUTODREAM_DIR:-unset})" >&2
  return 2
}
