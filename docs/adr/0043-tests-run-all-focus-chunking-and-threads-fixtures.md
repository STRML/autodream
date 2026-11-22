# 0043: run-all: focus, chunking and threads fixtures

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_focus_tag_*`, `test_focus_cli_*`, `mk_codex_session`); see docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript "The focus mod", `tests/run-all.sh` (`mk_chunky`, `chunk_reads`, `turn_stats`, `test_chunking_an_omp_session_cuts_the_day_then_chunks_the_live_chain`), `tests/run-all.sh` (`test_threads_backfill_budget_uses_grown_index_request`)

## focus-tag fixtures and shims are built to hit one failure each

### Context

`bin/autodream-focus.sh` and `bin/vault-notes.sh` fail silently in ways a happy-path fixture cannot reach. The tests inject specific faults and use dates and shapes chosen for the trap.

### Decision

- Local day: 23:30 in New York on `$DATE` is 04:30Z the next day. Judged by UTC it would wait a night, and evening is when the day is reviewed. The test sets `TZ=America/New_York`.
- No jq: the PATH holds only the tools the script uses, with jq left out, because macOS 15 ships jq in `/usr/bin`.
- Torn last line: the untag assertion compares content, not bytes. The torn line comes back with the newline that ends it, which is what stops the next tag being glued onto it.
- Read failures: a jq shim exits 5 on the `-R -n` read of the tags file (an I/O error). A `tail` shim exits 1, so the torn-line check cannot be answered and must not be guessed. For `last --harness omp` the jq shim fails only on the `-c -s` turn-picking call, so the live-branch copy exists when it dies and the test can assert that no copy is left in `TMPDIR`.
- Unlocked writer: a `tail` shim appends a line just before the add's append, and an `awk` shim appends after the untag's rewrite. They stand in for an old mod build that takes no lock, and each depends on which command runs at that point in the script.
- Codex: a person's turn is an `item_completed` `UserMessage` event. The `response_item` messages with role user are what Codex injects, and the last one is injected after the last real prompt. Choosing by position or by a first character picks the wrong turn.
- Relative transcript: the test runs from the directory where the relative path resolves, and the path must still be refused, because the nightly run reads from another directory.

### Consequences

Reordering commands inside `autodream-focus.sh` can move a shim's trigger point. Re-check that each shim still fires before editing.

## chunking tests count from the fixtures and the mock's captures, with tiny size knobs and a prefix-only header check

### Context

The chunked-triage section of the suite checks a mechanical split and merge. A test that took its expected counts from the code under test would pass whatever the code did. A fixture of a few KB also has to behave like a multi-MB session. docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage "Reading a long session: chunked triage" describes the feature, and "Tests" has the shard and `TMPDIR` rules.

One omp assertion parsed the first chunk's header line with `jq`. The header embeds the session's absolute path and is cut at the slimmer's 400-character line cap. It is 391 characters under a 9-character `TMPDIR`. A `TMPDIR` 9 characters longer (a Mac's default, or one shard's nested temp dir) cut it mid-JSON, and `jq` on the cut line printed nothing.

### Decision

Expected counts come from the fixtures (`mk_chunky` writes numbered `turn-NNN` markers) and from what the mock engine was handed (`MOCK_CAPTURE_DIR` keeps every transcript a worker read, listed by `chunk_reads`), never from the runner's own counters. `AUTODREAM_SLIM_BYTES` and `AUTODREAM_L1_CHUNK_BYTES` are set to a few thousand bytes so the fixture chunks. The omp header assertion compares only the first 24 characters (`{"type":"autodream_meta"`) and never parses the line.

### Consequences

A new chunking assertion should count markers in the captured chunk inputs, and should not rely on `run-stats.txt` as its only evidence. Any assertion that parses a slimmed line depends on `TMPDIR` length, so check a prefix instead. The 391-versus-400 margin is measured; a longer path in the fixture header moves it without any error.

## the backfill budget test sizes its input cap from the linker prompt, not a literal

### Context

The test seeds two dates for `threads.sh backfill --max-calls 2`. Day 1 (2019-12-30) holds one 80-byte goal and must link in one engine call. Day 2 (2019-12-31) holds two goals in two repos. It fits in one call while the index is small, but once day 1 has grown the index, its request exceeds `AUTODREAM_THREADS_MAX_INPUT` and splits into one call per repo group. The assertions (`actual_calls` stays at 2, day 2 is listed under `skipped_dates:`) only mean something if the split happens on day 2 and not on day 1.

A request is the linker prompt plus the index, so the margin between "fits" and "splits" is the cap minus the prompt size. The test leaves 649 bytes of request beside `prompts/THREAD_LINKER.md`.

### Decision

The test computes the cap at run time as `wc -c < prompts/THREAD_LINKER.md` plus 649. The 649 is the measured headroom for day 1's one-group request. Nothing else in the repo derives it.

### Consequences

A literal cap would break on the next edit to `THREAD_LINKER.md`:

- A longer prompt pushes day 1 over the cap. It becomes an unsplittable oversized request, and `threads.sh` refuses it (`repo-hint request is N bytes, over AUTODREAM_THREADS_MAX_INPUT`). The test then fails for a reason unrelated to the budget.
- A shorter prompt leaves room for day 2 to fit in one call. The test then passes without exercising budget enforcement after context growth.

If you change the seeded goals or repo paths, re-measure the 649.
