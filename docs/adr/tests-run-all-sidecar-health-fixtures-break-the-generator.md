# tests-run-all: the sidecar-health tests break the stats generator, because the runner regenerates every sidecar

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_stats_sidecar_missing_counted`, `test_stats_sidecar_malformed_counted`)

## Context

`compute_session_stats` in `bin/run.sh` deletes and regenerates every sidecar on each run. A sidecar is kept only if the generator exits 0, writes a non-empty file, and the file is a JSON object (`jq -e 'type == "object"'`). A hand-edited sidecar is overwritten before anything reads it.

## Decision

- To get a missing sidecar, the test sets `AUTODREAM_STATS_BIN` to a path that does not exist.
- To get a sidecar that is read but unusable, the test points `AUTODREAM_STATS_BIN` at a stub that writes a valid object with no `transcript_bytes`. It passes the object check, survives generation, and fails at read time. This is the quieter of the two failure paths.

## Consequences

Seeding a bad file in the findings dir tests nothing, since the run replaces it. Writing the stub as a non-object makes the generator step drop it and reaches the other path instead. `stats_sidecars_unparseable` counts both, and the `oversized_total` fallback to the transcript's own size covers both.
