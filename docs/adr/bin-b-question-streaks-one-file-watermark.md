# bin-b: the streak board and its watermark are one file written by one rename, and reruns hold counts

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`write_state`, `newest_of`, `cmd_update`)

## Context

The newest counted report date used to live in a second file. Three review rounds in a row (Codex on 232c94c, 4eea84d and 600e6dd) each found a write order, or a failure between the two files, that let an older rebuild recreate a streak.

`AUTODREAM_FORCE=1 run.sh <today>` rebuilds a report already counted, and rebuilding an older date would rewrite live state with history.

## Decision

- The watermark is the first line of the state file, `#last<TAB>YYYY-MM-DD`, above the rows. A question-free report leaves only that line.
- Every write is a temp file in the state directory and one rename, so a failed temp creation, a full disk, a failed rename or a kill between write and rename leaves the old file whole (a kill can strand a `STATE.XXXXXX` temp).
- A date older than the watermark is refused. The same date holds each existing count and refreshes membership, and a question new on that rebuild starts at 1. A rebuild re-posts no banner but still writes `question-escalations.txt`.
- A state file that exists but cannot be read is not an empty board: reading it as empty would drop the watermark and restart every streak, so `update` refuses.

## Consequences

State that must change together goes in one file. When a fix starts choosing which of two files to write first, merge them (CLAUDE.md, "Bash traps this feature hit"). `clear` keeps the watermark, so an older rebuild after a clear is still history.
