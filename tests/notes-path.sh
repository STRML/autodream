#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WRITER="$REPO/bin/autodream-note.sh"

PASS=0
FAIL=0
tmproot="${TMPDIR:-/tmp}"
SANDBOX="$(mktemp -d "${tmproot%/}/notes-path.XXXXXX")"

export AUTODREAM_CONFIG="$SANDBOX/nonexistent-config"
trap 'rm -rf "$SANDBOX"' EXIT

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

printf 'notes-path\n'

INSTALL="$SANDBOX/install1/autodream"
mkdir -p "$INSTALL"
: > "$INSTALL/config"
mkdir -p "$SANDBOX/fakehome"
HOME="$SANDBOX/fakehome" AUTODREAM_DIR="$INSTALL" bash "$WRITER" "env-routed note" >/dev/null 2>&1
if [ -s "$INSTALL/notes.md" ] && grep -q "env-routed note" "$INSTALL/notes.md"; then
  ok "AUTODREAM_DIR from the environment routes the note there"
else
  nope "AUTODREAM_DIR from the environment routes the note there" "not in $INSTALL/notes.md"
fi
if [ -e "$SANDBOX/fakehome/.claude/autodream/notes.md" ]; then
  nope "the legacy path is not written when AUTODREAM_DIR is set" "legacy file exists"
else
  ok "the legacy path is not written when AUTODREAM_DIR is set"
fi

INSTALL2="$SANDBOX/install2/autodream"
mkdir -p "$INSTALL2"
: > "$INSTALL2/config"
ln -s "$WRITER" "$INSTALL2/autodream-note.sh"
( unset AUTODREAM_DIR; bash "$INSTALL2/autodream-note.sh" "symlink-routed note" ) >/dev/null 2>&1
if [ -s "$INSTALL2/notes.md" ] && grep -q "symlink-routed note" "$INSTALL2/notes.md"; then
  ok "an installed symlink routes the note to its own install dir"
else
  nope "an installed symlink routes the note to its own install dir" "not in $INSTALL2/notes.md"
fi

INSTALL3="$SANDBOX/install3/autodream"
mkdir -p "$INSTALL3"
: > "$INSTALL3/config"
ln -s "$WRITER" "$INSTALL3/autodream-note.sh"
ln -s "$REPO/bin/vault-notes.sh" "$INSTALL3/vault-notes.sh"

( unset AUTODREAM_DIR; bash "$INSTALL3/autodream-note.sh" "seam note" ) >/dev/null 2>&1
READER_SAYS="$( unset AUTODREAM_DIR; bash "$INSTALL3/vault-notes.sh" status 2>/dev/null | grep -m1 'notes file' )"

case "$READER_SAYS" in
  *"$INSTALL3/notes.md"*) ok "the reader names the same file the writer wrote, with no env set" ;;
  *) nope "the reader names the same file the writer wrote, with no env set" "reader said: ${READER_SAYS:-<no notes-file line>}" ;;
esac

if [ -s "$INSTALL3/notes.md" ] && grep -q "seam note" "$INSTALL3/notes.md"; then
  ok "the note landed in the install dir both halves resolve to"
else
  nope "the note landed in the install dir both halves resolve to" "missing from $INSTALL3/notes.md"
fi

printf '\npassed: %d   failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
