#!/bin/bash
resolve_install_dir() {
  local src="$1" name="${2:-}" dir
  [ -z "${AUTODREAM_DIR:-}" ] || return 0
  dir="$(cd "$(dirname "$src")" 2>/dev/null && pwd)"
  if [ -n "$dir" ] && { [ -f "$dir/config" ] || [ -f "$dir/PROMPT.md" ]; }; then
    AUTODREAM_DIR="$dir"
    return 0
  fi
  [ -z "$name" ] || echo "$name: WARNING no install markers next to $src; falling back to legacy $HOME/.claude/autodream" >&2
  AUTODREAM_DIR="$HOME/.claude/autodream"
}
