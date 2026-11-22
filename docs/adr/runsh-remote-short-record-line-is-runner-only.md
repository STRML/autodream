# runsh: a remote-short record line inside L2's body is dropped; only the runner writes it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: the `awk '!/^<!-- autodream:remote-short=.* -->$/'` filter and `remote_short_line`)

## Context
Only the runner states which hosts a report did not read, and the short-dates scan takes the last record line it finds. A record line the model wrote into its own body could become a date's record when remote sync was off and the runner wrote none.

## Decision
The staged report is the model's body with any record-shaped line removed, followed by the runner's `remote_short_line`, in one `.tmp` and one `mv`. See CLAUDE.md, "Remote hosts" (what a failed host loses, "The record is a line inside the report").

## Consequences
Do not trust a record line from the body. Keep the record and the body in one atomic write; two files have an order of writes to get wrong.
