# bin-a: L1 resolves the engine first and keys the model by the engine, not by the session's source

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`adapter_l1_engine`, `adapter_l1_model`, `adapter_l2_model`)

## Context

Which harness holds a transcript and which engine reads it are separate choices: the run has one reviewer, the engine that writes the summary, unless the host picks another. A model id belongs to one engine: `neuralwatt/glm-5.3-flash` means nothing to claude. A source-keyed pin sent omp sessions to the claude CLI with an omp model id (see CLAUDE.md, "Who starts the L1 worker").

## Decision

`adapter_l1_engine <source> <reviewer>` resolves, first match wins:

1. `AUTODREAM_L1_ENGINE_<NAME>`: that source only (name upper-cased, dashes to underscores).
2. `AUTODREAM_L1_ENGINE`: every source.
3. The run's reviewer, the L2 engine (`AUTODREAM_L2_ENGINE`, else the first enabled adapter), passed by the runner.
4. The source itself, only when no reviewer is passed.

Only the model call moves. The source's own adapter still enumerates, normalizes, describes and adds its triage notes. A choice that names no accepted adapter resolves nothing (exit 1), so the caller leaves those sessions untriaged instead of falling back to some other engine.

`adapter_l1_model` resolves the engine first, then, keyed by the engine and never by the source:

1. `AUTODREAM_L1_MODEL_<ENGINE>`: that engine only, whichever source's sessions it reads, like `AUTODREAM_L2_MODEL_<NAME>`.
2. `AUTODREAM_L1_MODEL`: every engine, an override for hosts with one engine.
3. The manifest's `l1_model`: that engine's default.

With the reviewer on claude, `AUTODREAM_L1_MODEL_OMP` therefore does not reach omp sessions, and an omp model id never reaches the claude CLI.

`adapter_l2_model` resolves `AUTODREAM_L2_MODEL_<NAME>`, `AUTODREAM_L2_MODEL`, then the manifest's `l2_model`. The manifest's `l2_model` may be absent, which for claude means "let the CLI pick", so the function exits 1 with no output and the caller passes no model at all.

## Consequences

A host can pin one engine without touching another. Do not key the L1 model by source. CLAUDE.md, "Who starts the L1 worker" and "Which engine runs L2", state the same rules from the runner's side.
