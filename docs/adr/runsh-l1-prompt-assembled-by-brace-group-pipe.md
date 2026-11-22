# runsh: the L1 prompt is assembled by a brace group piped to the engine, with paths passed as literal data

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`)

## Context
Passing the paths as `KEY=value` made a worker try to `$`-expand them in a shell; there is no such variable, so they expanded to nothing and the call failed (the failure mode that broke earlier runs). A `prompt=$(...)` capture strips trailing newlines, which would glue the SESSION_TRIAGE.md body onto the end of the output-path line and corrupt it.

## Decision
`l1_attempt` prints the transcript path and the output path as literal text lines, then `cat`s SESSION_TRIAGE.md (plus the adapter addendum, day note, chunk note and stats block) from one `{ ...; } | engine` brace group, so the blank-line separator printed by `printf` survives.

## Consequences
Any state the engine side of the pipe needs must be set outside the brace group (see the timeout wrapper ADR). Do not move the assembly into a `$(...)`.
