# runsh: superseded stale and partial copies are retired outside the `-f "$REPORT_PATH"` test

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `STALE_REPORT` removal, `drop_stale_report_copies`, the `.partial-*` loop)

## Context
- The retirement has to sit outside the `-f "$REPORT_PATH"` test (#40). A successful partial move leaves that path gone, so a stale copy went unmentioned in the one outcome where the user most needs to be told where their last good report went.
- The moved-aside copy was insurance against this rebuild producing nothing. A complete report means the insurance has expired, and dropping it stops every `--force` rebuild from leaving another `.stale-<epoch>` file in the dreams dir forever. Only a COMPLETE report supersedes the old one; a truncated file is not a rebuild.
- A delivered report also supersedes the moved-aside copies of earlier failed rebuilds, which the block above never reaches (it only knows the copy this run made). The remote-short record is read from a copy only while no report has been delivered since, so leaving them would let a label a later retry read come back.
- Partials are prefixes of a report that now exists in full, so a complete report supersedes every one for this date, including partials from earlier nights, which the `.stale-*` rule can never reach. Without this they pile up with nothing to remove them.

## Decision
`rm` the run's `STALE_REPORT` when `report_complete`; call `drop_stale_report_copies` on a delivered, complete report; delete every `$REPORT_PATH.partial-*` when complete, else name the readable partial. See CLAUDE.md, "Remote hosts" (`drop_stale_report_copies`) and "What the consume gate actually has to check (PR #37 review)" (the `.partial-*` paragraph). `drop_stale_report_copies` deletes a copy, except one holding a `## Triage decisions` heading, which is renamed to `<report>.triaged-<epoch>` because it holds the user's own writing.

## Consequences
Do not nest this under the `-f` check. A copy left in the `.stale-*` glob means nothing has been delivered since, which the remote-short lookup relies on.
