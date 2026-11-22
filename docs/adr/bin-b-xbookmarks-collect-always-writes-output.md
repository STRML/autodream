# bin-b: every collect path exits 0 and writes its output file, and failure reasons cross subshells through a file

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`collect`, `fail`, `state_write_failed`, the `HAVE_JQ` dispatch)

## Context

`x-bookmarks.sh` runs inside the nightly pipeline. X changing a bundle path at 3am must not cost a night's report, and PROMPT.md reads an absent `x-bookmarks.md` as "feature not enabled, do not mention it". So a failure has to be the content of the file, never an exit code or a missing file. CLAUDE.md "X bookmarks as idea fuel" states the invariant.

Three incidents shaped the code:

- A missing `jq` used to `exit 0` before the dispatch. run.sh's `|| log` never fired, and a user with working credentials saw the section vanish from every report with nothing separating "off" from "broken". The jq check now only sets `HAVE_JQ`, and `collect` writes a `fetch failed` stub.
- `fail()` first assigned `FAIL_REASON` from inside nested command substitutions (`qid=$(get_query_id)` runs `qid=$(detect_query_id)`). Each forks a subshell whose variable writes are discarded, so the cookie-expiry remediation arrived as an empty string and the report said a fetch failed for no stated reason.
- `merge_state` failing meant this run's bookmarks never reached state, and `emit_unread` read the old state: with none, the report was told there is nothing unread (#108).

## Decision

- `fail` writes the reason to `$TMP/fail-reason`, and `fail_reason` reads it. A file crosses the subshell boundary; a variable does not.
- Every `collect` outcome (not configured, credentials broken, fetch failed, jq missing) writes `x-bookmarks.md` and the manifest and exits 0.
- A failed `merge_state` is reported through `state_write_failed`, under the `fetch failed` header L2 already treats as a failure, instead of letting an old state read as "nothing unread".

## Consequences

Nothing about a bookmark may ever change the exit status of `collect`, and a new failure path must write the file. A new value that has to leave `get_query_id` or `detect_query_id` must go through a file too (`bin-b-xbookmarks-provenance-recorded.md`).
