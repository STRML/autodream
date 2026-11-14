# Dropped threads implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Drafted by Codex Sol 2026-11-14 from `docs/design/dropped-threads-2026-11-14.md`; signed off by the Claude main loop the same day.

Goal: Implement dropped threads in three independently testable PRs, in the approved delivery order.  
Architecture: Trusted runner facts + L1 facets → tool-less linker → validated atomic index → report, CLI, dashboard.  
Tech Stack: Bash 3.2, jq, existing portable helpers, Python 3 stdlib, static HTML/JavaScript. Spec path: `docs/design/dropped-threads-2026-11-14.md`.  
Global Constraints: Planning only; repository unchanged. Commands below are future implementation steps. Preserve the spec’s eligibility rules, runner-owned provenance, catch-up without a watermark, and merge-only locking.  
Review Focus: F1–F12 compliance, concurrent updates, tool isolation, input injection, and repeatable candidate identity.

## PR 1: Thread index, linker, CLI, report section, and backfill

1. **Task 1.1: Add tool-less linker invocations to both adapters.**

   **Files**
   - Modify: `adapters/claude/adapter.sh`
   - Modify: `adapters/omp/adapter.sh`
   - Test: `tests/adapter-claude.sh`
   - Test: `tests/adapter-omp.sh`
   - Create/test: `tests/threads-tools-probe.py`

   **Interfaces**
   - `adapter.sh threads-argv MODEL`: emits NUL-delimited argv; rejects a missing model with exit 2.
   - Reuse `engine-bin` and `l1-env`.
   - Both invocations consume the prompt on stdin and return plain JSONL assignments on stdout.
   - Neither invocation receives an output path or filesystem tools.

   **Parallelism:** Can run alongside Task 1.2. Their files do not overlap.

   - [ ] **Write failing tests.** Add adapter contract cases named `test_claude_threads_argv_has_no_tools` and `test_omp_threads_argv_has_no_tools`. Decode the NUL stream into an argv array and assert:

     ```bash
     assert_eq "$rc" 0 "threads-argv exists"
     assert_eq "$requested_model" "fixture-model" "model passed literally"
     assert_eq "$tool_count" 0 "explicit empty tool list"
     assert_eq "$persists_session" false "headless calls leave no session"
     assert_eq "$loads_context_or_extensions" false "no ambient tools"
     ```

     Add the separate real-CLI probe. Its loopback fake provider returns a Write request, then a Bash write request, followed by a valid assignment. The probe must assert:

     ```python
     assert marker.exists() is False
     assert advertised_tools == []
     assert assignment_received is True
     ```

     Use isolated config/auth settings and dummy loopback credentials. This probe tests CLI enforcement; an argv-aware shell mock alone cannot prove that tools are unavailable.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/adapter-claude.sh
     TMPDIR=/tmp /bin/bash tests/adapter-omp.sh
     TMPDIR=/tmp python3 tests/threads-tools-probe.py --engine claude
     TMPDIR=/tmp python3 tests/threads-tools-probe.py --engine omp
     ```

     Expected: missing `threads-argv` exits 2 and fails the new assertions.

   - [ ] **Implement the verbs.**
     - Claude: retain the composed lean-query flags, subscription auth, and `--no-session-persistence`; pass `--tools ''`; disable hooks, slash commands, MCP configuration, and context loading. Use a system prompt that requests stdout JSONL.
     - OMP: pass an explicit `--tools=` plus its supported `--no-tools`; retain the advisor/auto-recall overlay and `--no-session`; disable extensions, skills, rules, context files, and title generation.
     - Do not derive the OMP verb from its warmup invocation, which omits the tool restriction.
     - Use normal approval settings for these new verbs. Do not add `bypassPermissions`.
     - Before merge, verify empty-tool enforcement with both installed CLIs. The inspected OMP help advertises `--tools` and `--no-tools`; help output alone is insufficient evidence.

   - [ ] **Run green.** Repeat the four commands. Both real-CLI probes must finish without creating their marker.

   - [ ] **Commit.**

     ```bash
     git add adapters/claude/adapter.sh adapters/omp/adapter.sh tests/adapter-claude.sh tests/adapter-omp.sh tests/threads-tools-probe.py
     git commit -m "feat: add tool-less thread linker adapter commands"
     ```

2. **Task 1.2: Build the atomic state store and basic CLI.**

   **Files**
   - Create: `bin/threads.sh`
   - Create/test: `tests/threads-state.sh`

   **Interfaces**
   - State: `$AUTODREAM_DIR/threads.jsonl`, one thread object per line.
   - Lock: `$AUTODREAM_DIR/threads.jsonl.lock`.
   - Record fields:

     ```text
     id, kind, repo, title, goal, sessions[], status, done_by, last_seen
     sessions[]: date, hash, session_path, outcome
     ```

   - CLI:
     - `threads.sh list [--status STATUS] [--kind KIND] [--repo PATH] [--json]`
     - `threads.sh search QUERY [--json]`
     - `threads.sh close ID`
     - `threads.sh reopen ID`
   - Proposed functions in `bin/threads.sh`:
     - `threads_read_state`
     - `threads_acquire_lock`
     - `threads_release_lock`
     - `threads_write_state NEXT_FILE`
     - `threads_set_status ID STATUS`
     - `threads_is_dropped AS_OF LAST_SEEN STATUS OUTCOME`

   **Parallelism:** Can run alongside Task 1.1. Later tasks modify `bin/threads.sh` serially.

   - [ ] **Write failing tests.** Cover public CLI behavior with seeded JSONL:

     ```bash
     # test_threads_close_and_reopen
     assert_eq "$closed_status" closed_by_sam "operator close persists"
     assert_eq "$closed_done_by" sam "operator owns the close"
     assert_eq "$reopened_status" open "explicit reopen succeeds"

     # test_threads_state_write_is_atomic
     assert_eq "$after_failed_write" "$before" "old state survives"
     assert_eq "$after_failed_rename" "$before" "rename failure preserves state"

     # test_threads_cli_refuses_unreadable_state
     assert_eq "$rc" 1 "CLI reports unreadable state"
     assert_eq "$after" "$before" "state is not replaced with an empty index"

     # test_threads_list_computes_dropped
     assert_eq "$age_seven_count" 0 "older than seven days is strict"
     assert_eq "$age_eight_count" 1 "unfinished open thread becomes dropped"
     assert_eq "$mostly_achieved_count" 0 "mostly achieved stays quiet"
     ```

     Include invalid IDs, unknown IDs, literal search metacharacters, `08` configuration parsing, and a stale lock.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/threads-state.sh
     ```

     Expected: assertions fail because `bin/threads.sh` does not exist.

   - [ ] **Implement the store and CLI.**
     - Resolve the install directory with `lib-install-dir.sh`; load config with environment values winning.
     - Source `portable.sh`; use `pdate_shift`, `pdate_epoch`, and `pstat_mtime`.
     - Only a missing index means an empty index. An existing unreadable or malformed index refuses writes.
     - Require IDs matching `^t-[0-9a-f]{8}$`.
     - Copy the `question-streaks.sh` destination-local temporary file plus single-rename pattern.
     - Create the state directory before attempting the lock.
     - Pin stale reclaim to **older than 120 seconds**.
     - Make one initial lock attempt and **three retries**, one second apart. CLI exhaustion exits nonzero.
     - Re-read state after acquiring the lock. `close` and `reopen` use this same lock.
     - Store `closed_by_sam` with `done_by: sam`; reopening clears closure attribution.
     - Compute dropped status at read time with default `AUTODREAM_THREADS_DROPPED_DAYS=7`. Never persist `"dropped"`.
     - Keep state and membership in one atomic file. Do not copy the question-streak watermark.

   - [ ] **Run green.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/threads-state.sh
     ```

     Expected: every state and CLI assertion passes under `/bin/bash`.

   - [ ] **Commit.**

     ```bash
     git add bin/threads.sh tests/threads-state.sh
     git commit -m "feat: add atomic thread state and management CLI"
     ```

3. **Task 1.3: Connect trusted session inputs, catch-up, the linker, and merging.**

   **Files**
   - Modify: `bin/run.sh`
   - Modify: `bin/threads.sh`
   - Create: `prompts/THREAD_LINKER.md`
   - Modify/test: `tests/run-all.sh`
   - Modify/test: `tests/mock-claude.sh`

   **Interfaces**
   - Runner function: `thread_source_rows FROM TO`.
   - Runner variable: `THREAD_SOURCE_ROWS`, captured before the first L1 call.
   - Runner variable: `THREADS_REFRESH_KEYS`, containing existing source keys successfully re-triaged during this run.
   - Trusted input JSONL fields:

     ```text
     date, hash, source, session_path, cwd, repo,
     nested, user_message_count, measured
     ```

   - `threads.sh update DATE` consumes trusted source rows on stdin.
   - Proposed functions:
     - `threads_collect_candidates`
     - `threads_build_requests`
     - `threads_call_linker REQUEST_FILE RESPONSE_FILE`
     - `threads_validate_assignments`
     - `threads_merge_assignments`
   - Candidate fields: `hash`, `kind`, `repo`, `goal`, `outcome`.
   - Assignment JSONL: `{hash, thread, title?, finished}`.
   - Use a request-local `hash` handle containing date and session hash, mapped back through the runner’s candidate table. Persist the original 12-character session hash. This distinguishes one transcript appearing on multiple report days without adding model-supplied provenance.
   - Counters:

     ```text
     threads_state: ok|unreadable
     threads_link: ok|not_needed|failed
     threads_linked: N
     threads_rejected: N
     threads_close_refused: N
     threads_unmeasured: N
     threads_calls: N
     threads_skipped: locked        # only when applicable
     ```

   **Parallelism:** Starts after Tasks 1.1 and 1.2; overlaps their implementation files.

   - [ ] **Write failing E2E tests.** Add every test through `_run test_name`. Extend the mock with independent `MOCK_THREADS_MODE` and `threads-*` capture files, leaving existing L1/L2 modes intact.

     ```bash
     # test_threads_eligibility_and_goal_fallback
     assert_eq "$candidate_count" 2 "only eligible human sessions reach linker"
     assert_eq "$array_fallback_goal" "first initiative" "array fallback"
     assert_eq "$string_fallback_goal" "omp initiative" "string fallback"

     # test_threads_missing_sidecar_is_unmeasured
     assert_grep "$stats" '^threads_unmeasured: 1$' "missing measurement"
     assert_eq "$missing_sidecar_link_count" 0 "unmeasured source excluded"

     # test_threads_runner_provenance_survives_worker_tampering
     assert_eq "$stored_path" "$real_session" "runner path wins"
     assert_eq "$stored_repo" "$real_repo" "runner repo wins"
     assert_eq "$forged_source_count" 0 "forged worklist entry excluded"

     # test_threads_one_call_across_repo_hints
     assert_eq "$calls" 1 "normal night makes one linker call"
     assert_eq "$linked_harnesses" "claude,omp" "bucket encodings converge"
     assert_eq "$linked_repos" 2 "repo is a hint, not a partition"

     # test_threads_no_eligible_sessions_makes_no_call
     assert_eq "$calls" 0 "empty pending set skips model"
     assert_grep "$stats" '^threads_linked: 0$' "honest zero"

     # test_threads_linker_failures_preserve_state_and_catch_up
     assert_eq "$failed_index" "$before" "failure leaves index untouched"
     assert_eq "$run_exit" 0 "report still completes"
     assert_grep "$stats" '^threads_link: failed$' "failure disclosed"
     assert_eq "$next_night_missing_links" 0 "next night catches up"

     # test_threads_rejects_assignments_individually
     assert_eq "$valid_links" 1 "valid sibling survives rejected rows"
     assert_grep "$stats" '^threads_rejected: 3$' "three bad rows counted"

     # test_threads_finished_requires_achieved_outcome
     assert_eq "$unfinished_status" open "unsupported close refused"
     assert_grep "$stats" '^threads_close_refused: 1$' "refusal counted"

     # test_threads_unreadable_index_prevents_write_and_render
     assert_eq "$state_after" "$state_before" "index preserved"
     assert_eq "$page_after" "$page_before" "page preserved"
     assert_grep "$stats" '^threads_state: unreadable$' "read failure disclosed"
     assert_eq "$warning_banners" 1 "operator warned"

     # test_threads_concurrent_merges_preserve_cli_close
     assert_eq "$status_after_linker" closed_by_sam "concurrent close survives"
     assert_eq "$both_runs_links_present" true "fresh state reread before merge"

     # test_threads_lock_exhaustion_is_bounded
     assert_grep "$stats" '^threads_skipped: locked$' "nightly skips"
     assert_eq "$cli_exit" 1 "CLI fails loudly"

     # test_threads_retriaged_goal_replaces_source_link
     assert_eq "$source_memberships" 1 "source key is replaced, not appended"
     assert_eq "$new_goal" "revised goal" "fresh triage participates"

     # test_threads_older_rebuild_only_links_missing_sources
     assert_eq "$already_linked_calls" 0 "older rebuild is idempotent"
     assert_eq "$newer_last_seen" "$before_last_seen" "history does not regress"

     # test_threads_linker_cannot_write
     assert_no_file "$attempted_write" "linker has no writable tools"
     assert_eq "$accepted_links" 1 "valid stdout still reaches merge"
     ```

     Table-drive failure modes: absent engine, refusal, nonzero exit, timeout, and successful exit with unusable output. Table-drive rejected assignments: malformed JSON, unknown thread ID, unknown candidate handle, invalid `finished`, and duplicate/conflicting assignment.

     Eligible fixtures must use a read-only existing checkout cwd, such as `$REPO`, rather than the existing `/tmp/proj-a` fixture. Worktree fixtures use an isolated `/var/tmp/adt.XXXXXX` checkout with cleanup, separate from `$TMPDIR`.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Expected: new thread counters, calls, and index assertions fail because `run.sh` does not yet invoke the updater.

   - [ ] **Implement trusted input capture and catch-up.**
     - Extend the `SESSION_ROWS` approach without changing its existing TSV contract.
     - Capture session path, adapter, cwd, canonical repo hint, nesting, and measured user count in runner memory before L1.
     - Resolve archive paths through accepted adapters/session roots and runner-computed hashes. Never recover authoritative paths from findings JSON, `sessions.txt` after L1, or `rollup.tsv`.
     - Read historical eligibility from stats sidecars directly. Do not require `rollup.tsv`.
     - Eligibility is top-level, at least two user messages, and cwd outside `$TMPDIR`, `/tmp`, `/private/tmp`, and any directory component named `scratchpad`. Apply exclusions before converting a worktree to its main repo.
     - Missing/unusable required sidecar measurements increment `threads_unmeasured`.
     - Resolve worktrees through Git common-directory metadata. An unresolved repo remains an empty hint.
     - Read only `underlying_goal`, fallback `notable_initiatives`, and `outcome` from accepted findings. Exclude error/gated records without substantive facets.
     - Nightly catch-up covers the inclusive 14-day window ending at `TARGET_DATE`, selecting missing `(date, hash)` keys. Include successfully re-triaged existing keys as replacements.
     - Process candidates in stable chronological order. Ordinary older rebuilds leave existing memberships alone.

   - [ ] **Implement request building and merging.**
     - Defaults:
       - `AUTODREAM_THREADS_ENGINE=claude`
       - `AUTODREAM_THREADS_MODEL=claude-haiku-5-5`
       - `AUTODREAM_THREADS_TIMEOUT=300`
       - `AUTODREAM_THREADS_MAX_INPUT=65536`
     - Validate positive integer knobs with decimal handling.
     - Sizing evidence: November 13 yielded 25 candidates and 5,187 compact JSON bytes before cwd exclusions, with empty thread context. Using archived bucket lengths as a sizing proxy gave 5,447 bytes. Pin 65,536 as the initial ceiling; record actual complete request bytes during validation.
     - Supply open threads from the last 90 days with `id,title,repo,goal,last_seen`; supply closed thread hints as `id,title,repo`.
     - Make one call across all repos below the ceiling. Above it, split by canonical repo hint, retaining empty-repo candidates together. Never split by storage bucket.
     - Measure the complete serialized request. An unsplittable oversized request is a disclosed failure, with its candidates left pending.
     - Use the L1 timeout executable and process-group behavior: `timeout -k 30 300`. If no supported timeout exists, skip the linker as failed rather than run it unbounded.
     - A failed call publishes none of that call’s assignments.
     - Validate successful stdout one JSONL assignment at a time. Unknown or malformed assignments increment `threads_rejected`; valid siblings continue.
     - Assign collision-checked `t-<8 hex>` IDs in runner code. Strip controls from titles and cap them at 120 characters.
     - Take the lock only after model execution. Re-read state and merge against current statuses.
     - Preserve `closed_by_sam`, including when the CLI closed a target while the model was running.
     - Auto-close only when `finished == true` and the relevant newest outcome is `fully_achieved` or `mostly_achieved`.
     - Keep `last_seen` at the maximum linked date. Older input cannot replace the goal or closure judgment of newer work.
     - Stage the complete index beside its destination and rename once.

   - [ ] **Run green.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Also rerun the two real-CLI tool probes from Task 1.1. Record mutation evidence for dropping provenance protection, broadening the lock around the model call, and removing sticky-close handling.

   - [ ] **Commit.**

     ```bash
     git add bin/run.sh bin/threads.sh prompts/THREAD_LINKER.md tests/run-all.sh tests/mock-claude.sh
     git commit -m "feat: link eligible sessions into persistent threads"
     ```

4. **Task 1.4: Add report output, resume/backfill, installation, and PR 1 documentation.**

   **Files**
   - Modify: `bin/run.sh`
   - Modify: `bin/threads.sh`
   - Modify: `prompts/PROMPT.md`
   - Modify: `install.sh`
   - Modify/test: `tests/run-all.sh`
   - Modify/test: `tests/mock-claude.sh`
   - Modify: `README.md`
   - Modify: `example/config.example`
   - Modify: `CLAUDE.md`
   - Modify: `codemaps/architecture.md`

   **Interfaces**
   - `threads.sh report DATE` writes the deterministic report section to stdout.
   - Named L2 input: `findings/<date>/dropped-threads.md`.
   - `threads.sh resume ID [--launch]`.
   - `threads.sh backfill FROM TO [--engine E] [--model M] [--max-calls N]`.
   - Proposed functions:
     - `threads_report DATE`
     - `threads_resume ID LAUNCH`
     - `threads_backfill FROM TO ENGINE MODEL MAX_CALLS`
   - `backfill` reports `planned_calls`, `max_calls`, and final `actual_calls`.

   **Parallelism:** Serial after Task 1.3; shares runner, CLI, and test files.

   - [ ] **Write failing tests.**

     ```bash
     # test_threads_empty_night_still_catches_up_and_reports
     assert_eq "$prior_pending_links" 0 "catch-up runs on early-return path"
     assert_grep "$report" '^## Dropped threads$' "stub includes current index"
     assert_eq "$l2_calls" 0 "empty-night path still avoids L2"

     # test_threads_report_ranking_and_limit
     assert_eq "$recommendation_rows" 5 "report cap"
     assert_eq "$first_id" "$newly_dropped_id" "new crossings rank first"
     assert_eq "$reserved_idea_rows" 2 "ideas receive reserved slots"

     # test_threads_auto_closed_threads_are_visible_and_reopenable
     assert_grep "$report" "$auto_closed_id" "closed tonight is visible"
     assert_eq "$reopened_status" open "operator can correct false done"

     # test_threads_resume_quotes_injected_goal
     assert_eq "$launched_permission_mode" default "normal permission mode"
     assert_eq "$launch_cwd" "$canonical_repo" "launch starts in repo"
     assert_eq "$attack_is_inside_data_fence" true "goal is quoted as data"
     assert_eq "$contains_evidence_excerpt" false "findings prose excluded"

     # test_threads_resume_marks_missing_transcript
     assert_grep "$brief" "transcript missing" "deleted transcript is named, not offered as a path to Read"
     assert_grep "$brief" "$surviving_path" "surviving transcript still listed"

     # test_threads_backfill_uses_sidecars_and_respects_budget
     assert_eq "$requires_rollup" false "pre-November archive is supported"
     assert_eq "$first_processed_date" "$from" "oldest first"
     assert_eq "$calls" 2 "budget is enforced"
     assert_eq "$plan_printed_before_first_call" true "count precedes work"
     assert_grep "$output" "$date_without_sidecars" "skipped date is named"

     # test_threads_install_links_entrypoint
     assert_eq "$installed_cli_works" true "installed symlink resolves helpers"
     ```

     Extend the mock L2 path to copy `dropped-threads.md` into its report. Separately assert the production prompt’s named-file and verbatim-copy contract.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Expected: missing section, missing CLI verbs, and missing install link.

   - [ ] **Implement report integration.**
     - On the normal path, run thread updating after L1 and the existing `write_rollup` call, before L2. Append thread counters after the main run-stats block has been written.
     - On the zero-session path, run catch-up and write the deterministic section before writing the stub report and returning.
     - Build the early report with the same `threads_report` output used for L2.
     - Add the exact `dropped-threads.md` path to `PROMPT.md`’s named inputs and startup instructions.
     - Add `## Dropped threads`: copy runner output verbatim, preserving stale-index warnings and every “closed tonight” entry. Do not turn suggestions into open questions.
     - Limit dropped recommendations to five. Reserve up to two slots for ideas; unused reserved slots return to work.
     - Rank newly crossed threads since the most recent prior complete report first, then linked-session count, with stable ID tie-breaking. Derive this from report dates; add no watermark.
     - List every auto-closed thread separately from the five dropped recommendations.

   - [ ] **Implement resume and backfill.**
     - Resume prints a brief by default.
     - Include runner facts, dates, outcomes, repo, and transcript paths. Put title and goal inside a fence labelled as transcript data; choose a fence that embedded text cannot terminate.
     - Direct the new session to Read source transcripts. Exclude findings prose and `evidence_excerpt`.
     - `--launch` uses `--permission-mode default`, cwd equal to a usable repo or `$HOME`, and a concrete initial instruction.
     - Backfill reuses collection, request building, validation, and merge functions. It reads sidecars without depending on rollups.
     - Preflight the date/repo batches and print the planned call count and budget before invoking an engine. Count every invocation, including failed calls, against the budget. Disclose any additional split required by current context size.
     - Name skipped dates; leave rejected or unprocessed inputs available for later catch-up.
     - Link `bin/threads.sh` into `$AUTODREAM_DIR` in `install.sh`.
     - Document defaults, formats, failure counters, and the lack of a watermark. Register `tests/threads-state.sh` in the existing unit-suite list.

   - [ ] **Run green and validate PR 1.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     TMPDIR=/tmp /bin/bash tests/install-path.sh
     TMPDIR=/tmp /bin/bash tests/install-dry-run.sh
     git diff --check
     ```

     Run on macOS with `/bin/bash` and through existing Linux CI. Complete the repo-required independent review before merge.

   - [ ] **Commit.**

     ```bash
     git add bin/run.sh bin/threads.sh prompts/PROMPT.md install.sh tests/run-all.sh tests/mock-claude.sh README.md example/config.example CLAUDE.md codemaps/architecture.md
     git commit -m "feat: report and resume dropped threads with bounded backfill"
     ```

   - [ ] **After PR 1 merges, run the approved historical backfill.** Resolve the exact local DeepSeek model from OMP’s current model registry, then run:

     ```bash
     . bin/portable.sh
     TO=$(pdate_yesterday)
     ~/.claude/autodream/threads.sh backfill 2026-07-17 "$TO" --engine omp --model "$LOCAL_DEEPSEEK_MODEL" --max-calls 120
     ```

     Verify the call summary, skipped dates, index validity, and CLI output before starting PR 2. This uses archived facets and makes no L1 re-triage calls.

## PR 2: Static dashboard and explore session

1. **Task 2.1: Render and publish the hardened local dashboard.**

   **Files**
   - Create: `bin/threads-render.py`
   - Create: `templates/threads.html`
   - Modify: `bin/threads.sh`
   - Modify: `bin/run.sh`
   - Modify: `install.sh`
   - Modify/test: `tests/run-all.sh`

   **Interfaces**
   - `threads.sh render`.
   - `threads-render.py STATE OUTPUT --as-of DATE`.
   - Output: `$DREAMS_DIR/threads.html`.
   - Embedded JSON: generation time, as-of date, thread records, and computed display status.
   - Counter: `threads_render: ok|failed|skipped_unreadable`.

   **Parallelism:** Serial after PR 1. Task 2.2 also modifies `bin/threads.sh` and `tests/run-all.sh`.

   - [ ] **Write failing tests.**

     ```bash
     # test_threads_render_failure_preserves_previous_page
     assert_eq "$html_after" "$html_before" "failed render preserves page"
     assert_grep "$stats" '^threads_render: failed$' "failure disclosed"

     # test_threads_html_payload_is_inert
     assert_eq "$decoded_goal" "$hostile_goal" "text survives encoding"
     assert_eq "$raw_json_less_than_count" 0 "script terminators escaped"
     assert_eq "$unexpected_html_nodes" 0 "payload creates no HTML elements"
     assert_eq "$unsafe_dom_sinks" 0 "dynamic text uses textContent"
     assert_eq "$invalid_id_commands" 0 "copy commands require valid IDs"

     # test_threads_render_runs_on_empty_night_and_cli_write
     assert_eq "$empty_night_page_exists" true "early path renders"
     assert_eq "$page_closed_status" closed_by_sam "CLI write refreshes page"
     assert_eq "$generation_time_present" true "page shows its age"
     ```

     Feed `</script>`, HTML event attributes, quotes, control characters, and shell metacharacters through the real renderer. Use Python’s stdlib HTML parser to inspect the resulting document. Treat the fixed script’s `textContent`-only rule as a security contract.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Expected: dashboard is absent, render status is missing, and hostile-input assertions fail.

   - [ ] **Implement rendering and hooks.**
     - Use Python stdlib JSON encoding; replace every `<` in embedded JSON with the literal escape `\u003c`.
     - Embed data only in a `type="application/json"` script element.
     - Populate dynamic content using `textContent`; prohibit dynamic HTML sinks.
     - Emit exactly this CSP:

       ```text
       default-src 'none'; script-src 'self' 'unsafe-inline';
       style-src 'unsafe-inline'; connect-src 'none'
       ```

     - Implement search, repo selection, and Dropped/Open/Ideas/Done views.
     - Build copy commands only from IDs matching `^t-[0-9a-f]{8}$`. Keep transcript text and repo values out of executable command construction.
     - Show generation time visibly.
     - Write a temporary page beside the destination and rename only after successful rendering. Refuse to render unreadable state.
     - Render at the end of both nightly paths and after successful CLI state writes, outside the state lock.
     - Install the renderer and template through the existing symlink mechanism.

   - [ ] **Run green.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     TMPDIR=/tmp /bin/bash tests/install-dry-run.sh
     git diff --check
     ```

     Open the hostile fixture in a real browser before merge. Verify filters and copy controls, literal display of the payload, and absence of executed payloads or network requests.

   - [ ] **Commit.**

     ```bash
     git add bin/threads-render.py templates/threads.html bin/threads.sh bin/run.sh install.sh tests/run-all.sh
     git commit -m "feat: render a hardened local thread dashboard"
     ```

