#!/bin/bash
set -u

AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"
DEST="$AUTODREAM_DIR/cc-autodream.app"
PB=/usr/libexec/PlistBuddy
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -d "$DEST" ] && [ "$FORCE" -eq 0 ]; then
  echo "make-notifier.sh: $DEST already exists (use --force to rebuild)"
  exit 0
fi

SRC="$(brew --prefix terminal-notifier 2>/dev/null)/terminal-notifier.app"
if [ ! -d "$SRC" ]; then
  TN="$(command -v terminal-notifier || true)"
  [ -n "$TN" ] && SRC="$(cd "$(dirname "$(readlink -f "$TN" 2>/dev/null || echo "$TN")")/.." && pwd)/terminal-notifier.app"
fi
if [ ! -d "$SRC" ]; then
  echo "make-notifier.sh: terminal-notifier not installed; skipping (notify.sh will fall back)"
  exit 0
fi

mkdir -p "$AUTODREAM_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

PL="$DEST/Contents/Info.plist"
$PB -c "Set :CFBundleName cc-autodream" "$PL"
$PB -c "Set :CFBundleIdentifier com.samuelreed.cc-autodream" "$PL"
$PB -c "Add :CFBundleDisplayName string cc-autodream" "$PL" 2>/dev/null \
  || $PB -c "Set :CFBundleDisplayName cc-autodream" "$PL"

codesign --force --deep -s - "$DEST" >/dev/null 2>&1 || true
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "make-notifier.sh: built $DEST (notifications will show as cc-autodream)"
echo "make-notifier.sh: enable it once under System Settings > Notifications > cc-autodream (style: Alerts)"
