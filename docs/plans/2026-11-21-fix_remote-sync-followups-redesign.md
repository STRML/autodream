# Redesign: remote sync follow-ups (#228, #229, #230)

Branch `fix/remote-sync-followups`, https://github.com/STRML/autodream/pull/234. Review gate rounds 1 to 4 blocked, so this plan groups every blocking finding by the mistake behind it and rules each group out.

## Blocking findings, by group

| Group | Mistake | Findings (round) |
|---|---|---|
| A | Treating a sync status or a run-stats file as proof that a report was delivered | `partial` omitted from the list (1); failed rebuild clears the warning (1); same, pre-marker nights (2, 3); marker cleared by a half-written report (2) |
| B | An alternate output path (the empty-night stub) not carrying the obligations of the main one | stub tells the user to overwrite decisions with no warning (1); stub hides the question from the streak store (1); stub hides an unreadable scan (1) |
| C | Keys of different kinds sharing one flat `remote_sync_<name>` namespace in run-stats | a malformed entry's key `invalid` equals a host named `invalid` (1); a host named `studio_cause` read as `studio`'s cause line (3); `studio` plus `studio_cause` (4) |
| D | A failed measurement recorded as a value | mirror size from a failed walk (1); a read error read as no match (1) |
| E | A path or resource built from a failed allocation | `/0.status` from a failed `mktemp` (1); job dir leaked by a killed run (1) |

Groups A, B, D and E were fixed and not raised again in the delta rounds, except that round 2 to 4's repeat of A is really C's ambiguity at the migration site. Group C came back three times (rounds 3 and 4, and its first form in round 1) because each fix parsed run-stats better instead of removing what makes the parse ambiguous.

## The step that would have caught group C in round 1

Asking what a label may be called before writing a parser for the keys built from it. `remote_sync_<label>`, `remote_sync_<label>_cause`, `remote_sync_<label>_last_ok` and the refusal key `invalid` are all built by concatenation, so two different facts can print the same line. No parser can undo that; only the set of allowed labels can.

## Design change

1. **Reserved label names.** `sync_remote_roots` refuses a label equal to `invalid` or ending in `_cause` or `_last_ok`, in the same `case` as the character check and so ahead of the adapter check: the entry takes the key `invalid`, nothing syncs, the cause names the label and says it is reserved. A reserved label therefore never gets a key of its own, never reaches `REMOTE_SYNCED_LABELS` and never joins the marker. After this, `remote_sync_<name>` with a status value names a label exactly when `<name>` is not `invalid` and does not end in either suffix, for every file this code writes.
2. **The migration reads that rule and nothing else.** `migrate_remote_short_marker` is one pass: a status line whose key is not `invalid` and does not end in `_cause` or `_last_ok`, with the status words in one shared list (`REMOTE_SHORT_STATUSES`) that `remote_short_has` also uses. The two-pass `seen` logic goes, because it only existed to give a meaning to the names step 1 forbids.
3. **The migration also keeps the "read everything" answer.** When the old run-stats says `remote_sync: on` and names no short label, it writes an empty marker. Without it, a forced rebuild whose sync fails and then defers rewrote run-stats, the scan fell back to it, and a date whose standing report did read the host was listed as short (the inverse of group A, found in plan review). An old run-stats that is unreadable, or that awk cannot read, logs a WARNING instead of returning silently (group D).
4. **The stub marker needs the stub write to have succeeded.** `cat > "$REPORT_PATH"` has no move-aside, so a write that cannot open leaves the previous run's report, which `report_complete` accepts. `STUB_WRITTEN=$?` gates the marker.
5. **Residual, stated.** A run-stats file written before this change by a host whose label ended in a reserved suffix would migrate wrongly. The only host configured anywhere is `studio2` (https://github.com/STRML/autodream/issues/229 says "Today there is one host (studio2)"), so no such file exists. No shim is added.
6. **Deletion date.** The migration and the run-stats branch of `remote_short_has` only matter for nights written before the marker, inside a 7-day window. Both are removed after 2026-11-28; the comment above the function says so.

## Failure matrix

| State or input | What the operation does | How it can fail | What the caller is told | Test |
|---|---|---|---|---|
| Label `invalid` configured | Refused before ssh | Synced, then its `ok` line read as the refusal | `remote_sync_invalid: invalid`, cause names the label and the reserved rule, no rsync | `reserved_labels_are_refused` |
| Label `x_cause` or `y_last_ok` configured | Refused before ssh | Its status line read as another label's extra line | Same | `reserved_labels_are_refused` |
| Reserved label while the claude adapter is off | Refused as reserved, not as an adapter refusal | Written under its own key and joined to the marker | Key `invalid`; a real label in the same config is still refused for the adapter and listed | `reserved_label_is_refused_before_the_adapter_check` |
| Legacy run-stats with `other`, `other_cause`, `other_last_ok` and the key `invalid`, rebuild dies before a report | Migration writes `other` only | Extra lines or the refusal key read as hosts | Marker lists `other`; the next night names the date | `pre_marker_migration_skips_a_labels_extra_lines` |
| Legacy run-stats says `remote_sync: on` and every host `ok`, forced rebuild's sync fails and no report follows | Migration writes an empty marker | Run-stats rewritten with `failed`, scan falls back to it and lists a date that did read the host | Date not listed | `pre_marker_ok_night_is_not_made_short_by_a_failed_rebuild` |
| Legacy run-stats has no `remote_sync: on`, or cannot be read | No marker; a WARNING for the unreadable case | Silent return | Log line | by inspection (a mode-000 run-stats is skipped as root in CI) |
| Stub report write fails to open | Marker untouched | `report_complete` accepts the earlier report and clears the marker | Date still listed | gated on `STUB_WRITTEN`, by inspection (no test can make the write fail without breaking the run) |
| Forced rebuild syncs, then no report | Marker from the earlier delivery stands | Cleared by the rebuild's run-stats | Date still listed | `failed_rebuild_keeps_the_date_listed` |
| Report written but not validated (stub half-write, degraded capture) | Marker untouched | Cleared on `-s` | Date still listed | gated by `L2_DELIVERED` and `report_complete` |
| Empty night, host synced, earlier date short | Question inside the sentinels, counted, with the triage-decisions warning | "None" and a zero count | Question and streak escalation | `empty_night_stub_asks_the_question_and_counts_it` |
| Empty night, an earlier night unreadable | Stub says it could not be checked | Silent | A sentence in the stub | `empty_night_stub_says_the_scan_could_not_read_a_night` |

## What does not change

Marker file semantics, the scan, the stub, the job dir and the mirror size stay as they pass today. Two tests are replaced: the one that had a host named `invalid` syncing (that name is now refused) and the one that kept a host named `studio_cause` (ditto). The stale text that described `invalid` as a malformed entry is updated in `bin/run.sh`, `CLAUDE.md`, `prompts/PROMPT.md` and `README.md`. `bin/remote-sync.sh` keeps its own character check and no reserved-name check, because only `run.sh` builds run-stats keys.
