# runsh: the question-streak update runs first after a complete report, ahead of pins and notify

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: the `question-streaks.sh update` call)

## Context
It only reads the report and writes one local file, while the steps after it call out (`notify.sh` runs the user's `AUTODREAM_OPEN` synchronously, `apply-pins.sh` calls the Mnemopi store). If either hangs, a kill there leaves a report on disk that the next trigger skips, and a streak update placed after them would never run for it, so a stale question would miss its escalation (https://github.com/STRML/autodream/issues/77). The failure it answers is not a missing signal but an unchanging one: the X bookmarks question was asked six times across ten failing nights, each night's banner identical to the last, and nothing moved until the user noticed by accident.

## Decision
The update runs before the pins and `notify.sh`; a non-zero exit logs and the run continues (never fatal; it is bookkeeping). See CLAUDE.md, "Open questions that never get answered".

## Consequences
Do not move it below `notify.sh` or `apply-pins.sh`.
