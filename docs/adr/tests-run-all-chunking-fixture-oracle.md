# tests-run-all: chunking tests count from the fixtures and the mock's captures, with tiny size knobs and a prefix-only header check

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`mk_chunky`, `chunk_reads`, `turn_stats`, `test_chunking_an_omp_session_cuts_the_day_then_chunks_the_live_chain`)

## Context

The chunked-triage section of the suite checks a mechanical split and merge. A test that took its expected counts from the code under test would pass whatever the code did. A fixture of a few KB also has to behave like a multi-MB session. CLAUDE.md "Reading a long session: chunked triage" describes the feature, and "Tests" has the shard and `TMPDIR` rules.

One omp assertion parsed the first chunk's header line with `jq`. The header embeds the session's absolute path and is cut at the slimmer's 400-character line cap. It is 391 characters under a 9-character `TMPDIR`. A `TMPDIR` 9 characters longer (a Mac's default, or one shard's nested temp dir) cut it mid-JSON, and `jq` on the cut line printed nothing.

## Decision

Expected counts come from the fixtures (`mk_chunky` writes numbered `turn-NNN` markers) and from what the mock engine was handed (`MOCK_CAPTURE_DIR` keeps every transcript a worker read, listed by `chunk_reads`), never from the runner's own counters. `AUTODREAM_SLIM_BYTES` and `AUTODREAM_L1_CHUNK_BYTES` are set to a few thousand bytes so the fixture chunks. The omp header assertion compares only the first 24 characters (`{"type":"autodream_meta"`) and never parses the line.

## Consequences

A new chunking assertion should count markers in the captured chunk inputs, and should not rely on `run-stats.txt` as its only evidence. Any assertion that parses a slimmed line depends on `TMPDIR` length, so check a prefix instead. The 391-versus-400 margin is measured; a longer path in the fixture header moves it without any error.
