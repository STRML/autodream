# runsh: the L2 prompt is a brace group with literal paths, run in a subshell

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the L2 call: the `{ printf ...; cat PROMPT.md; } | env ...` pipeline in a `( cd "$WORK_DIR" ... )` subshell)

## Context
Same literal-path framing and brace-group assembly as the L1 worker (the worker writes `Session transcript to analyze (literal absolute path)` and similar): the paths stay literal data the aggregator reads with Glob/Read, and the blank-line separator before PROMPT.md is preserved instead of letting a `prompt=$(...)` capture strip it and glue the doc onto the report-path line.

## Decision
A subshell scopes the cwd change (isolating the AI-title stub into `$WORK_BUCKET`, same as L1) to this call; `$?` after the subshell is the pipeline's exit, which is the engine's (the original comment said claude's; the engine is whichever adapter L2 runs on). The brace group writes three literal-path lines (findings directory, `dropped-threads.md`, report destination), a blank line, then `PROMPT.md`. See CLAUDE.md, "The AI-title stub vector".

## Consequences
Do not capture the prompt with `$(...)`. The "Findings directory to aggregate (literal absolute path)" line is also one of `prune-self-sessions.sh`'s markers for recognizing autodream's own sessions.
