# runsh: an empty L2 argv is replaced with `false`, never run

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_ARGV=(false)`)

## Context
An empty argv would run a bare `env`, which prints the environment into the report capture.

## Decision
When no L2 command could be built, `run.sh` logs a WARNING and sets `L2_ARGV=(false)`, so every attempt fails visibly and nothing is captured.

## Consequences
Do not "simplify" by dropping the placeholder: the pipeline is `env <envs> /bin/sh -c '... exec "$@"' <pidfile> <argv>`, and with no argv the environment lands in the dream file.
