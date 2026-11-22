# runsh: numeric env knobs are refused or normalised at startup, never discovered at 03:15

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `case ... in ''|*[!0-9]*` blocks after `FANOUT`: `AUTODREAM_L1_TIMEOUT`, `AUTODREAM_L1_WARMUP_TIMEOUT`, `AUTODREAM_L1_CHUNK_BYTES`, `AUTODREAM_L1_MAX_CHUNKS`, `AUTODREAM_SANDBOX_SHAPE_MIN`, the noise-gate loop)

## Context
Each knob has its own way of failing silently if it is unvalidated:
- `AUTODREAM_L1_TIMEOUT` / `AUTODREAM_L1_WARMUP_TIMEOUT`: GNU timeout treats a duration of 0 as "no timeout", so an unvalidated 0 restores the exact hang the timeout bounds while the startup log still reports a timeout is set; a non-numeric value is worse (timeout rejects it and every worker fails). The warmup runs before every recovery path, so an unbounded warmup wedges the run.
- Chunk knobs: 0 is a real value for `AUTODREAM_L1_CHUNK_BYTES` (chunking off), so only a non-number is refused there; `AUTODREAM_L1_MAX_CHUNKS` below 1 would mean no chunk is ever read. Bash arithmetic reads `08` as an invalid octal number.
- `AUTODREAM_SANDBOX_SHAPE_MIN`: 0 would list every session, so the floor is 1. L2 cannot read the environment, so `write_rollup` hands it the value through run-stats (`sandbox_shape_denies_min`).
- `AUTODREAM_MIN_USER_TURNS` / `AUTODREAM_MIN_MINUTES` reach jq through `--argjson` with stderr discarded: a non-number makes jq fail, the noise gate comes back empty, and every session goes to a model call with no message.

## Decision
Each knob is checked with a digits-only `case` and, where 0 or less is wrong, a `-gt 0` / `-ge 1` test; the script exits 1 with a `FATAL:` line on stderr (the run log does not exist yet). Knobs that are used in arithmetic are rewritten with `$((10#$X))` so a leading zero is decimal whatever the user wrote. See CLAUDE.md, "Reading a long session: chunked triage" for the chunk gate.

## Consequences
A new numeric knob needs the same treatment, with the reason its zero or non-number is dangerous. Do not relax the timeout zero check: it re-creates the 2026-08 hang.