2. **Task 2.2: Launch the constrained explore session.**

   **Files**
   - Modify: `bin/threads.sh`
   - Modify/test: `tests/run-all.sh`
   - Modify: `README.md`
   - Modify: `CLAUDE.md`
   - Modify: `codemaps/architecture.md`

   **Interfaces**
   - `threads.sh explore`.
   - Proposed function: `threads_explore`.
   - cmux operation: `new-split right --command COMMAND`.
   - Claude tools: Read and Bash, with the automatic Bash permission scoped to the installed `threads.sh` command.
   - Interactive launch uses `--permission-mode default`.

   **Parallelism:** Serial after Task 2.1 because both tasks modify CLI and integration tests.

   - [ ] **Write failing tests.** Use shimmed `open`, cmux, and Claude binaries.

     ```bash
     # test_threads_explore_launch_is_constrained
     assert_eq "$opened_path" "$dreams/threads.html" "opens local dashboard"
     assert_eq "$cmux_operation" new-split "opens a split"
     assert_eq "$permission_mode" default "normal permission mode"
     assert_eq "$tools" "Read,Bash" "explorer toolset"
     assert_eq "$bash_permission" "$installed_threads_permission" "CLI scope"
     assert_eq "$inlined_index_or_report" false "prompt points to files"
     assert_eq "$prompt_is_one_word" false "launch carries explicit intent"

     # test_threads_explore_quotes_paths_and_reports_launch_failure
     assert_eq "$injection_marker_exists" false "shell values remain literal"
     assert_eq "$failed_cmux_exit" 1 "failed launch is visible"
     ```

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Expected: `explore` is unsupported and no constrained launch is captured.

   - [ ] **Implement `threads_explore`.**
     - Render first; refuse to open a knowingly unreadable index.
     - Open the local HTML file and launch Claude using cmux’s inspected `new-split` operation.
     - Copy `review.sh`’s executable resolution and `%q` shell quoting pattern.
     - Copy its prompt rules: reference the index/dashboard paths, inline only the narrow briefing, and provide a substantive initial instruction.
     - Restrict the declared tools to Read and Bash. Scope automatically permitted Bash calls to the installed thread CLI; other requests retain ordinary approval.
     - Pass neither `bypassPermissions` nor equivalent permission-skipping flags.
     - Keep title/goal text inside labelled data fences when quoting individual threads.
     - Fail visibly when cmux cannot create the split.

   - [ ] **Run green.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     TMPDIR=/tmp /bin/bash tests/review-prompt.sh
     TMPDIR=/tmp /bin/bash tests/review-cmux.sh
     git diff --check
     ```

     Complete a real cmux smoke launch and the required independent review before merging PR 2.

   - [ ] **Commit.**

     ```bash
     git add bin/threads.sh tests/run-all.sh README.md CLAUDE.md codemaps/architecture.md
     git commit -m "feat: explore threads in a constrained cmux session"
     ```

## PR 3: Explicitly deferred ideas from L1

1. **Task 3.1: Extend L1 output and preserve ideas across chunk merging.**

   **Files**
   - Modify: `prompts/SESSION_TRIAGE.md`
   - Modify: `adapters/omp/triage.md`
   - Modify: `bin/merge-chunks.sh`
   - Modify/test: `tests/merge-chunks.sh`
   - Modify/test: `tests/mock-claude.sh`
   - Modify/test: `tests/run-all.sh`

   **Interfaces**
   - Optional L1 field:

     ```json
     {
       "deferred_ideas": [
         {"idea": "One-line description", "quote": "Verbatim user quote"}
       ]
     }
     ```

   - Maximum three entries.
   - Each quote is nonempty and **under 200 characters**, so at most 199.
   - Missing fields in historical findings mean an empty list.
   - Chunk rule: concatenate in chunk order, deduplicate, cap at three.

   **Parallelism:** Serial after PR 2; Task 3.2 shares the mock and integration tests.

   - [ ] **Write failing tests.**

     ```bash
     # test_merge_chunks_preserves_deferred_ideas
     assert_eq "$merged_idea_count" 3 "union is capped at three"
     assert_eq "$merged_quotes" "quote-a|quote-b|quote-c" "stable deduplication"
     assert_eq "$missing_or_mistyped_field_count" 0 "optional bad field ignored"

     # test_threads_chunked_triage_keeps_deferred_ideas
     assert_eq "$accepted_quotes" "quote-a|quote-b|quote-c" "real runner merge"
     assert_eq "$idea_from_later_chunk_present" true "later chunks contribute"

     # test_l1_deferred_ideas_require_explicit_deferral
     assert_eq "$prompt_requires_user_quote" true "verbatim evidence required"
     assert_eq "$prompt_allows_inference" false "empty beats inferred ideas"
     ```

     Include duplicate entries across chunks, invalid entry types, a missing field in chunk one, and an overlong quote. The integration test must exercise actual chunked `run.sh`, not only the merge helper.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/merge-chunks.sh
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Expected: the current merger retains only the first chunk’s extra field or loses later ideas, violating the explicit union rule.

   - [ ] **Implement schema and merge behavior.**
     - Tell L1 to emit only ideas the user raised and explicitly deferred.
     - Require a verbatim quote under 200 characters; emit `[]` when none qualifies.
     - Keep the OMP addendum consistent with the common field.
     - Add an explicit `deferred_ideas` merge expression alongside `notable_initiatives` and `instructions_given`.
     - Normalize malformed optional fields to empty arrays, retain valid entries, concatenate in chunk order, deduplicate, and cap at three.
     - Preserve the existing `--check` findings contract and refusal to merge around failed chunks.

   - [ ] **Run green.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/merge-chunks.sh
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     git diff --check
     ```

     Record the caught mutation: removing the explicit merge rule must lose an idea supplied only by a later chunk.

   - [ ] **Commit.**

     ```bash
     git add prompts/SESSION_TRIAGE.md adapters/omp/triage.md bin/merge-chunks.sh tests/merge-chunks.sh tests/mock-claude.sh tests/run-all.sh
     git commit -m "feat: capture explicitly deferred ideas in session triage"
     ```

