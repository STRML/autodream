# runsh: The L1 engine is resolved before its model, and an engine that fails its login check is removed before any transcript is sent

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the per-source engine/model loop and the `engine_login_ok` loop)

## Context
A source's engine choice that names no accepted adapter must not fall through to some other engine. Every L1 engine must meet `AUTODREAM_REQUIRE_LOGIN` before a transcript goes to it. See CLAUDE.md, 'Who starts the L1 worker' ("The engine, then the model", "No engine is an error for this run's config, not forever").

## Decision
- For each source, `adapter_l1_engine` is resolved first. A choice that names no accepted adapter leaves that source with no model (and a WARNING), so its sessions get error records instead of a call on some other engine.
- `AUTODREAM_L1_MODELS`, `AUTODREAM_L1_ENGINES` and `AUTODREAM_L1_PROBE_URLS` are built from that resolution.
- Each engine in use is checked with `engine_login_ok`. One that fails has its column blanked in `AUTODREAM_L1_ENGINES`, so its sessions take the same path as a choice naming no accepted adapter (error records, no model call).

## Consequences
- Do not resolve the model first or default a missing engine to the reviewer: that sent omp sessions to the claude CLI with a model id from another engine once (PR #165 review, per CLAUDE.md).
- The login failure is a config problem for this run, so those records are dropped and retried on a later run that resolves an engine.
