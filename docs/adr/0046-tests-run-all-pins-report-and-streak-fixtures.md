# 0046: run-all: pins, report lifecycle, citations and question-streak fixtures

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`mk_session_with_cwd`, `test_rollup_marks_trig_sandbox_sessions`, `test_pins_custom_slug_bucket_keeps_its_cwd`, `test_pins_unresolvable_cwd_still_counts_toward_a_collision`, `test_pins_bucket_named_subagents_is_a_project`), `tests/run-all.sh` (`test_pins_tab_in_cwd_never_splits_the_row`, `test_pins_forged_session_path_authorizes_nothing`, `pins_tamper_case`, `test_pins_ledger_wiped_by_a_worker_stores_nothing_twice`, `test_pins_failed_move_aside_leaves_no_temp_file`), `tests/run-all.sh` (`test_pins_applied_after_complete_report`, `test_pins_applied_before_notify`, `mk_stranded_pins`, `test_no_markdown_memory_writer_remains`), `tests/run-all.sh` (`test_unmovable_stale_report_disarms_consuming`, `test_partial_report_does_not_consume`, `test_run_outcome_is_written_only_for_a_delivered_or_untouched_report`, `test_unassembled_*`, `test_pre_marker_report_is_not_abandoned`, `test_missing_report_still_abandoned_before_epoch`, `test_dead_stdout_does_not_kill_the_run`, `run_dream_broken_pipe`), `tests/run-all.sh` (`streak_rows`, `test_question_streaks_state_lives_with_the_install`, `test_question_streaks`, `test_question_streaks_reruns_and_mismatch`, `test_question_streaks_lock_is_a_kernel_flock`), `tests/run-all.sh` (`test_citation_check_*`, `mk_report`, `mk_findings`); rule in `docs/adr/0009-l2-aggregation.md#a-citation-is-any-standalone-12-hex-token-so-a-stray-token-is-a-false-alarm-and-never-a-false-all-clear`

## pin and rollup fixtures reproduce the bucket and cwd shapes the host really has

### Context

The pin tests cover rows R1-R11 of the failure matrix in `docs/plans/2026-09-15-mnemopi-pins.md`; `tests/apply-pins.sh` holds the rows of `apply-pins.sh` itself. `run.sh` refuses a session whose cwd does not encode to the bucket it is stored in, and a fixture that breaks that rule tests the refusal instead of the case it names. Several real shapes decide the outcome, and each has a measured size.

### Decision

- Sessions go in the bucket Claude would use for their cwd. `lib-project.sh` (`encode_project`) is the one encoder, so fixtures call it and carry no second copy of the rule.
- A skill-creator trigger eval runs `claude -p` from `/private/var/folders/<x>/<y>/T/trig-<id>/repo` and deletes the directory afterwards. The runner cannot resolve that cwd, so the bucket key decides the `sandbox` column (docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, "Session roots" and the rollup notes). The look-alike `/Users/x/T/trig-parser` checkout must stay `no`.
- Slug buckets (`owner-repo`, set through `CLAUDE_CODE_PROJECT_DIR_NAME`) override cwd encoding, so no cwd ever encodes to them. On this host they are the main Rush and STRML repos: 68 of 359 buckets in `~/.claude`.
- A removed worktree gives a session whose cwd the adapter can no longer resolve (`rmdir` in the fixture). That was true of 8 of the 48 sessions on 2026-09-14.
- Claude Code writes workflow agents one level deeper than plain subagents: `<bucket>/<session>/subagents/workflows/wf_<id>/agent-*.jsonl` (65 such files on this host). A bucket may also be named `subagents`. The project is the directory directly under the session root, whatever it is called.

### Consequences

Replacing a fixture's cwd or bucket with a convenient literal can make the bucket check pass or fail for the wrong reason. Check that the fixture still encodes the way the row says before editing it.

## pin fixtures leave exactly one guard standing and build the bad state the way L1 or L2 could

### Context

Pin authorization has several layers. A fixture that trips an earlier layer passes without reaching the one it names. Several bad states also arrive through the model's Write tool, so the fixture has to build them the same way.

### Decision

- **Tab in a cwd.** The tab encodes to a dash, so the bucket really is the tab cwd's own and the bucket check passes. Only the tab guard stands between that row and a split `pin-projects.tsv` line.
- **Forged session path and tampered worklist.** The other project's session exists and is readable, but its mtime is outside the target date, so the run never enumerates or triages it. Only a forged `session_path`, or a line appended to `sessions.txt` by L1 or L2, can point at it. A fixture that touches it to the report day would make it a legitimate session.
- **Ledger wipe.** The test deletes the first run's findings JSONs before the forced rebuild. Otherwise L1 sees every session as done and never starts a worker, so the mock never empties the ledger and the runner's snapshot is never exercised.
- **Directory at the pins path.** `mkdir -p pins.jsonl/sub` is what L2's Write tool produces by writing any path under `pins.jsonl/`. `mv` cannot put that over the `mktemp` file, which is the case the move-aside guard exists for.

### Consequences

Giving the "other project" session an in-window mtime, or leaving the first run's findings in place, keeps the tests green and removes what they prove.

## the pin tests pin the order of run steps and where the pin block sits in the prompt

### Context

Pins are the only thing the nightly writes outside its own directory, so the order of steps decides what a killed or hung run can lose. `AUTODREAM_OPEN` runs synchronously inside `notify.sh`, so a blocking editor command holds the run there.

### Decision

