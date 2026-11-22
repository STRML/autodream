# runsh: helpers and libraries are found through `find_lib` (script dir, then the runner's real bin dir), not SCRIPT_DIR alone

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`SCRIPT_DIR`, `RUNNER_SRC`, `RUNNER_BIN_DIR`, `find_lib`, the `. report-format.sh` / `err-cause.sh` sources, `APPLY_PINS`, `FAILURE_CLASS`, `portable.sh` lookup)

## Context
`install.sh` symlinks each script into `~/.claude/autodream` individually, so a merge swaps the run.sh those links point at instantly, while newer helpers (`lib-project.sh`, `adapters.sh`, `preflight.sh`, `adapters/`, `apply-pins.sh`, `failure-class.sh`, ...) stay missing from the install dir until `install.sh` is re-run. Sourcing only from SCRIPT_DIR then skips them in silence and the run dies later on `session_hash: command not found`, with no report and nothing saying why.

## Decision
- The symlink walk (`RUNNER_SRC`) resolves this script to its real location, so the repo's own `bin/` is the fallback. The installed dir comes first, because that is the layout the nightly is supposed to have and the one whose files are meant to win. `find_lib <basename>` prints the first readable copy, or nothing.
- `portable.sh` is looked up the same way (own dir, then the readlink target's dir) because installed copies are symlinks and a merge updates them before install.sh links a new helper.
- Libraries whose absence would corrupt the run are NOT optional: `report-format.sh` and `err-cause.sh` stop the run with a `FATAL` before any work, because an unfound lib would turn every read of a report into "command not found" after L1 had already been paid for.
- `apply-pins.sh` and `session-window.sh` use `find_lib` for the same reason; `failure-class.sh` is looked up in SCRIPT_DIR, the runner's repo dir, then AUTODREAM_DIR, after the runner walk, because an install made before it existed has a link for every other script but not this one and updating the checkout must not break that install's nightly (Codex review of omp-autodream b19ec84). The directory the run.sh link points at always has it.

## Consequences
A new helper must be resolved with `find_lib` (or the failure-class pattern) and must have a decided missing-helper behaviour: fatal for a library, degrade-and-say-so for an optional feature. See CLAUDE.md, "Which code actually ran" and the install notes.
