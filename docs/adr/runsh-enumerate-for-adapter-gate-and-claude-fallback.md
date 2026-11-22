# runsh: enumerate_for delegates only to an accepted adapter, resolved once per scan, and keeps a claude-only inline find as the skew fallback

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`enumerate_for`, `scan_roots`)

## Context

An install whose `adapters/` tree predates the adapter loader (a stale link after a partial upgrade) must degrade, not lose the night, so an inline `find` stays as the fallback. That fallback hardcodes `*.jsonl`, and nothing reads `session_glob` from a manifest, so walking another harness's roots with the Claude glob would return nothing and read as a quiet night: a silent wrong answer rather than a loud one.

Checking only that `adapter.sh` is executable would run a directory that failed containment. Rebuilding the accepted set through `adapters_list` for every root costs two realpaths and a `jq` per adapter directory, and the answer cannot change mid-run because nothing writes to `adapters/` while a scan is in flight.

## Decision

`enumerate_for` calls `adapter_run <adapter> enumerate <root> $TARGET_DATE $ENUM_END` and returns its status unchanged (`return $?`, never a constant; see `enumeration-judged-by-output-not-status`) only when all three hold: the `adapter_run` function is defined (`declare -F adapter_run`, false on an install whose `adapters/` tree predates the loader), the adapter is in `ACCEPTED_ADAPTERS`, and its `adapter.sh` is executable. `scan_roots` assigns `ACCEPTED_ADAPTERS` once, from `adapters_list`. Anything else falls to the inline `find`, which is claude-only: for any other adapter name it logs "no adapter for ... no fallback that knows its session format" and returns 1, so the root counts as failed (see `enumeration-judged-by-output-not-status`).

## Consequences

The comment on the fallback called it unreachable "because only claude is ever enabled" and said it becomes live once a second adapter ships beside a stale `adapters/` link. The omp adapter is now accepted and can be enabled through `AUTODREAM_ADAPTERS`, so that skew is reachable (this is the ADR's reading, not the comment's). Do not give the fallback a non-claude glob. Do not move the `adapters_list` call back inside the per-root loop.
