# tests-run-all: notify tests stub the branded notifier before any call that can post, and record argv one per line

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_notify_count`, `test_notify_open_command`, `test_notify_dryrun`)

## Context

`bin/notify.sh` resolves the branded notifier bundle first. With none present, resolution falls through to a system `terminal-notifier` and posts for real. Pointing `AUTODREAM_DIR` at a temp dir is not enough to avoid that. While `test_notify_dryrun` was being written without the stub, the suite posted a live notification for a fixture dated 2020-04-01.

## Decision

- Every call that can reach the posting code runs with an executable stub at `$root/cc-autodream.app/Contents/MacOS/terminal-notifier`. `AUTODREAM_NOTIFY_OSA_BACKUP=0` turns off the osascript fallback, and `SUBL=/usr/bin/true` stops an editor from opening.
- The dry-run assertions run with no stub on purpose. A dry run has to be safe without any stubbing. The stub is added only before the follow-up call without the flag, which proves the guard is not just off.
- The fake editor logs each argument on its own line, so the test can count arguments and prove word-splitting and quoting. Exit status alone would not show a path with a space being split.

## Consequences

Seeding the stub before the dry-run calls hides a dry run that posts. Removing it before the wet call posts a real banner. Logging with `echo "$@"` merges arguments and makes the "exactly two arguments" and "single argument" assertions meaningless.
