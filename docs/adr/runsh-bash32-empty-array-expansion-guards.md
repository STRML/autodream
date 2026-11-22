# runsh: every expansion of a possibly-empty array is guarded for bash 3.2 under `set -u`

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`${L2_ARGV[@]+"${L2_ARGV[@]}"}`, `${L2_ENVS[@]+...}`)

## Context
`run.sh` runs under `/bin/bash`, which is 3.2 on macOS and what launchd uses. Under bash 3.2 with `set -u`, `"${a[@]}"` on an EMPTY array is an unbound-variable error, where bash 5 expands to nothing. A warmup that aborted for exactly that reason passed the whole suite until the suite ran the shipped interpreter (see CLAUDE.md, "Tests").

## Decision
Every expansion of the L2 argv and env arrays uses the `${a[@]+"${a[@]}"}` form.

## Consequences
Run the suite under `/bin/bash`, not whatever `bash` is first on PATH. A new array expansion here needs the same guard.
