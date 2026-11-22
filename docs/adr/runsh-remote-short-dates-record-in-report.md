# runsh: A report carries a record of the hosts it did not fully read, so later nights can name the gap

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`remote_short_scan`, `remote_short_line`, `remote_short_labels`, `remote_report_record`, `sync_remote_roots`, `REMOTE_PREV_SHORT`)

## Context
A finished report stops every later trigger at the guard, and the next night's mtime lower bound skips a transcript last written on the failed day, so a date whose host was down is never retried (#230). Rebuilding it replaces a report the user may have triaged, so nothing rebuilds on its own. An earlier design kept the record in a second file and spent four review rounds on the orders in which the two could diverge.

## Decision
The record is one line inside the report, `<!-- autodream:remote-short=a,b -->`: the labels that report did not fully read, empty when none. `remote_short_line` is called by the L2 writer and the stub inside the same atomic write as the report body, so the record and the report are one file and cannot disagree. A run killed before it publishes, a rebuild that defers, and a write that fails all leave the old report with its old record. A report with no such line was written with remote sync off (or before the record existed) and is skipped. With remote sync off, `remote_short_line` still writes the line when the report being replaced carried a record to keep, and writes nothing otherwise.

A run whose sync worked looks back `REMOTE_SHORT_SCAN_DAYS` (7) days and, per label that synced `ok` or `partial`, writes `remote_short_dates_<label>` (`none` when empty) plus an open question with the rebuild command (`autodream-now.sh <date> --force`). The question warns that a rebuild replaces that date's report, including any `## Triage decisions` already written into it, so a date already triaged should be left alone. A night with a findings dir and no report (a rebuild that failed in L2 moved the old one aside, and the next trigger rebuilds it), a report that will not read, or a date that will not compute is counted in `remote_short_scan_unreadable`. Only labels configured tonight are listed.

What a report did not fully read (`remote_short_labels`): every configured label whose sync was not `ok` (partial counts: rsync 23 can leave a file uncopied, which the next sync copies with an old mtime that the next day's lower bound skips); every configured label when the enumeration was incomplete (`ROOTS_FAILED`, `ROOTS_UNAVAILABLE`, `PARTIAL_ROOTS` above zero), because the roots that failed cannot be told apart from a mirror; and every label the replaced report listed that this run does not configure (`REMOTE_PREV_SHORT`), so a rebuild with fewer hosts cannot erase them.

`REMOTE_PREV_SHORT` is the record of the report at the path if it carries one, else of the newest moved-aside `.stale-<epoch>` copy that does: a rebuild that died in L2 moved the real report aside and may have left a record-less capture at the path. A copy cannot resurface an old label, because a delivered report removes every copy it supersedes (see `drop-stale-report-copies-keep-triage-decisions`).

See CLAUDE.md, "Remote hosts" (What a failed host loses, and how it is named later (#230)).

## Consequences
Do not move the record into a second file. The stub report must carry the same question inside its sentinels.
