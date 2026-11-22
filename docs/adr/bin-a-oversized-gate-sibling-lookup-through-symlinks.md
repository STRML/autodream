# bin-a: a linked script finds its sibling helpers by following its own symlink, because `install.sh` links each script on its own

Status: accepted · Date: 2026-11-21 · Code: `bin/oversized-gate.sh` (library and classifier lookup), `bin/pending-triage.sh` (`_lib`)

## Context

`install.sh` symlinks each script into `~/.claude/autodream` individually. Merging a branch swaps the script those links point at at once, while a new library link does not exist until `install.sh` is re-run. `cd -P` resolves a symlinked directory but not a symlinked file, so `$HERE` is the install dir every time, and the script stopped working entirely during that window. For `oversized-gate.sh` that was the one tool whose purpose is recomputing the #12 gate from artifacts after a runner problem. An install made before `failure-class.sh` existed linked the script but not the classifier (Codex review of b19ec84).

## Decision

- `oversized-gate.sh` looks for `lib-project.sh` beside itself, then in the directory its symlink chain ends in (up to 8 hops, relative link targets resolved against the link's directory). It exits 2 if neither has it.
- It looks for `failure-class.sh` in three places in order: its own directory, the real directory behind its symlink, then `AUTODREAM_DIR`. It exits 1 if none has it. `run.sh` uses the same walk.
- `pending-triage.sh` does the same for `portable.sh`, `lib-install-dir.sh` and `report-format.sh` through `_lib`: its own directory first, then the directory of what `readlink` returns.

## Consequences

CLAUDE.md, "A failed worker leaves its evidence", states the classifier rule for `run.sh` and `oversized-gate.sh`. A new helper that these scripts source must be found the same way, or an update of the checkout breaks the nightly until the next `install.sh`.