2. **Task 3.2: Link separate idea candidates and document historical recovery.**

   **Files**
   - Modify: `bin/threads.sh`
   - Modify: `prompts/THREAD_LINKER.md`
   - Modify/test: `tests/run-all.sh`
   - Modify/test: `tests/mock-claude.sh`
   - Modify: `README.md`
   - Modify: `CLAUDE.md`
   - Modify: `codemaps/architecture.md`

   **Interfaces**
   - Each accepted deferred idea becomes a `kind: idea` candidate.
   - Extend request-local candidate handles with an idea discriminator derived by runner code from the validated quote.
   - Maintain source references as the original `(date, hash, session_path, outcome)`.
   - Work and idea candidates from one source must remain distinguishable through validation, retries, and membership replacement.
   - Reuse the existing updater, statuses, report ranking, and dashboard renderer.

   **Parallelism:** Serial after Task 3.1 because mock and integration-test files overlap.

   - [ ] **Write failing tests.**

     ```bash
     # test_threads_deferred_ideas_are_independent_candidates
     assert_eq "$work_threads" 1 "source still contributes its work goal"
     assert_eq "$idea_threads" 3 "three deferred ideas remain distinct"
     assert_eq "$total_linker_calls" 1 "ideas share the nightly request"

     # test_threads_idea_retry_does_not_lose_rejected_sibling
     assert_eq "$valid_idea_duplicates" 0 "accepted idea is idempotent"
     assert_eq "$rejected_idea_eventually_linked" true "sibling remains pending"

     # test_threads_closed_idea_stays_closed
     assert_eq "$closed_idea_status" closed_by_sam "closure is sticky"
     assert_eq "$reworded_duplicate_threads" 0 "rewording attaches to closure"

     # test_threads_idea_slots_are_reserved
     assert_eq "$report_rows" 5 "recommendation limit remains five"
     assert_eq "$idea_rows" 2 "ideas survive a larger work backlog"

     # test_threads_backfill_does_not_retriage_ideas
     assert_eq "$l1_calls" 0 "ordinary backfill reads existing facets only"
     assert_eq "$old_missing_field_errors" 0 "historical findings remain valid"
     ```

     Pin the candidate-identity behavior before implementation. A work link must not make the updater consider all ideas from that source processed.

   - [ ] **Run red.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     ```

     Expected: idea candidates are absent, or shared source identity incorrectly suppresses siblings.

   - [ ] **Implement idea ingestion.**
     - Validate the optional array and quote bounds independently of core findings.
     - Create independent runner-owned handles for work and each idea. The model may only return handles it received.
     - Preserve accepted siblings across retries and leave rejected candidates pending.
     - Ensure re-triage replaces source membership without duplicating existing ideas.
     - Keep candidate bookkeeping within the index’s atomic update; introduce neither a date watermark nor a separately committed progress file.
     - Link ideas through the same engine call and merge path as work.
     - Preserve sticky operator closures and the existing five-slot/two-idea ranking.
     - Keep normal backfill free of L1 calls.

   - [ ] **Document the separate historical-ideas run.**
     - Explain that pre-PR-3 ideas require re-triaging transcripts.
     - Define a small, isolated sample run first.
     - Measure actual L1/chunk calls, elapsed time, and available cost telemetry from that sample.
     - Quote the estimated full-run cost and scope to Sam **before** starting the full re-triage.
     - Keep this opt-in operation separate from the already approved facet-only backfill.

   - [ ] **Run green and validate PR 3.**

     ```bash
     TMPDIR=/tmp /bin/bash tests/run-parallel.sh 4
     TMPDIR=/tmp /bin/bash tests/merge-chunks.sh
     git diff --check
     ```

     Complete macOS Bash 3.2 validation, Linux CI, and the required independent review before merge.

   - [ ] **Commit.**

     ```bash
     git add bin/threads.sh prompts/THREAD_LINKER.md tests/run-all.sh tests/mock-claude.sh README.md CLAUDE.md codemaps/architecture.md
     git commit -m "feat: link deferred ideas as independent threads"
     ```

## Failure-matrix coverage

Every listed E2E test belongs in `tests/run-all.sh` and is registered with `_run test_name`.

| Spec failure-matrix row | Named E2E test | Task |
|---|---|---|
| Nothing triaged tonight; early return | `test_threads_empty_night_still_catches_up_and_reports`; `test_threads_render_runs_on_empty_night_and_cli_write` | 1.4, 2.1 |
| No eligible sessions tonight | `test_threads_no_eligible_sessions_makes_no_call` | 1.3 |
| Engine down, refusing, or timed out | `test_threads_linker_failures_preserve_state_and_catch_up` | 1.3 |
| Malformed assignment, unknown ID, or unknown hash | `test_threads_rejects_assignments_individually` | 1.3 |
| Finished judgment without achieved outcome | `test_threads_finished_requires_achieved_outcome` | 1.3 |
| Wrong auto-close must be visible and correctable | `test_threads_auto_closed_threads_are_visible_and_reopenable` | 1.4 |
| Existing index cannot be read | `test_threads_unreadable_index_prevents_write_and_render` | 1.3 |
| Concurrent runs or CLI write; lock exhaustion | `test_threads_concurrent_merges_preserve_cli_close`; `test_threads_lock_exhaustion_is_bounded` | 1.3 |
| Re-triaged session has a new goal | `test_threads_retriaged_goal_replaces_source_link` | 1.3 |
| Rebuild of an older date | `test_threads_older_rebuild_only_links_missing_sources` | 1.3 |
| Worker forges worklist, project, and session path | `test_threads_runner_provenance_survives_worker_tampering` | 1.3 |
| Linker attempts a filesystem write | `test_threads_linker_cannot_write`, plus both real-CLI probes | 1.3, 1.1 |
| Session sidecar missing | `test_threads_missing_sidecar_is_unmeasured` | 1.3 |
| Dashboard rendering fails | `test_threads_render_failure_preserves_previous_page` | 2.1 |
| Thread text contains HTML or `</script>` | `test_threads_html_payload_is_inert` | 2.1 |
| Linked transcript no longer exists | `test_threads_resume_marks_missing_transcript` | 1.4 |
| Resume goal contains instructions | `test_threads_resume_quotes_injected_goal`; `test_threads_explore_launch_is_constrained` | 1.4, 2.2 |