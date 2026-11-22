# bin-b: the banner runs osascript with fd 9 closed and escapes the message for AppleScript

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`show_notification`, `post_banner`)

## Context

The banner is the one surface that looks different from last night's, so it is best-effort and never fatal, the same posture as `notify.sh`.

## Decision

- `osascript` runs with fd 9 closed. A child that outlives this script would otherwise keep the flock alive after the script is killed.
- Backslashes and double quotes in the message are escaped. Otherwise a quote in a question title ends the AppleScript string and the whole `-e` becomes a syntax error, which `osascript` reports on a stderr this drops, so the banner would vanish for exactly the questions with punctuation in them.
- `AUTODREAM_NOTIFY_DRYRUN=1` prints "dry run, no banner" before anything else, including the `osascript` lookup.

## Consequences

Any new child process started while the lock is held needs `9>&-` too.
