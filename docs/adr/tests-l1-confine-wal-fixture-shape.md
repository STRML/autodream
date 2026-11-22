# tests-l1-confine: the omp `l1-stage-env` fixture is a live WAL database with a log-only row

Status: accepted · Date: 2026-11-22 · Code: `tests/l1-confine.sh` (the `omp l1-stage-env` cases)

## Context

`adapters/omp/adapter.sh l1-stage-env` seeds each confined omp worker with a copy of `agent.db` that leaves the OAuth credential rows out (`CLAUDE.md`, "A host with no working sandbox says so"). A running omp keeps `agent.db` open in WAL mode, so a plain file copy of the main file misses whatever is committed only to the log and can capture a torn state.

## Decision

The fixture builds `agent.db` the way a live omp holds it: `journal_mode=WAL`, `wal_autocheckpoint=0`, an API-key row and an OAuth row, then one more committed row (`deepseek`) that exists only in the log. A python process keeps that connection open for the whole verb. The assertion lists the providers in the copy and expects `neuralwatt,deepseek`, so only a SQLite backup-API snapshot passes; a file copy returns `neuralwatt` alone.

## Consequences

Simplifying the fixture to a closed, checkpointed database makes the assertion pass for a plain `cp` and removes the guard. Keep the holder process alive until the verb returns. The OAuth assertions pair with it: the worker copy holds zero OAuth rows and the real database still holds one.
