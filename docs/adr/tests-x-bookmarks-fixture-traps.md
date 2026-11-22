# tests-x-bookmarks: fixture shapes that keep an assertion able to fail

Status: accepted · Date: 2026-11-22 · Code: `tests/x-bookmarks.sh` (`fixture_page`, `deny_writes`, `test_walk_reaches_every_suffix_variant`, `make_har`, `make_page2`, `test_the_cursor_is_matched_as_a_value_not_a_substring`)

## Context

Each shape below was chosen because the obvious fixture lets the guarded bug pass.

## Decision

- **Emit order.** `fixture_page` lists id 100 (older) before id 200 (newer), so file position is oldest-first. The emit is newest first, so an implementation that trusts file position fails `test_newest_first`. Do not reorder the entries to match the output.
- **`deny_writes`.** `chmod 555` blocks writes for everyone but root. The helper probes with a real write and returns 1 when the directory still takes one, and callers then skip. A root run neither fails nor passes for the wrong reason.
- **Walk fixture.** `test_walk_reaches_every_suffix_variant` serves 30 `main.*.js` page URLs and a `bundle.Bookmarks.<hash>` variant whose chunk URL is the last one the walk enumerates (`<hash>9`). With the old global cap of 24 requests that variant sat behind the 30 page URLs and was never requested (#107).
- **HAR cursors.** `make_har` writes the cursor into each Bookmarks request's `variables` parameter: none for the first pair, `CURSOR_END` for the rest, `-` for none. The reader matches the cursor as a value in `variables`, so a HAR whose URLs lack it cannot exercise paging.
- **Cursor `20`.** `test_the_cursor_is_matched_as_a_value_not_a_substring` sets the bottom cursor to `20`, which is also the page size in every URL (`count%22%3A20`). A substring match reads page one as its own next page and accepts a capture with no page two.
- **Page two.** `make_page2` replaces the entries with one bookmark and no bottom cursor, so the last page reads as the end of the timeline. Adding a cursor entry turns the "complete under the cap" cases into incomplete ones.

## Consequences

Changing any of these fixtures can leave every assertion green with the guard removed. After editing one, rerun the test against a reverted guard.
