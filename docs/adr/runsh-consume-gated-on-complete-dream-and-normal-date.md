# runsh: archive and mark-read consume input only after a complete report and only for the normal nightly date

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `NORMAL_TARGET_DATE`, `CONSUME_SAFE`, the `VAULT_NOTES archive`, `publish` and `XBOOKMARKS mark-read` steps)

## Context
- Gated on a complete report, deliberately stricter than the enclosing `-f` check (the original comment said "non-empty"; the code tests `report_complete`, which also requires the open-questions marker and, from the questions epoch on, the questions block): archiving a note or stamping a bookmark read after a run that produced nothing would throw away the only copy of input the user cared about, silently and unrecoverably.
- Also gated on `TARGET_DATE` being the date a normal nightly run would process (yesterday, right now, the same `pdate_yesterday` computation as the default at the top). `collect` is date-agnostic: it reads whatever is CURRENTLY in the vault inbox and CURRENTLY unread. That is right for tonight's date, but CLAUDE.md documents reprocessing an old one (`AUTODREAM_FORCE=1 run.sh 2026-05-29`), and archive/mark-read do not know the date is old: a rebuild of 2026-05-29 would archive a note written THIS morning into `processed/2026-05-29/` and stamp today's unread bookmarks read, and tonight's real run would find an empty inbox and nothing unread, so the note never reaches any report. Collection still runs unconditionally, so L2 still SEES today's notes and bookmarks as context; only the consuming side is skipped for an old-date reprocess.
- `AUTODREAM_CONSUME_DATE` overrides which date counts as normal, authoritatively and with no fallback, for the same reason `AUTODREAM_STATS_BIN` and `AUTODREAM_OVERLAP_BIN` do: the suite pins a fixed historical `TARGET_DATE`, so without an override every consume path would take the skip branch and the archive tests would pass while asserting nothing.
- Publishing is NOT consuming: it copies the report into the vault so it can be read on a phone, and a reprocessed date is as worth reading as a fresh one. It stays outside the date gate; only archive and mark-read, which destroy the user's only copy of input, are gated.

## Decision
`archive` and `mark-read` run only when `report_complete` holds, `CONSUME_SAFE` is 1 (see `stale-dream-moved-aside-before-l2-and-consume-safe`) and `TARGET_DATE` equals `NORMAL_TARGET_DATE` (`${AUTODREAM_CONSUME_DATE:-$(pdate_yesterday)}`). Each skip logs its own reason: no marker, a stale report that could not be moved aside, or an old-date reprocess. `publish` runs whenever the report is complete, before the `CONSUME_SAFE` and date checks. See CLAUDE.md, "What the consume gate actually has to check (PR #37 review)".

## Consequences
Do not widen consuming to old dates, and do not tie `publish` to the date gate. Tests that exercise archiving must set `AUTODREAM_CONSUME_DATE`.
