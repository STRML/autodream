# rest: a report command is bounded by one built-in watchdog, never timeout(1), with a per-file size limit and a settled process tree

Status: accepted · Date: 2026-11-22 · Code: `bin/report-scripts.sh` (`run_bounded`, `tree_pids`, `settle_tree`, the numeric knobs, the `collect` timeout branch); CLAUDE.md "Report scripts"

## Context

A report command must not be able to hold or fill the nightly run, and the processes it started must not outlive it. Three observations shaped the code:

- `timeout(1)` reports the command's own exit status when the command traps TERM and exits 0, and leaves a TERM-ignoring child of an exited wrapper running. Neither can be told apart from a normal run, so there is no `timeout(1)` path (macOS ships none anyway).
- A watchdog written as `( sleep N; kill ... ) &` leaves its `sleep` running after the command finished in time. Killing only the subshell did not end the sleep.
- macOS does not enforce `ulimit -f` on `>>` appends.

## Decision

- **One path, `run_bounded`.** It starts the command, then a watchdog subshell that sleeps `AUTODREAM_REPORT_TIMEOUT` (default 60). At the timeout the watchdog records the process tree (`tree_pids`, via `pgrep -P`) in a flag file the caller owns, sends TERM to it, waits `AUTODREAM_REPORT_KILL_GRACE` (default 5) seconds and sends KILL. The watchdog traps TERM and kills its own sleep, so a command that finishes in time leaves nothing behind and a watchdog woken at that moment cannot signal a recycled pid.
- **The flag file is the evidence.** It is empty unless the timeout fired. A row is `timeout` exactly when it is non-empty, whatever the exit status was: a command that traps TERM and exits 0 is still one that ran past its limit. The exit status and the clock are never used to infer it.
- **The tree is settled after the command is gone.** A TERM-ignoring child the command started is no longer reachable through the command's process tree, so `settle_tree` walks the recorded list. It gives survivors what is left of the grace period, then sends KILL.
- **Output is limited per file.** `ulimit -f` caps every file the command writes, stdout and stderr included, at four times `AUTODREAM_REPORT_MAX_BYTES` (default 100000). A command that never stops printing dies on SIGXFSZ (exit 153, reported as an output-limit failure rather than a bare `exited 153`) long before the disk is full. The report body is cut at the cap itself. The limit is per file and macOS does not enforce it on appends, so what a script appends to its own files is bounded by the timeout alone.
- **The knobs are read with `10#`.** A value with a leading zero (`08`) is a number here, not a bad octal that aborts the collector. A non-numeric or zero value falls back to the default.

## Consequences

`pgrep` cannot read the process table inside the Claude Code sandbox, so the child-kill assertions in `tests/report-scripts.sh` skip there (3 skips on 2026-11-22) and run in CI. The same watchdog shape lives in `tmo` in `bin/portable.sh`, `run_bounded` in `x-bookmarks.sh` and the hard-cap watchdog in `bin/prune-worktrees.sh`. A fix to one is a fix to the class, so grep the others before changing it.
