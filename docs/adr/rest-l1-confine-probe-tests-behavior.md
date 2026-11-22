# rest: the sandbox probe runs a real confined shell and checks both sides of the boundary

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`cmd_probe`)

## Context

A sandbox tool can accept a profile and confine nothing, or start and refuse everything. Trusting its exit code or its acceptance of the profile reports "confined" for a host where workers can still write anywhere (#169), or reports "not confined" for a host that is fine.

## Decision

`l1-confine.sh probe` prints one line, `yes<TAB><tool>` or `no<TAB><reason>`, and always exits 0. It makes a temp directory with a `stage` and an `outside` directory, builds a prefix with no protected paths and no stage root, and runs a confined `/bin/sh` that writes a file inside the stage and then tries to write one in `outside`. The answer is `yes` only when the stage write landed and the outside write did not. Distinct `no` reasons: no tool on PATH, no probe directory, the tool could not build a profile, the tool rejected the profile or could not start (with its exit code and the first 200 characters of stderr), the stage was not writable, the outside write was not refused. The script that tries the outside write is written to exit 0 even when that write is refused, so a nonzero exit means the tool failed, not the write.

## Consequences

`run.sh` runs the probe once per run and reports `l1_confined` from it (`runsh-l1-confiner-missing-runs-unconfined`). The probe builds a prefix with no paths, so the real per-engine prefix is built separately at setup. The suite skips the real-sandbox cases where `sandbox-exec` cannot start (it cannot inside another sandbox).
