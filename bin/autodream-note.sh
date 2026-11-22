#!/usr/bin/env bash
set -euo pipefail

_src="${BASH_SOURCE[0]}"; _lib="$(dirname "$_src")/lib-install-dir.sh"
[ -r "$_lib" ] || _lib="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/lib-install-dir.sh"
# shellcheck source=/dev/null
. "$_lib"
resolve_install_dir "$_src" autodream-note.sh
NOTES="${AUTODREAM_NOTES_FILE:-$AUTODREAM_DIR/notes.md}"
EXPIRES=""
if [ "${1:-}" = "--expires" ]; then EXPIRES="${2:-}"; shift 2; fi
TEXT="${*:-}"
[ -n "$TEXT" ] || { echo "usage: autodream-note.sh [--expires YYYY-MM-DD] \"note text\"" >&2; exit 2; }

mkdir -p "$(dirname "$NOTES")"
if [ ! -f "$NOTES" ]; then
  printf '# Operator notes for autodream\n\nFree-text notes the next run should address in its "Operator notes" section.\nFormat: `- [added] (expires DATE) text` — expiry optional; expired notes are ignored.\n\n' > "$NOTES"
fi

TODAY="$(date +%F)"
if [ -n "$EXPIRES" ]; then
  printf -- '- [%s] (expires %s) %s\n' "$TODAY" "$EXPIRES" "$TEXT" >> "$NOTES"
else
  printf -- '- [%s] %s\n' "$TODAY" "$TEXT" >> "$NOTES"
fi
echo "noted -> $NOTES"