- **Pins and their authorization list land before the report** (issue 72), so a complete report on disk always has them beside it. The test compares mtimes with `-nt`. `mk_stranded_pins` runs `sleep 1` before writing the report for the same reason: mtime resolution must separate the two files.
- **`notify.sh` is replaced by a stand-in** that records whether `pins-applied.tsv` was already non-empty when it ran. That checks the order directly. It does not need a real blocking command.
- **The pin block follows the report sentinel in PROMPT.md.** A capture cut off before the sentinel is retried whole, so a pin can never be stored for a report that was never delivered. The test compares the line numbers of the two prompt steps.
- **The report may only say a pin was proposed.** L2 exits before any pin is applied, and the runner can still refuse one, so PROMPT.md must not tell the report to call a pin stored.

### Consequences

Moving the pin step after report delivery, or editing PROMPT.md's step wording, fails these tests on purpose. The grep patterns for the two step lines are literal prompt text, so a prompt rewrite needs the patterns updated in the same change.

## report-lifecycle fixtures force each failure with a concrete mechanism

### Context

The report, the consume gate and `unassembled_dates` fail silently. Each test makes its failure happen by a specific mechanism, and would pass without the guard if that mechanism were swapped for a looser one.

### Decision

- Move-aside failure: `chmod 555` on the dreams dir, so the old report stays at the report path. Without the disarm, the retry loop and the consume gate both see the old file.
- `MOCK_MODE=l2_partial` writes a non-empty report with no open-questions marker, which is what a mid-write kill leaves. `-s` alone cannot tell it from a good report.
- Stub staging failure: the stub is written to `<report>.tmp` and renamed over the report, so a read-only old report is replaced. A directory at the staging path is what makes the write fail.
- Epoch: `AUTODREAM_MARKER_EPOCH` is pinned to the fixture's date so the marker is required. The default would exempt every 2020 date. A missing report must stay abandoned under an epoch that exempts an unmarked one: the epoch must not swallow it.
- The marker-less fixture has the real shape of the six reports in `~/.claude/dreams` that the check called abandoned every night.
- Dead stdout: `run_dream_broken_pipe` pipes the run into a reader that closes at once. Three runs died this way on 2026-08-02. Tee was killed, the next log line SIGPIPEd the run, and the retry loop, the move-aside and the consume gate were never reached. No error line said so, because saying so was the thing that died. See docs/adr/0001-runner-lifecycle.md#background-the-logger-could-kill-the-run-and-did-2026-08-02 "The logger could kill the run".

### Consequences

Running the suite as root defeats the `chmod`-based cases.

## the question-streaks tests use fixtures shaped to hit the specific failure, not the obvious one

### Context

docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered "Open questions that never get answered" has the feature and its review history. Several fixtures only have power because of a detail that looks arbitrary.

- The empty-night run sets `AUTODREAM_DIR` explicitly. `run.sh` takes its install dir from `AUTODREAM_DIR` (default `~/.claude/autodream`), not from its own location. A value that comes from that default is not exported on the early path, which is why both call sites pass it to the helper.
- `AUTODREAM_QUESTION_LOCK_WAIT=1`: the default is 15 one-second tries, and two cases each held a lock on purpose for all of them. That was 32 seconds of the suite, in a suite where one test takes 46.
- The unreadable-state case uses `chmod 200` (write-only), so a wrongly written update would land and the `cmp` would catch it.
- A streak key is hex, so it can be all digits. `awk` compares two numeric-looking strings as numbers: `clear 89709551468` matched the row `089709551468` (Codex review of omp-autodream 5f7ddaa). `awk -v` also decodes backslash escapes: `\060...` became `0...` and matched a real key (omp-autodream b67c2f1).
- `streak_rows` counts with `wc -l`, not `grep -c . || echo 0`: `grep -c` prints `0` and exits 1 on no match, so the fallback also fires and the value is `0\n0`. That trap is in docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent and still caught this test on its first run.
- The bad-`python3` loop tries exit codes 1, 7, 11 and 15, which include numbers the lock code once used for a holder.

### Decision

Each fixture keeps the shape above: an explicit `AUTODREAM_DIR`, a one-second lock wait, a write-only state file, a digits-only key with a leading zero, an escaped key, `wc -l` for row counts, and the extra `python3` exit codes.

### Consequences

Replacing the leading-zero key with an ordinary hex key, or the escaped key with a plain one, leaves the assertions passing against an `awk` comparison that is wrong. Raising the lock wait back toward the default adds about 30 seconds to the suite.

## citation fixtures copy the real 2026-08-18 report shapes

### Context

On 2026-08-18 L2 attached a correct Bitwarden finding (in `6f38f3cbed43`) to `47eba605cf1e`, a different session in the same project that was noise-gated. A gated stub still carries `project`, which makes the wrong hash look plausible. 10 of 11 citations that night were sound, so the defect is per citation, and the counters exist to make it measurable.

### Decision

The fixtures keep the shapes that night produced:

- Bare hashes in a parenthesised comma list with no backticks, as the real pre-fix report wrote them. Anchoring only on backticks scored that report `citations_total: 0`, a false all-clear. The test keeps a bare fixture.
- A 40-character commit SHA, to prove boundary matching. Its neighbouring characters are hex, so a 12-hex run inside it is not a citation.
- An omp session file name ending in a UUID whose tail is 12 hex characters (`87b5b1392572` was the tail of `...2026-08-18T15-43-51-432Z_01a0158b-1488-7000-bf4a-87b5b1392572.jsonl`). L2 cites omp sessions by that tail, so it must resolve by session path. Reporting it as unresolved would train the reader to ignore the counter.

### Consequences

Replacing the SHA fixture with a short one, or backticking the bare list, leaves the assertions passing with the boundary and bare-form logic removed.
