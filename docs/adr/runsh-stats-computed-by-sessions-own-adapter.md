# runsh: A session's stats are computed by its own adapter, over the live linearized conversation

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_session_stats`)

## Context
omp records are not claude records. Stats describe the live conversation the worker will read, not the append-only tree it came from: abandoned branches would otherwise add user turns and stretch the duration, and the noise gate reads these numbers.

## Decision
For a source other than claude whose adapter script exists, the session's own adapter computes the stats (`adapter_run "$src" stats`). `AUTODREAM_STATS_BIN` still wins, and a session with no recorded source keeps the claude script (`$STATS`), so an install that predates the source sidecar degrades instead of failing. An adapter whose manifest has `normalize: true` is linearized first, into `<hash>.statsin.jsonl`, and the stats read that copy (falling back to the raw file if normalize fails). The result is then cut to the report day before the stats run, and a cut that errors logs a WARNING that the stats cover the whole transcript. A stats run that fails or writes a non-object removes the sidecar and logs `stats failed ... continuing without precomputed stats`.

See CLAUDE.md, "Several harnesses in one run".

## Consequences
The order with the day cut is in `day-slice-normalize-before-cut`. The temp copies (`.statsin.jsonl`, `.statsday.jsonl`) are removed after each session.
