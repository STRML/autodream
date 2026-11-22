# bin-b: unread bookmarks are emitted from state, sorted by id, and marked read only after a real report

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`emit_unread`, `merge_state`, `mark_read`, `collect_bookmarks`)

## Context

CLAUDE.md "X bookmarks as idea fuel" and "What the consume gate actually has to check" give the contract. Five defects shaped the code:

- After a failed run the bookmarks are already recorded as seen (so incremental paging stops at them) but nobody was shown them. Emitting only this fetch's finds would drop them forever.
- The fetch appends each page newest-first, so file order is chronological only within one run. Taking the head or tail of it served the oldest 40 bookmarks.
- Cursor pagination can return one post on two pages (the timeline shifts between requests). Deduping against `$SEEN` alone, which is state from before the run, wrote both copies: one bookmark shown twice, using two `MAX_UNREAD` slots.
- `$TMP` is under `TMPDIR`, a different filesystem on macOS, so `mv` from there is a copy-then-unlink, not an atomic rename. A truncated `seen.jsonl` re-surfaces every lost bookmark as unread.
- In `$ids | index(.id)` the `.` has already been rebound to the array, so `.id` indexes an array with a string and jq errors on every line. The result is a silent no-op that leaves everything unread forever.

## Decision

- `collect_bookmarks` merges the fetch into `seen.jsonl`, then `emit_unread` emits every entry with a null `read_on`, not only this fetch's. A failed fetch still lets earlier unread bookmarks through; "failed" is the header only when there is also nothing to show.
- `emit_unread` sorts by `[(.id | length), .id]` descending. Snowflake ids exceed 2^53, so `tonumber` would round them. Length-then-string orders numeric strings correctly even if X shortens ids again.
- `merge_state` keeps an `accepted-ids` file for ids taken during this run, and stages its temp file in `STATE_DIR` so `mv` is a real rename, gated on the copy having succeeded. `mark_read` stages in `STATE_DIR` for the same reason.
- `mark_read` binds `.id as $i` before the pipe into `$ids`.
- run.sh calls `mark-read` only after a non-empty report exists.

## Consequences

Never sort by file position, stage state outside `STATE_DIR`, or rebind `.` before reading `.id` in that filter. `tests/x-bookmarks.sh` pins the emit order and the mark-read no-op.
