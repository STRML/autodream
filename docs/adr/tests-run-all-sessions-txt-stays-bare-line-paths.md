# tests-run-all: sessions.txt stays a list of bare, line-delimited paths, and the tests guard that

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_newline_path_is_rejected_not_split`, `test_artifact_hash_contract_is_unchanged`, `test_source_sidecar_is_written`, `test_preflight_stops_a_run_missing_a_dependency`, `test_unusual_session_paths_are_triaged_or_refused`)

## Context

Four consumers derive an artifact key, or a filesystem path, from a whole line of `sessions.txt`: the hash assignment in `l1_missing_count()`, the findings-name code in `run.sh`, `bin/oversized-gate.sh`'s hash recomputation, and every archived findings directory, which is keyed by sha1 of the whole line. Adding a field to a line, or letting a path span two lines, silently invalidates all of them.

Before the enumeration check, a path containing a newline was written by `find` as two lines and the runner invented a second session that did not exist. The L1 fan-out used to read the file through `xargs -I {}`: a tab became a space, a backslash was deleted, and a quote killed the whole dispatch with "unterminated quote" (#54). It is NUL-delimited now.

A missing `shasum` empties the artifact hash silently, so every session in a night would target one findings filename.

## Decision

- The source of each session lives in a sidecar (`sessions-source.txt`) keyed by the artifact hash, never as a column in `sessions.txt`. A test asserts the file holds no tab.
- A newline in a path is rejected at enumeration and counted (`sessions_rejected_path`). A tab is refused too, because the TSV artifacts carry columns. Backslash, quote and apostrophe paths are triaged like any other path.
- The preflight test hides `shasum` with an empty PATH dir to prove the run stops before enumerating.

## Consequences

Any change that adds a field to `sessions.txt`, or shifts the hash input, needs a migration of every archived findings dir and of `oversized-gate.sh`. CLAUDE.md, "Which day a session belongs to" and "Self-audit", cover the rest of the artifact set.
