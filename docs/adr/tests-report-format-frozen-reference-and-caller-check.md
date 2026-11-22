# tests-report-format: the old inline code is kept verbatim as the oracle, and callers are checked by call, not by mention

Status: accepted · Date: 2026-11-22 · Code: `tests/report-format.sh` (`old_marker`, `old_has_marker`, `old_has_sentinel`, `old_body`, `old_after`, `old_pins`, `uses`)

## Context

`bin/report-format.sh` replaced inline marker and sentinel reads that lived in `run.sh`, `notify.sh`, `question-streaks.sh` and `triage-dream.sh`. The refactor is only safe if the helper and the code it replaced agree on stdout and on exit status for every fixture, the awkward ones included (CRLF, no trailing newline, a quoted sentinel, an unclosed pin block).

A check that a script "uses the lib" is easy to satisfy by accident. A script that only names `report-format.sh` in an error message, or in a comment, would pass a grep for the file name while still reading the report with its own awk.

## Decision

- The `old_*` functions are the previous implementations, copied verbatim. They are the oracle: `same` runs helper and reference over the whole fixture matrix and compares output and status.
- `uses <script> <helper>` greps for the helper's name on a line that is not a comment (`^[^#]*\bhelper\b`). Each caller must call the helper it replaced. A mention of the lib's file name proves nothing.
- The lib must also be sourced on a line of its own, and no other `bin/*.sh` may read the marker or the sentinel with its own grep, sed or awk (comment lines are skipped).

## Consequences

Do not "improve" an `old_*` function: once it changes, the test compares the helper with a reference nobody ever ran, and a behaviour change in the helper passes. A new fixture goes into `FIXTURES`, and a new caller gets a `uses` line.
