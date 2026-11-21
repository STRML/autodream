# Redesign: remote sync follow-ups (#228, #229, #230)

Branch `fix/remote-sync-followups`, https://github.com/STRML/autodream/pull/234. The review gate blocked rounds 1 to 4, a first redesign (reserved labels, below) ran as round 5 and blocked on three new P1s, and this is the second redesign. It groups every blocking finding by the mistake behind it and rules each group out.

## Blocking findings, by group

| Group | Mistake | Findings (round) |
|---|---|---|
| A | Treating a sync status or a run-stats file as proof that a report was delivered | `partial` omitted (1); failed rebuild clears the warning (1); same for older nights (2, 3); marker cleared by a half-written report (2); successful sync clears the warning when the mirror could not be enumerated (5) |
| B | An alternate output path (the empty-night stub) not carrying the obligations of the main one | stub: no warning about triage decisions, no counted question, no unreadable-scan line (1); no unknown-mirror line (5, P2) |
| C | Keys of different kinds sharing one flat `remote_sync_<name>` namespace in run-stats | host `invalid` (1); host `studio_cause` (3, 4) |
| D | A failed measurement recorded as a value | mirror size from a failed walk (1); read error as no match (1); newline in a path (5, P2); a failed date computation (5, P2) |
| E | A path or resource built from a failed allocation | `/0.status` (1); leaked job dir (1) |
| F | Related state published in two unprotected steps, or replaced by a narrower view | a delivered report keeps the previous report's marker if the run dies between them (5); a rebuild configured with fewer hosts erases a short host (5) |

Groups A and F are one mistake seen twice: the record of "which hosts this report did not read" lived outside the report, in `remote-short.txt` and in run-stats, so it could disagree with the report it described. Rounds 1 to 5 fixed the disagreements one order at a time. `CLAUDE.md` already names the rule that ends it (`question-streaks.sh`: "when a fix starts choosing which of two files to write first, merge the files instead").

## Design

1. **The record is a line in the report.** `<!-- autodream:remote-short=a,b -->`, the labels the report did not fully read, empty when none. It is written inside the same atomic write as the report body: the L2 writer's `{ report_body; remote_short_line; } > tmp && mv tmp report`, and the stub's heredoc. `remote-short.txt`, `write_remote_short_marker`, `migrate_remote_short_marker` and the run-stats fallback are deleted. A run killed before it publishes, a rebuild that defers, and a write that fails all leave the old report with its old record, by construction.
2. **What a report did not fully read** (`remote_short_labels`): every configured label whose sync was not `ok` (`partial` counts); every configured label when `ROOTS_FAILED`, `ROOTS_UNAVAILABLE` or `PARTIAL_ROOTS` is above zero, because a failed root cannot be told apart from a mirror; and every label in the record of the report being replaced that this run does not configure (`REMOTE_PREV_SHORT`, read at the top of `sync_remote_roots` before anything moves the old report), so a rebuild with fewer hosts cannot erase it. With remote sync off the line is still written when the replaced report carried one.
3. **The scan reads reports.** For each of the seven days before the target date, `$DREAMS_DIR/<date>.md`, read once into memory. A record line names the labels; a report with no line (remote sync was off, or it predates the record) is skipped. A night with a findings dir and no report (a rebuild that died in L2 moved the old one aside, and the next trigger rebuilds it), a report that will not read, or a date that will not compute is counted in `remote_short_scan_unreadable`.
4. **No migration.** Nights since remote sync shipped (2026-11-18) were already named by their own self-audit line, so the scan does not look at them. This removes the run-stats fallback whose hole (a rebuild rewrites run-stats before L2 runs) the gate found in rounds 2 to 4.
5. **Reserved labels** (kept from the first redesign): `invalid` and any name ending in `_cause` or `_last_ok` are refused, ahead of the adapter check, so run-stats lines cannot be mistaken for a host.
6. **Smaller fixes from round 5:** the mirror size is `unknown` when a path holds a newline; the empty-night stub says when a mirror could not be measured; a failed date computation counts as unreadable. Not changed: an inaccessible parent of a mirror reading as an empty one (P2; `-d` cannot tell absent from unreadable, and a mirror with an inaccessible parent also fails the sync that creates it).

## Failure matrix

| State or input | What the operation does | How it can fail | What the caller is told | Test |
|---|---|---|---|---|
| Earlier report's record names the label | Date listed, oldest first, inside seven days | Window off by one; clean or record-less report listed | `remote_short_dates_<label>` | `short_dates_lists_earlier_dates_the_host_missed` |
| Nothing short | `none` | Key absent reads as an old runner | `remote_short_dates_<label>: none` | `short_dates_none_when_every_earlier_date_was_read` |
| Label still failing tonight | No scan for it | Dates listed for a host that is still down | Failure line and banner | `short_dates_not_scanned_while_the_host_is_still_down` |
| Report missing (findings dir exists) or unreadable | Skipped, counted | Read as clean | `remote_short_scan_unreadable: N` | `short_dates_counts_a_night_it_cannot_read` |
| Label renamed or removed | Not listed | Listed under another label | Nothing | `short_dates_only_for_labels_in_the_config` |
| Host failed, host back, date rebuilt with `--force` | Next night names the date; the rebuilt report's record is empty | Rebuilt date stays listed | Question and command, then nothing | `short_date_is_named_until_it_is_rebuilt` |
| Rebuild dies in L2 | Old report moved aside, no report at the path; the next trigger rebuilds it and the record follows the new report | Old record lingers beside a missing report | Counted unreadable until the trigger delivers | `failed_rebuild_is_retried_by_the_next_trigger_and_its_record_follows_the_report` |
| Rebuild configured with fewer hosts | Record keeps the dropped host's label | Dropped host erased | Record `a` after rebuilding with `b` only | `rebuild_with_fewer_hosts_keeps_the_record_of_the_one_it_dropped` |
| Rebuild with remote sync off | Line still written with the carried labels | Record dropped | Record kept | `rebuild_with_remote_sync_off_keeps_the_record` |
| Sync ok but a root could not be enumerated | Every configured label recorded short | Cleared because the sync was ok | Date offered for rebuild | `incomplete_enumeration_marks_every_host_short` |
| Reserved label | Refused under key `invalid`, before the adapter check | Key collision | Cause names the label and the rule | `reserved_labels_are_refused`, `reserved_label_is_refused_before_the_adapter_check` |
| Empty night, earlier date short | Question inside the sentinels, counted, with the warning | "None" and zero | Question and streak | `empty_night_stub_asks_the_question_and_counts_it` |
| Empty night, scan or measurement failed | Stub says so | Silent | A sentence | `empty_night_stub_says_the_scan_could_not_read_a_night`, `mirror_size_failure_is_unknown_not_zero` |
| Job dir cannot be made | No job starts, no result read | `/0.status` read | `failed (cannot make a job dir for the sync jobs)` | `no_job_dir_fails_each_host_and_says_why` |

## What does not change

Parallel sync, the job dir keyed by pid, the mirror archive and its size keys, and the PROMPT question title stay. Tests that seeded run-stats or a marker are rewritten to seed a report with a record line.
