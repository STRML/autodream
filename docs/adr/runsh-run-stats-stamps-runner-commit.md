# runsh: run-stats stamps the commit of the code that produced it (`runner_commit`, `runner_dirty`)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the full-run `run-stats.txt` block; also the zero-session block)

## Context
Issue #29. `install.sh` symlinks `~/.claude/autodream/*.sh` straight at the repo working tree, so the nightly executes whatever is checked out at 03:15: a tree sitting behind origin runs old code even though the fix is merged. That cost real data twice: the 2026-07-24 `overlap-stats.sh` dangle, and a tree stuck on a local commit from 2026-07-20 to 2026-07-24 that wrote four nights of `run-stats.txt` with no `oversized_*`/`gated`/`overlap_*` keys at all. Absent keys are a terrible signal: they read as "this stat did not apply" rather than "this runner predates the stat", and telling those apart took a reflog dig both times. See CLAUDE.md, 'Which code actually ran (`runner_commit`)'.

## Decision
`runner_commit` and `runner_dirty` are the first keys of every `run-stats.txt` (`$RUNNER_COMMIT`, `$RUNNER_DIRTY`), so the runner's age is legible from the artifact itself. A `run-stats.txt` that is missing keys means an old runner, not a stat that did not apply.

## Consequences
- Keep both keys on every path that writes run-stats (full run, zero-session stub, fatal exit).
