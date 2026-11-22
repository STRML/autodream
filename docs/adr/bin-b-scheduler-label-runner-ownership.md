# bin-b: a launchd plist is ours only when its ProgramArguments invoke this install's run.sh

Status: accepted · Date: 2026-11-21 · Code: `bin/scheduler-label.sh` (`runner_dir_of`, `norm_dir`, the plist scan loop)

## Context

`install.sh` and `bin/autodream-now.sh` each derived "which label is ours", and both got it wrong the same way: any plist whose body mentioned `run.sh` counted as ours. Installing a second autodream on a host that already ran one adopted the first one's label and rewrote that job in place. Nothing failed loudly. The overwritten job's triage sat dead for 18 days (omp-autodream#14, the cause of https://github.com/STRML/cc-autodream/issues/60).

CLAUDE.md, "The label is owned by a runner, not by a name", records the same decision.

## Decision

- The runner decides ownership. `runner_dir_of` reads `ProgramArguments:0..5` (the array is short: bash, the script, at most a `-c` form) and returns the directory of the first `*/run.sh`. The plist is ours when that equals the install dir. The label it carries and `AUTODREAM_DIR` do not count, because a hand-written plist may have no environment block but always names its program.
- `norm_dir` compares `pwd -P` of both sides, with a trailing slash stripped. A mismatch there is invisible: it yields a fresh label on every re-install instead of an error.
- The scan reads every plist in the LaunchAgents dir and goes by its `Label`, never by filename. launchd keys a job by Label. A foreign job holding the default label in `backup.plist` is still the job `install.sh` would boot out, and our own job renamed to a file without "autodream" in its name must still be found.
- A plist whose Label ends in `.ondemand` is skipped, by Label. `autodream-now` writes that sibling into `$AUTODREAM_DIR`, so the glob normally never sees one. The skip covers a hand-dropped copy, where adopting it would nest a second `.ondemand` suffix. A foreign job holding the default label in `backup.ondemand.plist` is still a conflict (Codex review of 0129fc0).
- Our own prior plist wins over any conflict, even when its label is not the default, so a re-install is idempotent.
- The default label held by anything that is not our runner, including a job with no `run.sh` at all, is a conflict.

## Consequences

A runner invoked as something other than a path ending in `/run.sh` is not recognised. `tests/scheduler-label.sh` pins each rule above, so change one only together with its test. The exit-status contract callers rely on is in `bin-b-scheduler-label-exit-contract.md`.
