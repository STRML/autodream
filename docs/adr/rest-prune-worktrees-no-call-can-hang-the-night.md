# rest: no call the pruner makes can hang the nightly run

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (`on_term`, the watchdog subshell, `tmo` from `bin/portable.sh`)

## Context

The pruner makes network calls (`gh`, `git fetch`, `git push`) and runs `trash` inside the nightly run. One call that waits for a password, a dead host, or a stuck filesystem would stall the whole run and the night's report. Commit `1075a87` (2026-10-13) bounded every call. CLAUDE.md, under "A watchdog takes its own `sleep` with it", records the later fix to the watchdog subshell here and in two sibling scripts.

## Decision

- **Prompts are off.** `GIT_TERMINAL_PROMPT=0` and `GH_PROMPT_DISABLED=1` are exported. Without a tty (launchd) ssh and git cannot prompt either. `GIT_HTTP_LOW_SPEED_LIMIT=1000` and `GIT_HTTP_LOW_SPEED_TIME=$CALL_SEC` make a slow transfer abort on its own.
- **Every network call and `trash` runs under `tmo "$CALL_SEC"`** (`AUTODREAM_PRUNE_CALL_SEC`, default 60). `tmo` uses `timeout`, `gtimeout`, or a built-in watchdog when neither exists. The remote delete and the fetch get twice that.
- **A hard cap covers everything else.** A watchdog subshell sleeps `AUTODREAM_PRUNE_BUDGET_SEC` plus `AUTODREAM_PRUNE_KILL_SLACK` (defaults 1200 and 120 seconds) from the start, then sends TERM to the script. `on_term` kills the children (`pkill -P`), writes an `interrupted` ledger line if a removal was in flight, adds a `skipped` row (`watchdog: the run outlasted its time cap`), writes the report, and exits 0.
- **The watchdog kills the children right after the TERM.** Bash runs a trap only after its foreground child exits, so a script blocked in a hung child would never reach `on_term` on its own.
- **The watchdog subshell traps TERM and kills its own `sleep`**, so ending the watchdog ends the sleep (otherwise the sleep lingers until its timeout, and a watchdog woken late could signal a recycled pid).
- **The budget is also checked between steps** (`budget_ok`), which turns an overrun into `time-budget` rows before the hard cap is needed.
- **A bad number in any `AUTODREAM_PRUNE_*` knob exits 0** with a message, never a non-zero status.

## Consequences

The script exits 0 on every path once it has an out-dir, because a pruning problem must not cost the night's report; `run.sh` relies on that. A new external call must go through `tmo`. A new loop must check `budget_ok`. If `tmo` or the watchdog changes, run `tests/prune-worktrees.sh` and `tests/portable.sh`, since the TERM path is the only thing standing between a hung host and a missing report.
