# tests: run-all-fixtures-mirror-real-shapes: run-all: fixtures reproduce the real on-disk shapes and dates

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_incomplete`, `test_noise_gate_trivial`, `test_stale_wrongtype_findings_is_redispatched`, `test_failure_class_provider_matrix`), `tests/run-all.sh` (`test_newline_path_is_rejected_not_split`, `test_artifact_hash_contract_is_unchanged`, `test_source_sidecar_is_written`, `test_preflight_stops_a_run_missing_a_dependency`, `test_unusual_session_paths_are_triaged_or_refused`), `tests/run-all.sh` (`test_session_stats`); `bin/session-stats.sh`, `tests/run-all.sh` (`test_stats_sidecar_missing_counted`, `test_stats_sidecar_malformed_counted`), `tests/run-all.sh` (`test_skill_fields_dropped_without_a_sidecar`, `test_skill_fields_are_enforced_from_the_sidecar`), `tests/mock-claude.sh` (`write_findings`), `tests/run-all.sh` (`mk_fanout_fixture`, `test_fanout_stats`), `tests/run-all.sh` (`LATE`, `mk_win_session`, `test_window_places_a_session_by_its_records_not_its_mtime`, `test_window_is_dst_correct_end_to_end`, `test_findings_outside_the_worklist_are_set_aside_not_deleted`), `tests/run-all.sh` (`test_idempotency_guard_needs_a_complete_report`), `tests/run-all.sh` (`test_runner_provenance_through_symlink`, `test_runner_provenance_relative_symlink`, `test_runner_provenance_unresolvable_chain`, `test_runner_dirty_ignores_untracked`)

## L1 fixtures reproduce the exact shape the runner left on disk, not a tidier one

### Context

Three tests pass or fail on a detail of the data that is easy to normalise away when the fixture is edited.

- The final-round stub is rewritten by the project-field normalization pass through `json.dump`, because it has a real `session_path` and no `project`. That turns `"findings":[]` into `"findings": []`.
- A findings file left by an earlier run can have `.findings` present but a string. The dispatcher guard called that "done" and exited, while `l1_missing_count` called it "missing", so nothing rewrote it and L2 aggregated it anyway. Three sites answer "is this record done?" and all three must agree.
- A worker's `.err` has a fixed layout: the worker's stderr at the top (omp's lands there), then run.sh's own lines (the session path, the exit-code line), then the stdout section, then run.sh's network note. The malformed-output branch dumps up to 2000 bytes of the worker's JSON with no trailing newline, so the session line lands on the same line as the dump. Each classifier case is a fixture of one of those positions.

### Decision

- The stub assertion matches `"findings": *\[\]`. It is about the empty array, not its spacing. `test_noise_gate_trivial` does the same for `"skipped": *"below_noise_gate"`: the normalization pass rewrites a gated stub (real `session_path`, no `project`) through `json.dump`, which reformats `"skipped":"below_noise_gate"` with a space.
- `test_stale_wrongtype_findings_is_redispatched` seeds `{"session_path":"STALE","findings":"oops"}` before the run and asserts the file is replaced by a real array.
- The `.err` fixtures in the provider/size matrix keep each worker-text, runner-text and marker line where run.sh writes it, including the dump fused to the session line.

### Consequences

Tightening the stub regex to the compact form fails on a correct run. Replacing the wrong-type seed with a missing or empty file removes the case where the guard and the counter disagreed. Tidying a `.err` fixture (adding the newline, reordering lines) turns it into a case the classifier already handled and stops it pinning the run.sh-written-text skip rules in `bin/failure-class.sh`. CLAUDE.md ("A failed worker leaves its evidence") has the rules the fixtures exercise.

## sessions.txt stays a list of bare, line-delimited paths, and the tests guard that

### Context

Four consumers derive an artifact key, or a filesystem path, from a whole line of `sessions.txt`: the hash assignment in `l1_missing_count()`, the findings-name code in `run.sh`, `bin/oversized-gate.sh`'s hash recomputation, and every archived findings directory, which is keyed by sha1 of the whole line. Adding a field to a line, or letting a path span two lines, silently invalidates all of them.

Before the enumeration check, a path containing a newline was written by `find` as two lines and the runner invented a second session that did not exist. The L1 fan-out used to read the file through `xargs -I {}`: a tab became a space, a backslash was deleted, and a quote killed the whole dispatch with "unterminated quote" (#54). It is NUL-delimited now.

A missing `shasum` empties the artifact hash silently, so every session in a night would target one findings filename.

### Decision

- The source of each session lives in a sidecar (`sessions-source.txt`) keyed by the artifact hash, never as a column in `sessions.txt`. A test asserts the file holds no tab.
- A newline in a path is rejected at enumeration and counted (`sessions_rejected_path`). A tab is refused too, because the TSV artifacts carry columns. Backslash, quote and apostrophe paths are triaged like any other path.
- The preflight test hides `shasum` with an empty PATH dir to prove the run stops before enumerating.

### Consequences

Any change that adds a field to `sessions.txt`, or shifts the hash input, needs a migration of every archived findings dir and of `oversized-gate.sh`. CLAUDE.md, "Which day a session belongs to" and "Self-audit", cover the rest of the artifact set.

## session-stats fixtures pin retired fields and anchored deny counting

### Context

`compliance_markers` was retired for claude on 2026-10-30 (omp: 2026-08-08). Agents follow the retry rules without typing the line, so the count only measured silence. `sandbox_shape_denies` counts tool results that open with a deny signed by the sandbox-shape guard. Measured 2026-11-03: 52 in one local-llm session, every one anchored.

### Decision

The markers fixture asserts the sidecar has no `compliance_markers` field, so reviving the count fails the test. The shape fixture covers the real deny (a `tool_use_error` with `is_error` true), bare and wrapped, array content, and several blocks in one record. It also holds the non-denies: a Read or grep that shows the string mid-text, an attachment, an assistant line, and the string on a later line of an error. The expected count is 5.

### Consequences

An unanchored match passes the deny cases and fails the non-deny cases. Add a new deny shape as a counted case, not as a fixture with the string anywhere in the text.

## the sidecar-health tests break the stats generator, because the runner regenerates every sidecar

### Context

`compute_session_stats` in `bin/run.sh` deletes and regenerates every sidecar on each run. A sidecar is kept only if the generator exits 0, writes a non-empty file, and the file is a JSON object (`jq -e 'type == "object"'`). A hand-edited sidecar is overwritten before anything reads it.

### Decision

- To get a missing sidecar, the test sets `AUTODREAM_STATS_BIN` to a path that does not exist.
- To get a sidecar that is read but unusable, the test points `AUTODREAM_STATS_BIN` at a stub that writes a valid object with no `transcript_bytes`. It passes the object check, survives generation, and fails at read time. This is the quieter of the two failure paths.

### Consequences

Seeding a bad file in the findings dir tests nothing, since the run replaces it. Writing the stub as a non-object makes the generator step drop it and reaches the other path instead. `stats_sidecars_unparseable` counts both, and the `oversized_total` fallback to the transcript's own size covers both.

## skill-field fixtures lean on the mock worker's empty `skills_invoked`, so the assertions have power

### Context

The runner overwrites `skills_invoked`, `skills_invoked_count`, `skills_invoked_counts` and `skills_authored` in every findings JSON from the stats sidecar. It removes all four when the sidecar is missing or lacks any of them (CLAUDE.md, "Skill fields are measured, not guessed"). A worker's own list is what let a report conclude "zero skills across 3,988 tool calls" on 2026-09-04, when the session had invoked skills.

### Decision

`tests/mock-claude.sh` always writes `skills_invoked:[]` in `write_findings`, which is the worker behavior behind that claim. The tests depend on it:

- The enforcement test builds a session that really invoked skills: two `Skill` calls, one `/triage` slash line and one SKILL.md write. It asserts the findings carry the sidecar's `deslop,triage`, the per-skill counts and the authored skill. A runner that believed the worker's empty list fails every one of those assertions.
- The no-sidecar test asserts all four keys are absent. With no sidecar to overwrite it, the mock's `[]` is a model guess that L2 would rank as a mechanical count.
- It also asserts `skills_unmeasured: 1` in run-stats. A missing field cannot say why it is missing: gated stubs and findings from before the fields existed lack them too, so the runner records the count.

### Consequences

If the mock's default findings carry real skill data, the enforcement assertions pass with the overwrite removed. Keep the mock's list empty, or give the enforcement fixture a session whose measured skills differ from whatever the mock writes.

## fanout fixture timestamps are chosen to stay inside the local report day in every timezone

### Context

A session belongs to a report day by the timestamps inside its transcript, and the day runs from local midnight to local midnight (CLAUDE.md, "Which day a session belongs to"). A fixture timestamp that lands on the next day in some timezone drops out of the window there, so the suite passes in one timezone and fails in another.

### Decision

The orphan fanout workers use `2020-01-02T09:05Z`. That is still 2020-01-02 locally from UTC-5 to UTC+11. The first draft used 18:05Z, which was already the next day in Hong Kong, Tokyo and Sydney, so the window dropped the workers there. 09:05Z also stays hours away from the other fixture sessions, so it does not create overlap.

### Consequences

Fixture timestamps for a report day must stay inside that day across UTC-5 to UTC+11, or the test fails on a developer machine in another zone. Moving the orphan workers toward the other sessions' times changes the overlap counts the test asserts.

## window tests state their expected sets from the fixtures, and the DST fixture sits where 23-hour and 24-hour days disagree

### Context

Issue #113: enumeration used to be `-newermt DAY ! -newermt NEXT`, so a session written to again after its day closed (a resumed one) vanished from every later rebuild of that day. The adapter's `find` is now a lower bound only (`run.sh` passes a far upper date) and `bin/session-window.sh` keeps files with a record inside the day. CLAUDE.md, "Which day a session belongs to", has the design.

### Decision

- Expected sets are worked out from the fixture timestamps, not read back from the code. `LATE` is three days after `DATE`, so a `find` with an upper bound would drop the file.
- The DST test runs under `TZ=America/New_York` on 2020-03-08. EST lasts until 02:00 and EDT follows, so local midnight is 05:00Z and the next one is 04:00Z. A record at 04:30Z on 03-09 is 00:30 EDT on 03-09 and is outside the report day. A fixed 24-hour window (end 05:00Z) would take it.
- The outside-worklist test needs two sessions in the worklist. `session_hash` prints no trailing newline, so a list of hashes run together matches nothing, and that made every findings JSON read as outside the worklist. A one-session worklist hides the bug.

### Consequences

If the expected values start coming from `session-window.sh` itself, the tests agree with the code by construction. Keep them as literals, and keep at least two in-window sessions in the outside-worklist fixture.

## the marker-guard test sets AUTODREAM_MARKER_EPOCH to the fixture date

### Context

`report_finishes_date` in `bin/run.sh` treats a report as finished when it carries the open-questions marker, or when the target date is before `AUTODREAM_MARKER_EPOCH` (default `2026-08-19`). The fixture date is `2020-01-02`, far before that default.

### Decision

The test runs with `AUTODREAM_MARKER_EPOCH="$DATE"`, which makes the fixture date one whose report must carry the marker. Without it the marker-less report counts as a legacy report, the guard skips it, and the test would not exercise #111. The same epoch is set for the second run, which shows a complete report is still a no-op.

### Consequences

Dropping the variable makes the first half of the test fail for a reason unrelated to the guard's marker check, or pass against a guard that never looks at the marker. Keep the epoch equal to `DATE`, not later.

## the runner-provenance fixtures copy the installed symlink layout, use physical paths, and stay under the hop cap

### Context

`run-stats.txt` records `runner_commit` and `runner_dirty` (#29). The runner finds its checkout by following its own symlink. `bin/run.sh` caps the walk at 8 hops, because macOS refuses to execute anything behind 16 or more links (ELOOP), so a cap at or above 16 could never fire.

### Decision

- The symlink test builds what `install.sh` leaves on disk: a real directory holding one symlink per script, not a link to the checkout. `cd "$(dirname "$0")"` then lands in a directory with no `.git`, and provenance has to follow the file's own link. Six production runs through 2026-08-03 stamped `unknown` against a clean checkout because earlier tests missed this.
- The relative-target test exists because `install.sh` writes absolute targets, so production never exercises the relative branch. Both sides go through `pwd -P` before `relpath`. `$TMPDIR` on macOS sits under `/var`, itself a link to `/private/var`, and a relative path computed from the logical name walks up through a directory that does not exist, so the link is born broken.
- The chain test uses 12 hops: above the cap of 8, below 16, so bash still runs the script and only the provenance field degrades. A truncated walk must say `unknown`, never stamp the sha of whatever checkout the truncated path sits in (here, this repo).
- `runner_dirty` counts tracked modifications only (`git status --porcelain --untracked-files=no`). A clean checkout with a stray untracked file reported `runner_dirty: yes` on the first production run. Untracked files are not code that exists in nobody's history.

### Consequences

A chain of 16 or more hops fails to execute on macOS and tests nothing. Using logical paths in the relative fixture can pass on Linux and break on macOS.
