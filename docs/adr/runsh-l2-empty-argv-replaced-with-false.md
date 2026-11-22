# runsh: an empty L2 argv is replaced with `false`, never run

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_ARGV=(false)`)

## Context
The original comment says an empty argv would run a bare `env`, which prints the environment into the report capture. That described the older `env <envs> <argv>` form. Through today's wrapper, `env <envs> /bin/sh -c '... exec "$@"' <pidfile>` with no argv runs `exec` with no command, which does nothing and exits 0, so the attempt would capture nothing and look like a clean exit instead of failing (checked by running the wrapper with no argv).

## Decision
When no L2 command could be built, `run.sh` logs a WARNING and sets `L2_ARGV=(false)`, so every attempt fails visibly and nothing is captured.

## Consequences
Do not "simplify" by dropping the placeholder: the pipeline is `env <envs> /bin/sh -c '... exec "$@"' <pidfile> <argv>`, and with no argv the attempt exits 0 with an empty capture, not the visible failure `false` gives.
