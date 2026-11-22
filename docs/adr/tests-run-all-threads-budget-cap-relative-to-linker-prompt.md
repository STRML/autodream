# tests-run-all: the backfill budget test sizes its input cap from the linker prompt, not a literal

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_threads_backfill_budget_uses_grown_index_request`)

## Context

The test seeds two dates for `threads.sh backfill --max-calls 2`. Day 1 (2019-12-30) holds one 80-byte goal and must link in one engine call. Day 2 (2019-12-31) holds two goals in two repos. It fits in one call while the index is small, but once day 1 has grown the index, its request exceeds `AUTODREAM_THREADS_MAX_INPUT` and splits into one call per repo group. The assertions (`actual_calls` stays at 2, day 2 is listed under `skipped_dates:`) only mean something if the split happens on day 2 and not on day 1.

A request is the linker prompt plus the index, so the margin between "fits" and "splits" is the cap minus the prompt size. The test leaves 649 bytes of request beside `prompts/THREAD_LINKER.md`.

## Decision

The test computes the cap at run time as `wc -c < prompts/THREAD_LINKER.md` plus 649. The 649 is the measured headroom for day 1's one-group request. Nothing else in the repo derives it.

## Consequences

A literal cap would break on the next edit to `THREAD_LINKER.md`:

- A longer prompt pushes day 1 over the cap. It becomes an unsplittable oversized request, and `threads.sh` refuses it (`repo-hint request is N bytes, over AUTODREAM_THREADS_MAX_INPUT`). The test then fails for a reason unrelated to the budget.
- A shorter prompt leaves room for day 2 to fit in one call. The test then passes without exercising budget enforcement after context growth.

If you change the seeded goals or repo paths, re-measure the 649.
