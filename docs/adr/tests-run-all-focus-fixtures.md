# tests-run-all: focus-tag fixtures and shims are built to hit one failure each

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_focus_tag_*`, `test_focus_cli_*`, `mk_codex_session`); see CLAUDE.md "The focus mod"

## Context

`bin/autodream-focus.sh` and `bin/vault-notes.sh` fail silently in ways a happy-path fixture cannot reach. The tests inject specific faults and use dates and shapes chosen for the trap.

## Decision

- Local day: 23:30 in New York on `$DATE` is 04:30Z the next day. Judged by UTC it would wait a night, and evening is when the day is reviewed. The test sets `TZ=America/New_York`.
- No jq: the PATH holds only the tools the script uses, with jq left out, because macOS 15 ships jq in `/usr/bin`.
- Torn last line: the untag assertion compares content, not bytes. The torn line comes back with the newline that ends it, which is what stops the next tag being glued onto it.
- Read failures: a jq shim exits 5 on the `-R -n` read of the tags file (an I/O error). A `tail` shim exits 1, so the torn-line check cannot be answered and must not be guessed. For `last --harness omp` the jq shim fails only on the `-c -s` turn-picking call, so the live-branch copy exists when it dies and the test can assert that no copy is left in `TMPDIR`.
- Unlocked writer: a `tail` shim appends a line just before the add's append, and an `awk` shim appends after the untag's rewrite. They stand in for an old mod build that takes no lock, and each depends on which command runs at that point in the script.
- Codex: a person's turn is an `item_completed` `UserMessage` event. The `response_item` messages with role user are what Codex injects, and the last one is injected after the last real prompt. Choosing by position or by a first character picks the wrong turn.
- Relative transcript: the test runs from the directory where the relative path resolves, and the path must still be refused, because the nightly run reads from another directory.

## Consequences

Reordering commands inside `autodream-focus.sh` can move a shim's trigger point. Re-check that each shim still fires before editing.
