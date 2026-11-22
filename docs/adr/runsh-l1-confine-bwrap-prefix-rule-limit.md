# runsh: with bwrap a trailing-star write rule covers only files that exist at launch, and run-stats says so

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_stat_lines`)

## Context
`bwrap` binds existing paths. A prefix rule (a trailing `*` in `AUTODREAM_L1_WRITES_EXTRA` or an adapter write list) therefore covers the files that exist when the sandbox starts and not one created later. `sandbox-exec` has no such limit.

## Decision
When `L1_CONFINE_USING` is `bwrap`, `l1_confine_stat_lines` adds `l1_confine_note: bwrap prefix rules bind existing files only` to every run-stats block that reports L1 stats.

## Consequences
A write that works under `sandbox-exec` on macOS can be refused on Linux for a file that did not exist at launch. Read the note before debugging a confined worker on Linux. Removing the line hides a real platform difference from the artifact.
