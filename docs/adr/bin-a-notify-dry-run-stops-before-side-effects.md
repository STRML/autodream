# bin-a: `AUTODREAM_NOTIFY_DRYRUN=1` stops before any banner, inbox file or opener, in every form of notify.sh

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (the two `AUTODREAM_NOTIFY_DRYRUN` checks)

## Context

Counting the questions of a report is pure computation, and people legitimately want to replay the counter over a pile of old reports. That is how the marker logic was validated. Doing it with the real script posts a real banner per report. On 2026-07-28 a verification sweep fired banners for reports up to eleven days old, and because the sweep had pointed the open command at a stub, clicking them did nothing.

Pointing `AUTODREAM_DIR` at a temp dir is not enough to make a sweep safe. The branded bundle is absent there, so the notifier resolution falls through to a system `terminal-notifier` and posts for real.

The failure and warning branch used to return before reaching the dry-run check. Its documented promise is that nothing is written, posted or opened, and anyone exercising that branch with the variable set got a live banner and a stray inbox file.

## Decision

`AUTODREAM_NOTIFY_DRYRUN=1` reports the question count (or the banner it would post) and exits 0. It writes no inbox file, posts no banner and opens nothing. The check sits after the count in the report form and before the notifier in the failure and warning form. The inbox directory is still created, and the branded notifier bundle may still be built, because both run above either check.

## Consequences

Anything that posts, opens or writes an inbox file belongs below the dry-run check in both forms. The inbox directory and the notifier bundle are the two things created above it. `tests/run-all.sh` exercises the dry-run output.
