# bin-a: notifications are branded by cloning, renaming and re-signing a copy of terminal-notifier.app

Status: accepted · Date: 2026-11-21 · Code: `bin/make-notifier.sh`, `bin/notify.sh` (`BRANDED`, `NOTIFIER`)

## Context

`terminal-notifier` attributes each notification to its own app bundle: the sender name and icon come from the bundle's `Info.plist`. There is no flag that sets an arbitrary sender name. `-sender` only borrows another existing app's identity.

## Decision

- `make-notifier.sh` copies `terminal-notifier.app` into `$AUTODREAM_DIR/cc-autodream.app`, renames it in the plist (`CFBundleName`, `CFBundleIdentifier`, `CFBundleDisplayName`), ad-hoc re-signs it (editing the plist invalidates the inherited signature, and macOS will not run the bundle without one) and registers it with LaunchServices so it appears under its own name.
- It is idempotent (a no-op when the bundle exists, `--force` rebuilds) and degrades gracefully: without `terminal-notifier` there is nothing to copy, so it prints a note and exits 0.
- `notify.sh` resolves the notifier in this order: the branded bundle's binary, bootstrapped once through `make-notifier.sh` when it is missing and `terminal-notifier` is installed; then plain `terminal-notifier`; then an `osascript` banner, which is not clickable. It looks for `make-notifier.sh` next to itself (the repo and the `~/.claude/autodream` symlink both work), then in the install dir.

## Consequences

The branded bundle is a new sender to macOS, with notifications off by default until the user enables it once under System Settings > Notifications > cc-autodream (style: Alerts). See `bin-a-notify-banner-fires-both-senders.md` for what happened the first time.
