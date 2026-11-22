# bin-a: the failure banner escapes the reason before putting it in an AppleScript string

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (`osa_reason`)

## Context

A failure reason that contains a `"` made `osascript` fail with a syntax error. Several reasons do contain one, since they quote paths and adapter lists. The failure branch drops `osascript`'s stderr, so the one surface a dead run has failed silently on exactly those runs.

## Decision

The reason is passed through `sed 's/\\/\\\\/g; s/"/\\"/g'` (backslashes first, then quotes) before it is interpolated into the `display notification` string literal.

## Consequences

Any new text interpolated into that string needs the same escape, because the stderr is discarded and a bad string shows up only as a missing banner. The `terminal-notifier` path takes the message as an argument and needs no escape.
