# 0001: The runner: lifecycle, guards, locks and config

Status: accepted · Governs: `bin/autodream-note.sh`, `bin/lib-install-dir.sh`, `bin/preflight.sh`, `bin/run.sh`, `bin/report-format.sh`, `err-cause.sh`, `portable.sh`, `bin/autodream-now.sh`

This record holds 37 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Where state lives](#background-where-state-lives)
- [Background: Sleep resilience](#background-sleep-resilience)
- [Background: The logger could kill the run, and did (2026-08-02)](#background-the-logger-could-kill-the-run-and-did-2026-08-02)
- [Background: run.sh sources the config now](#background-runsh-sources-the-config-now)
- [Background: Nobody was told (`unassembled_dates`)](#background-nobody-was-told-unassembled_dates)
- [Background: Which code actually ran (`runner_commit`)](#background-which-code-actually-ran-runner_commit)
- [Background: One repo, no sibling to drift from](#background-one-repo-no-sibling-to-drift-from)
- [autodream-note.sh resolves its install dir like the reader of the notes file does](#autodream-notesh-resolves-its-install-dir-like-the-reader-of-the-notes-file-does)
- [one resolver decides the install dir, from the script's unresolved path](#one-resolver-decides-the-install-dir-from-the-scripts-unresolved-path)
- [preflight stops hard on missing `jq`, `shasum`, `realpath` and the L2 engine, and only warns about `python3`](#preflight-stops-hard-on-missing-jq-shasum-realpath-and-the-l2-engine-and-only-warns-about-python3)
- [every expansion of a possibly-empty array is guarded for bash 3.2 under `set -u`](#every-expansion-of-a-possibly-empty-array-is-guarded-for-bash-32-under-set--u)
- [the enabled-adapter list is resolved once into a global by a function that prints nothing](#the-enabled-adapter-list-is-resolved-once-into-a-global-by-a-function-that-prints-nothing)
- [every FATAL funnels through log_fatal and fatal_exit, which leave a marker AND post a banner, never a stub report](#every-fatal-funnels-through-log_fatal-and-fatal_exit-which-leave-a-marker-and-post-a-banner-never-a-stub-report)
- [Findings JSONs outside this run's worklist are set aside, not deleted](#findings-jsons-outside-this-runs-worklist-are-set-aside-not-deleted)
- [a report is complete when it carries the end marker, never merely when its path is non-empty](#a-report-is-complete-when-it-carries-the-end-marker-never-merely-when-its-path-is-non-empty)
- [a helper's `AUTODREAM_*_BIN` override is authoritative, with no existability fallback](#a-helpers-autodream__bin-override-is-authoritative-with-no-existability-fallback)
- [helpers and libraries are found through `find_lib` (script dir, then the runner's real bin dir), not SCRIPT_DIR alone](#helpers-and-libraries-are-found-through-find_lib-script-dir-then-the-runners-real-bin-dir-not-script_dir-alone)
- [a finished report makes later triggers cheap no-ops (the idempotency guard)](#a-finished-report-makes-later-triggers-cheap-no-ops-the-idempotency-guard)
- [A finished report needs the open-questions marker, not just a non-empty file](#a-finished-report-needs-the-open-questions-marker-not-just-a-non-empty-file)
- [The per-run L1 ledgers are truncated past the idempotency guard](#the-per-run-l1-ledgers-are-truncated-past-the-idempotency-guard)
- [numeric env knobs are refused or normalised at startup, never discovered at 03:15](#numeric-env-knobs-are-refused-or-normalised-at-startup-never-discovered-at-0315)
- [An orphaned .err is counted and named, never retried](#an-orphaned-err-is-counted-and-named-never-retried)
- [run.sh appends its extra directories to the caller's PATH instead of replacing it](#runsh-appends-its-extra-directories-to-the-callers-path-instead-of-replacing-it)
- [One run per date at a time, through an flock held by a holder process](#one-run-per-date-at-a-time-through-an-flock-held-by-a-holder-process)
- [Preflight runs below the idempotency guard, above enumeration, through bash, and owns the dependency checks](#preflight-runs-below-the-idempotency-guard-above-enumeration-through-bash-and-owns-the-dependency-checks)
- [PROJECTS_DIR's default is applied at startup and whether the caller set it is recorded separately](#projects_dirs-default-is-applied-at-startup-and-whether-the-caller-set-it-is-recorded-separately)
- [how a run ended is written to a per-token outcome file, and nothing else tells the watcher](#how-a-run-ended-is-written-to-a-per-token-outcome-file-and-nothing-else-tells-the-watcher)
- [run.sh sources the config in a nounset-off, `set -a` block and replays the caller's exported environment](#runsh-sources-the-config-in-a-nounset-off-set--a-block-and-replays-the-callers-exported-environment)
- [sweeps that need only files on disk run above the idempotency guard, so a catch-up trigger that no-ops for today still does them](#sweeps-that-need-only-files-on-disk-run-above-the-idempotency-guard-so-a-catch-up-trigger-that-no-ops-for-today-still-does-them)
- [the runner's symlink walk is capped at 8 hops](#the-runners-symlink-walk-is-capped-at-8-hops)
- [every write and read of the session worklist and its provenance index fails closed](#every-write-and-read-of-the-session-worklist-and-its-provenance-index-fails-closed)
- [a sleeping laptop is survived by re-dispatching missing sessions across wake cycles and retrying L2](#a-sleeping-laptop-is-survived-by-re-dispatching-missing-sessions-across-wake-cycles-and-retrying-l2)
- [in-place list rewrites go through two helpers that replace the file atomically and account for every failure](#in-place-list-rewrites-go-through-two-helpers-that-replace-the-file-atomically-and-account-for-every-failure)
- [an existing dream is moved aside before L2, and a failed move disarms consuming](#an-existing-dream-is-moved-aside-before-l2-and-a-failed-move-disarms-consuming)
- [the run names dates whose findings were never assembled into a complete report, judging completeness by the open-questions marker with a dated exemption for legacy reports (#36)](#the-run-names-dates-whose-findings-were-never-assembled-into-a-complete-report-judging-completeness-by-the-open-questions-marker-with-a-dated-exemption-for-legacy-reports-36)
- [an unattended run logs to a file, and SIGPIPE is ignored on the interactive path](#an-unattended-run-logs-to-a-file-and-sigpipe-is-ignored-on-the-interactive-path)
- [A night with nothing to triage still cleans up, reconciles, and writes the full run-stats key set](#a-night-with-nothing-to-triage-still-cleans-up-reconciles-and-writes-the-full-run-stats-key-set)

## Background: Where state lives

This section was moved here from the former CLAUDE.md. Its original title: "Where state lives".

All under `$AUTODREAM_DIR` (default `~/.claude/autodream/`) except the reports:

- `findings/YYYY-MM-DD/*.json` — Layer 1 output, one per session (keyed by a 12-char sha1 of the session path). `*.json.err` is a worker's stderr on failure.
- `findings/YYYY-MM-DD/sessions.txt` (+ `.raw`) — the enumerated session list (`.raw` is pre-self-filter).
- `findings/YYYY-MM-DD/changelog-window.md` — upstream changelog diff for the date (see below).
- `findings/YYYY-MM-DD/run-stats.txt` — self-audit telemetry the aggregator reads.
- `findings/YYYY-MM-DD/.chunks/<hash>/` — chunked triage scratch for a session still pending: `in/` (chunk inputs, removed every round), `NN-<sha>-<cfg>.chunkout` (finished chunk answers, kept for the retry) and `NN.err`/`NN.out` (a failed chunk's evidence). Removed when the session has a findings JSON. `l1-chunks.txt` and `l1-chunk-calls.txt` are the per-run ledgers behind the chunk counters.
- `findings/YYYY-MM-DD/operator-notes.md` — every capture surface's notes merged into the one file L2 reads. `vault-notes-manifest.txt` alongside it lists the inbox files that went into it.
- `findings/YYYY-MM-DD/x-bookmarks.md` — unread X bookmarks for the "Ideas from bookmarks" section, plus `x-bookmarks-manifest.txt` of their ids. `x-bookmarks/seen.jsonl` holds the persistent read state.
- `findings/YYYY-MM-DD/report-index.txt` and `report-<name>.md` — the output of every command in `$AUTODREAM_DIR/report-scripts.conf`, run by `bin/report-scripts.sh collect` before L2 (see "Report scripts"). The index is always written, `none configured` included.
- `findings/YYYY-MM-DD/pins.jsonl` — Layer 2's proposed pins, one JSON object per line (`project`, `title`, `body`, `kind`). A file left by an earlier run or attempt is moved to a unique `pins.jsonl.stale-XXXXXX` (mktemp) before each L2 attempt.
- `findings/YYYY-MM-DD/fanouts.tsv` — `worker-hash<TAB>parent-hash` for every ungated nested transcript (a claude subagent or workflow worker, an omp advisor or task child), written after L1 so L2 can read it. Nested means a sidecar with `isSidechain` or `nested` set; the parent is found by walking up from the transcript until `<dir>.jsonl` is a file, which holds at every depth both harnesses nest to. `run-stats.txt` carries the counts (`sessions_top_level`, `sessions_nested`, `fanout_parents`, `largest_fanout`), and `bin/overlap-stats.sh` drops the same sidecars, because a worker overlaps its parent and its siblings by construction.
- `findings/YYYY-MM-DD/rollup.tsv`, `categories.tsv` and `findings.tsv` — what L2 counts from, written by `bin/rollup.sh` after L1 (after the skill-field pass and `compute_fanout_stats`). `rollup.tsv` has one row per session, gated ones included: `hash status project source nested is_advisor parent outcome user_message_count turn_count tool_call_count duration_minutes models_used findings skills_invoked_count skills_invoked_counts skills_authored instructions_given_count sandbox_shape_denies sandbox`, where `status` is `triaged`, `gated`, `error` or `unreadable` and every status but `gated` is compute_fanout_stats's N. `sandbox_shape_denies` comes from the claude sidecar (`session-stats.sh` counts `is_error` tool_results whose text opens with `sandbox-shape: `, bare or inside `<tool_use_error>`; anchored, because a Read of a doc that mentions the guard holds the same words mid-text) and is blank for omp; L2 lists rows at or over `AUTODREAM_SANDBOX_SHAPE_MIN` (default 10, handed over as run-stats `sandbox_shape_denies_min`) in the self-audit. It exists because #175 stopped L1 scoring the guard's denies as `sandbox_friction`. `sandbox` is `yes` for a skill-creator trigger eval (`claude -p` from `/private/var/folders/<x>/<y>/T/trig-<id>/repo`, 32 of 45 projects on 2026-11-17): the runner's session cwd (from `AUTODREAM_SESSION_ROWS`, the hash, bucket and cwd rows built before any model ran and handed to `rollup.sh` like the source map) must match `^/private/var/folders/.+/T/trig-[^/]+(/repo)?$`, and only a cwd that is unknown (`?`, the dir is deleted after the run) falls back to the runner's bucket for that session, which also covers a findings JSON that does not parse, matching `^-private-var-folders-.+-T-trig-[A-Za-z0-9_-]+$`. Both ends are anchored because an ordinary `/Users/x/T/trig-parser` checkout encodes to a key that contains `-T-trig-`. `categories.tsv` has `category severity sessions findings example_hashes sessions_real sessions_sandbox weighted`, where `sessions` is `sessions_real + sessions_sandbox` and `weighted` is `sessions_real + floor(sessions_sandbox / 4)`: L2 ranks by `weighted`, reads a whole category as sandbox-only from `sessions_real == 0` (never from the capped `example_hashes`; a narrower pattern from its own counted sessions' `sandbox` column), and never lets a sandbox-only pattern drive a pin, a rules proposal or an open question (Sam, 2026-11-18); run-stats carries `sandbox_sessions`, the ungated sandbox rows. Each category also has a row with `severity` `all`, whose `sessions` counts a session once across severities; an advisor's content findings count under its parent session and its tool-behavior findings (`sandbox_friction`, `tool_loop`, `missed_skill`) not at all, since L1 suppresses them for advisors. `findings.tsv` has `hash category severity what`, one row per finding, for patterns narrower than a category. `rollup.sh` runs under `pipefail`, so a failed stage exits 1 and publishes nothing rather than an empty tally. The `source` column comes from `AUTODREAM_SOURCE_MAP`, not `sessions-source.txt`, which an L1 worker can rewrite. They exist because L2's Glob and directory reads stop at 200 entries: on 2026-10-31 the dir held 2683 entries for 885 sessions and the report counted a 90-file sample. So PROMPT.md names every file L2 reads by exact path and never lets it list the dir, and a new side file L2 needs gets a named line there, not a glob. One `jq` per session (up to four when a file is malformed), so a malformed findings JSON or sidecar costs its row's cells (blank, never 0), not the table; about 3 seconds for 885 sessions. Watch awk: a hash like `0000000000e7` is a number to awk, so compare hashes as strings. `tests/rollup.sh` pins it against a 224-session fixture.
- `findings/YYYY-MM-DD/pin-projects.tsv` — `project<TAB>cwd` rows for every project in this run's worklist (`sessions.txt`), computed before the first L1 call and written after a complete report. The rows are held in the runner's memory in between, because L1 and L2 both run with the Write tool and could rewrite the worklist files. Project and cwd both come from the real session path, never from a findings JSON, whose `session_path` the L1 model writes. The project is the directory directly under the longest session root that holds the session, at any nesting depth below it. A cwd the adapter cannot resolve (a removed worktree), a cwd that does not encode to its dash bucket (slug buckets like `STRML-cc-autodream` skip that check), or a bucket with more than one distinct cwd, gets an empty column; `bin/apply-pins.sh` reads it to authorize and resolve each pin.
- `findings/YYYY-MM-DD/session-cwds.tsv` — `session-hash<TAB>cwd` rows copied from the runner's trusted `SESSION_ROWS` before it publishes a complete report. An unresolved cwd is `?`. The Lately view reads this per-session map to resolve worktree repos and merge Claude/OMP buckets; it does not trust the findings JSON's project field as a repo path. L1 and L2 cannot supply the map.
- `findings/YYYY-MM-DD/pins-applied.tsv` — the ledger of applied pins, `<sha1 of the resolved bank and the canonical pin><TAB><memory_id>`, so a rerun does not write the same pin twice. `run.sh` holds the ledger in memory before any model runs and puts it back before the pins are applied, because a worker with the Write tool could empty it.
- `threads.jsonl` — persistent dropped-thread index. `bin/threads.sh` links runner-owned session facts after `write_rollup`, renders `findings/<date>/dropped-threads.md`, and offers list/search/move/report/resume/explore/backfill (`close` and `reopen` are aliases of `move ID done` and `move ID open`). Status is derived at read time: an open work thread is dropped when its newest session is unfinished and both that session and the optional `kept_open` date (set by `move ID open`) are older than the cutoff; an idea is never dropped, so the nightly Dropped section lists work only. `move` writes each legacy session's own `kind` (one with neither kind nor candidate handle) before it changes the thread's, and the linker reads a session's kind before its thread's, so moving a thread between Open and Ideas does not change which sessions count as idea deferrals. The linker edits rows in place, so `kind` and `kept_open` survive it; catch-up has no watermark. The index write and operator status changes use the same destination-local temp plus one rename pattern as `question-streaks.sh`.
- Each eligible session contributes its work goal and up to three validated `deferred_ideas`. Idea candidates carry a runner-derived handle based on the source date/hash and a digest of the normalized (idea, quote) pair, while each session reference retains the original date/hash/path. Idea outcomes are always `not_achieved`. Work membership replacement uses the candidate handle across work and idea threads. Work candidates may attach to either kind; idea candidates attach only to idea threads.
- `threads-idea-offers.tsv` records the first offered idea handles for each (date, hash), one `date<TAB>hash<TAB>handle<TAB>idea-json<TAB>quote-json` row per idea. The last two columns are JSON strings preserving the original text, including controls and Unicode. The runner records all handles before calling the linker, under the state flock, with the same destination-local temp plus rename pattern. An unreadable or malformed ledger refuses linking like unreadable state. Catch-up and re-triage build idea candidates only from the ledger, so rejected or omitted siblings retry with their original payload while reworded ideas stay suppressed. A source with no ledger rows is seeded from indexed idea deferrals before collection, or contributes its first ideas when no indexed deferrals exist. Indexed idea sessions retain kind, goal and quote; legacy references fall back to the thread goal and an empty quote, with a stable source/thread-id handle when absent.
- Re-triage replaces only work candidates. Idea sources are never removed by refresh. Only work candidates with `fully_achieved` or `mostly_achieved` outcomes and `finished:true` can close threads, including idea threads (which keep kind `idea`). A work candidate whose (date, hash) already occurs among an idea thread's deferring sessions (idea kind or candidate handle, including legacy idea references without a handle) can attach but cannot close it. Refused completion, including any idea candidate's finished flag, is counted in `threads_close_refused`.
- A day split across linker calls can rarely create duplicate threads. `threads.sh move <id> done` resolves the duplicate.
- Each repo-hint group is validated independently. One failed group contributes no assignments, while valid groups publish in one locked read-validate-merge-rename. `threads_link` is `partial` when assignments were published and some groups failed, `failed` when nothing was published (including setup failures, lock contention, and no valid assignments), and `ok` when every group's assignments were published; `threads_groups_failed` counts failed groups. Candidates from failed groups remain unassigned for catch-up, and the report claims an updated index only for a published merge.
- Facet-only `threads.sh backfill` never re-triages old transcripts. Historical ideas require a separate, opt-in re-triage: measure an isolated small sample's L1/chunk calls, elapsed time and available cost first, then quote the full-run estimate and scope before starting it. Never fold that into ordinary backfill.
- `findings/YYYY-MM-DD/pins-result.txt` — pin application counters (`pins_total`, `pins_applied`, `pins_invalid`, and so on).
- `findings/YYYY-MM-DD/unindexed-roots.txt` — Claude folders (`~/.claude*/projects`) that exist but are not indexed, for the self-audit section. Written before the idempotency guard so a catch-up no-op still reports folders that appeared since setup.
- `findings/YYYY-MM-DD/triage-candidates.{md,tsv}` — touched GitHub repos whose untriaged open issues cleared `AUTODREAM_TRIAGE_MIN`, written by `bin/triage-candidates.sh` from the runner's own session rows (never a findings JSON). L2 only copies the `.md` into "Repos to triage"; the counting and the cooldown (`triage-suggested.tsv`) are the script's, and `tests/triage-candidates.sh` pins each row of its failure matrix. The `.tsv` has one row per repo with status `candidate`, `below`, `cooldown` or `skipped` and the reason.
- `findings/YYYY-MM-DD/worktree-prune.{md,tsv}` — what `bin/prune-worktrees.sh` removed, kept and skipped that night, one TSV row per worktree (`action<TAB>repo<TAB>branch<TAB>path<TAB>reason`). The step is opt-in through `AUTODREAM_PRUNE_ROOTS`; the proof rules and keep rules are in the script header and the README, and `tests/prune-worktrees.sh` pins each one. It deletes remote branches, so a new rule there needs a test that pins a KEEP before it needs one that pins a removal.
- `remote/<label>/projects/` and `remote/<label>/last-ok` — the mirror of a host named in `AUTODREAM_REMOTE_ROOTS` and the date of its last good sync (see "Remote hosts"). Never pruned: the mirror keeps transcripts the remote deleted.
- `root-choices.conf` — the per-folder index decision (`~/.claude-ds4/projects=index`), written by `bin/root-probe.sh` at install time. The primary `~/.claude/projects` is always indexed.
- `cache/claude-code/` — persistent clone of `anthropics/claude-code` for the changelog.
- `logs/run-YYYY-MM-DD.log` — full run log (run.sh tees here). `logs/launchd.{out,err}.log` — launchd's capture.
- `dreams/YYYY-MM-DD.md` (default `~/.claude/dreams/`) — the final report.

Scripts/prompts are symlinked into `~/.claude/autodream/` by `install.sh`, so editing the repo copy takes effect immediately. The installed launchd job is `com.samuelreed.autodream` (not the `com.user.*` example label).

`install.sh` also installs that scheduled job by default (unless `--no-schedule`): it generates the plist with auto-detected PATH/dirs and the label `bin/scheduler-label.sh` returns (see below), then `bootout`+`bootstrap`s it. `RunAtLoad` is false, so install *arms* the schedule without firing a run; the four morning triggers (03:15/06:15/09:15/12:15) match the example plist. It does not run `pmset` (sudo) — it only prints the `pmset repeat wake` recommendation. The `launchd/*.example` file is kept as a hand-editable fallback.

## Background: Sleep resilience

This section was moved here from the former CLAUDE.md. Its original title: "Sleep resilience".

The overnight failure mode: launchd fires at the scheduled time on a brief wake, the Mac sleeps in and out during the run, workers lose the network and fail (we saw 104/215 fail, L2 exit 1, no report).

launchd facts: `StartCalendarInterval` is anacron-like (runs once on the next wake if asleep at the trigger), NOT vanilla cron. But launchd does not WAKE the Mac (use `pmset repeat wake` for that), and it does nothing about sleep DURING a run.

run.sh handles it with:
- **L1 retry loop** (`dispatch_l1` + `l1_missing_count`): re-dispatches only the sessions still missing a findings JSON, up to `AUTODREAM_L1_ROUNDS` (5), calling `wait_for_network` between rounds. The worker is idempotent, so retries are cheap.
- **L2 retry loop**: retries the aggregator up to `AUTODREAM_L2_ATTEMPTS` (3) until `$REPORT_PATH` is non-empty.
- **Idempotency guard**: at the top of `run()`, if a finished report exists for the date it exits in a second (`AUTODREAM_FORCE=1` to rebuild). Finished means the open-questions marker is present (or the date predates `AUTODREAM_MARKER_EPOCH`); a marker-less report is moved aside and rebuilt (#111). This is what makes multiple launchd catch-up triggers safe.
- **Per-date run lock** (#55, #242): `run()` takes the lock for the date before touching the findings dir, because launchd serialises a label only against itself and `autodream-now.sh` uses another. A live holder makes the second run log and exit 0. An flock(2) on `$AUTODREAM_DIR/locks/run-<date>.flock` is the lock, held by a small python holder process, so the kernel drops it when the holder ends and nothing judges a holder dead; the directory `run-<date>.lock` only reports the owner's pid and start time to the dashboard (see "One run per date at a time, through an flock held by a holder process"). `question-streaks.sh` and `threads.sh` take their own flock through `bin/lib-flock.sh` (see "Open questions that never get answered").
- The plist example schedules several morning triggers (03:15/06:15/09:15/12:15) so a failed-overnight date gets retried on later wakes; the guard no-ops the rest.

`net_up` checks reachability of `api.anthropic.com` (any HTTP code beats `000`). Disable the wait with `AUTODREAM_NETCHECK=0` (tests set this).

## Background: The logger could kill the run, and did (2026-08-02)

This section was moved here from the former CLAUDE.md. Its original title: "The logger could kill the run, and did (2026-08-02)".

Every recovery path above assumes it gets to run. `run 2>&1 | tee -a "$RUN_LOG"` quietly revoked that assumption for all of them at once: it made each log line a write to a pipe, so whatever killed `tee` killed the run by SIGPIPE on the next `log` call. Three runs died there on 2026-08-02 — two scheduled, one detached, so launchd was not the cause — and 2026-08-01 ended with no report at all. The signature is a run log that stops mid-sentence at `L2 aggregation attempt 1/3...` and a `Terminated: 15` on tee beside a `Broken pipe: 13` on run in the launchd stderr. Nothing else says anything, because the thing that would have said it is what died.

The fix is that an unattended run writes to the file directly (a file has no reader to lose) and `trap '' PIPE` covers the interactive path, where `tee` is still worth having. A closed terminal now costs the run its output rather than its life. `test_dead_stdout_does_not_kill_the_run` pins it by piping a real run into a reader that closes immediately.

What still has no root cause is who SIGTERMs `tee`. It was not `claude --print` signalling its process group (tested directly: a sibling `sleep` survives a worker call), it was not sleep (`pmset -g log` shows the Mac awake), and it was not launchd (the detached run died the same way). The run no longer cares, which is the point, but the signal source is worth naming if it ever shows up somewhere that does.

## Background: run.sh sources the config now

This section was moved here from the former CLAUDE.md. Its original title: "run.sh sources the config now".

It didn't until this feature; only `review.sh` did, which was fine while every key was review-only and stopped being fine the moment `AUTODREAM_VAULT_DIR` had to reach the nightly run. Two details in that block are load-bearing and both were caught by tests rather than by reading:

- **`set -a` around the source.** The helper scripts are separate processes, so a config key that stays an unexported shell variable reaches nothing. Without it the config parses fine and the feature silently does not happen.
- **The `export -p` snapshot replayed after.** The config uses plain `KEY=value`, so a bare `.` lets the file clobber a variable the caller deliberately exported. Tests set env; a run invoked with an explicit `AUTODREAM_VAULT_DIR=` to disable the vault has to actually disable it.

`AUTODREAM_DIR` is resolved before the source and therefore cannot be set from the config. That is not an oversight — it names the file's own location.

## Background: Nobody was told (`unassembled_dates`)

This section was moved here from the former CLAUDE.md. Its original title: "Nobody was told (`unassembled_dates`)".

A run killed during L2 leaves a complete findings dir and no report, and every surface that would have said so is downstream of the death: `notify.sh` never runs, so there is not even a quiet banner. The catch-up triggers cannot cover it either, because launchd will not start a second instance of a label that is already running — a run slow enough to span its own catch-up window converts those triggers into nothing at all. 2026-07-26 sat unassembled for two days and was found during an unrelated investigation; 2026-08-01 repeated it.

`unassembled_dates()` sweeps the trailing week at the top of `run()` — deliberately *above* the idempotency guard, so a catch-up trigger that no-ops for today still reports older abandoned dates. It lists dates holding findings JSONs (sidecar-only dirs were never triaged and are not failures) whose report is missing or marker-less, and the result goes to the log and to `run-stats.txt`, which puts it in the next morning's report. The data was never the problem: `autodream-now.sh <date>` rebuilds one in minutes because the findings survive and it skips straight to L2.

## Background: Which code actually ran (`runner_commit`)

This section was moved here from the former CLAUDE.md. Its original title: "Which code actually ran (`runner_commit`)".

`install.sh` symlinks `~/.claude/autodream/*.sh` straight at the repo working tree, so the nightly executes whatever is checked out at 03:15. A tree behind origin runs old code even though the fix is merged and the PR is green. This has cost data twice: the 2026-07-24 `overlap-stats.sh` dangle, and a tree stuck on a local commit from 2026-07-20 to 2026-07-24 that wrote four nights of `run-stats.txt` with no `oversized_*` / `gated` / `overlap_*` keys at all.

`run-stats.txt` therefore carries `runner_commit` + `runner_dirty` (#29). The diagnostic that matters: a `run-stats.txt` that is *missing keys*, rather than holding suspicious values, means an old runner — not a stat that didn't apply. Both times it took a reflog dig to establish that.

`bin/oversized-gate.sh` exists because of the same incident. The #12 gate is a trailing-window judgment but `run.sh` records one night at a time, so a stretch of old-runner nights used to be unrecoverable. It recomputes the window from the `*.stats.json` sidecars and findings JSONs still on disk, which survive independently of whether the runner knew how to count them. Artifacts only, no model calls, safe to re-run. It refuses to call an empty window a measured 0%, and quotes a rule-of-three upper bound so a clean run isn't read as stronger evidence than the sample supports.

## Background: One repo, no sibling to drift from

This section was moved here from the former CLAUDE.md. Its original title: "One repo, no sibling to drift from".

This repo used to have a twin, **omp-autodream**, the OMP port, and five helpers were kept
byte-identical with it by a drift check (`bin/check-shared-drift.sh`, `shared-with-sibling.txt`).
The reason was real: on 2026-09-11 the X bookmarks queryId walk was fixed in omp-autodream after
X moved to 16-character webpack chunk hashes, the identical file here was never touched, and this
install kept failing every night for ten nights while both repos' suites passed, each internally
consistent. omp-autodream is archived and its code lives here (see "Moving from omp-autodream" in
the README), so there is one copy of each helper and nothing to compare against. The check and its
manifest were removed in issue #106. The habit that outlives them: **a review finding is a class,
not a site.** Before fixing a pattern in one script, grep for it in the others.

## autodream-note.sh resolves its install dir like the reader of the notes file does

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-note.sh` (the `resolve_install_dir` call, `NOTES`)

### Context

The writer of `notes.md` and its reader must agree on one directory. `autodream-note.sh` once hard-coded `$HOME/.claude/autodream`, while `vault-notes.sh` takes `AUTODREAM_DIR` from the launchd plist. The moment an install lived anywhere else, every note landed in a file the nightly never opened. There was no error and no missing note reported (#91, #112; `bin/lib-install-dir.sh` carries the resolver).

### Decision

The script calls `resolve_install_dir` with its own name: the environment first, else the script's own directory when it carries an install marker (`install.sh` writes `config` and links `PROMPT.md`), else the legacy default with a warning. `BASH_SOURCE` stays unresolved on purpose, because `install.sh` symlinks the scripts into `$TARGET`, so the link's directory is the install dir. `AUTODREAM_NOTES_FILE` overrides the file itself.

### Consequences

`docs/adr/0017-operator-notes-and-vault.md#vault-notes-resolves-its-install-dir-and-sources-the-config-the-way-runsh-does` records the reader's side of the same rule, and `docs/adr/0023-install-and-scheduling.md#an-installed-script-finds-a-newer-helper-through-its-own-symlink-target` the symlink-target fallback for `lib-install-dir.sh`. `tests/notes-path.sh` and `tests/install-dir.sh` pin the agreement.

## one resolver decides the install dir, from the script's unresolved path

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-install-dir.sh` (`resolve_install_dir`)

### Context

Six scripts each carried their own copy of the resolver, and the copies drifted (#112). They disagreed on which files prove a directory is an install, on whether to warn, and one never looked at its own location at all. The writer and the reader of the operator notes disagreed on the directory the moment an install lived anywhere but `~/.claude/autodream` (#91), and every note landed in a file the nightly never opened, with no error.

One of the two markers some copies tested, `l1-no-advisor.yml`, came from the OMP install, and nothing in this repo installs it.

### Decision

A script sources the helper and calls `resolve_install_dir "${BASH_SOURCE[0]}" [NAME]`. It sets `AUTODREAM_DIR` and does not export it:

1. An `AUTODREAM_DIR` already in the environment wins.
2. Otherwise the directory the script sits in, when it holds `config` (written by `install.sh`) or `PROMPT.md` (one of its symlinks). The caller's `BASH_SOURCE` stays unresolved on purpose: `install.sh` symlinks each script into `$TARGET`, so the link's own directory is the install dir, while the resolved path is the repo. No marker lives in the repo's `bin/`, so running from a checkout never mistakes `bin/` for an install.
3. Otherwise the legacy default `~/.claude/autodream`. With `NAME` it prints `NAME: WARNING ...` on stderr; without it the fallback is silent, which is what the scripts that never warned (`autodream-now.sh`, `notify.sh`, `question-streaks.sh`) keep.

### Consequences

A new caller passes `BASH_SOURCE[0]`, not a resolved path, or it finds the repo and falls back to the default. Adding a marker is one line here. docs/adr/0001-runner-lifecycle.md#background-where-state-lives and `tests/install-dir.sh` pin the callers.

## preflight stops hard on missing `jq`, `shasum`, `realpath` and the L2 engine, and only warns about `python3`

Status: accepted · Date: 2026-11-21 · Code: `bin/preflight.sh` (`need`, `_forced_missing`)

### Context

Preflight runs before anything is enumerated. `run.sh` already depended on all four tools; `realpath` is the new one, for adapter containment and cwd canonicalisation.

| Tool | What its absence costs |
|---|---|
| `jq` | every findings record, sidecar and manifest is parsed with it |
| `shasum` | the artifact key is sha1 of the session path; with no `shasum` every session collides on one filename, silently (see `docs/adr/0002-session-enumeration.md#the-artifact-key-is-a-validated-12-character-hex-prefix-of-sha1-and-nothing-derives-it-any-other-way`) |
| `realpath` | adapter directory containment and cwd canonicalisation; a host that reached adapter loading without it would fall back to weaker containment, which is the failure the check exists to prevent |
| `python3` | the project-field normalisation step is skipped and L2 grouping may show duplicate projects |

`python3` was once fatal here, and that contradicted the normalisation step, which already degrades gracefully without it. On a host where `python3` is only a pyenv shim absent from the launchd PATH, the nightly would have gone from a slightly worse report to no report at all, every night.

Emptying `PATH` to hide one dependency also hides bash's own helpers, so the suite could not otherwise exercise a single missing tool.

### Decision

- `need` prints `MISSING: <tool>` and counts it. Any missing tool makes the script print `preflight_missing: <keys>` and exit 1. `realpath` is security-critical, so it is never a degraded path.
- `python3` prints `DEGRADED:` and does not change the exit status.
- A configured L2 engine binary that is not found is `MISSING` too (key `l2_engine`).
- `AUTODREAM_PREFLIGHT_FORCE_MISSING` takes a comma-separated list of names to treat as absent. It exists for tests only and is unset in every real run.
- `--l2-bin` with no value exits 2. `shift 2` with one argument left fails and shifts nothing, so `$#` never decreases and the loop would spin forever. Preflight runs before the idempotency guard, so a wedged one would also block every launchd catch-up trigger behind the "label already running" rule. `oversized-gate.sh` validates `--days` for the same reason, where the bug had been observed: `--days` with nothing after it left `$#` at 1 and spun.

### Consequences

Adding a dependency means choosing hard stop or degraded on purpose: a hard stop for anything whose silent absence corrupts results, a warning only where the code already has a working fallback. `tests/preflight.sh` pins both paths.

## every expansion of a possibly-empty array is guarded for bash 3.2 under `set -u`

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`${L2_ARGV[@]+"${L2_ARGV[@]}"}`, `${L2_ENVS[@]+...}`)

### Context
`run.sh` runs under `/bin/bash`, which is 3.2 on macOS and what launchd uses. Under bash 3.2 with `set -u`, `"${a[@]}"` on an EMPTY array is an unbound-variable error, where bash 5 expands to nothing. A warmup that aborted for exactly that reason passed the whole suite until the suite ran the shipped interpreter (see docs/adr/0028-test-suite-organization.md#background-the-test-suite).

### Decision
Every element expansion of the L2 argv and env arrays at the L2 launch uses the `${a[@]+"${a[@]}"}` form. The `${#L2_ARGV[@]}` length tests and the array assignments need no guard, because only an element expansion of an empty array trips `set -u`.

### Consequences
Run the suite under `/bin/bash`, not whatever `bash` is first on PATH. A new array expansion here needs the same guard.

## the enabled-adapter list is resolved once into a global by a function that prints nothing

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`resolve_enabled_adapters`, `ENABLED_ADAPTERS`, `ENABLED_ADAPTERS_RESOLVED`, `_enabled_adapters_uncached`)

### Context
The first version was a memoised `enabled_adapters` that every caller invoked as `$(enabled_adapters)`, so the cache assignment happened inside a command substitution and died with the subshell, leaving `ENABLED_ADAPTERS_RESOLVED` at 0 in the parent on every call. The loader re-ran all three times and the duplicate warning the memo was written to stop came straight back (reproduced: the uncached body ran 3/3 times and the cache stayed empty). It is the trap `adapters.sh`'s own header documents for `adapters_rejected`: a file crosses the subshell boundary, a variable does not.

### Decision
`resolve_enabled_adapters` assigns the global and returns, printing nothing; callers read `ENABLED_ADAPTERS`. The boundary is crossed by not creating one. Inside the uncached resolver, the "accepted but not enabled" diagnostic goes to stderr, NOT stdout: the function's stdout is its return channel and `log()` is a bare echo, so a diagnostic on stdout was word-split into bogus adapter names.

### Consequences
Never call `resolve_enabled_adapters` inside `$(...)`, and never log to stdout from a function whose stdout is captured. docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent has the same class ("A variable set inside `$(...)` never comes back").

## every FATAL funnels through log_fatal and fatal_exit, which leave a marker AND post a banner, never a stub report

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`FATAL_REASON`, `log_fatal`, `fatal_exit`, `notify_fatal`)

### Context
A run that dies writes no report and posts no banner; until `fatal_exit` existed a failed night was completely silent (the log line was the only record, and nothing reads the log). The marker and the banner cover different failures: a transient cause is caught by the marker when a later night succeeds, while a persistent one (a lost exec bit, jq off the launchd PATH) never has a later success to be read by, so it needs the banner tonight.

### Decision
- `log_fatal` records the reason in `FATAL_REASON` so it survives to the exit path.
- `fatal_exit` writes a short `run-stats.txt` (a header line, `runner_commit`, `runner_dirty`, `fatal`, `sessions_triaged: 0`, then the remote-sync lines when there are any) and calls `notify_fatal`. The `fatal:` line is the marker the next run reads (`unassembled_dates` reads it as the reason a date has no report). It is deliberately NOT a stub report: a report is what the idempotency guard reads as "this date is complete", and it is not.
- NEVER over a date that already has a report. `AUTODREAM_FORCE` bypasses the idempotency guard by design (the documented `autodream-now.sh <date> --force` path), so any fatal under it would otherwise overwrite that date's full L1/L2 telemetry with the stub and announce a FAILED night while `dreams/<date>.md` sits there complete; `unassembled_dates()` would not catch it because the report exists.
- The guard covers the WRITE only. The first version returned before the banner too, and that branch is reachable in exactly one situation, the detached `--force` rebuild under launchd, where the banner is the only surface an operator sees: with no banner the operator polls `dreams/<date>.md`, finds the OLD report, and reads a failed rebuild as a successful one. So the guarded branch still calls `notify_fatal`, with the note that the existing report is unchanged.
- Both fatal paths post through `notify_fatal`, so the posting lives in one place. Keeping two copies is how the guarded path lost its banner in the first place.

### Consequences
A new fatal must go through `log_fatal` and the `fatal_exit` exit, not `exit 1` after a bare echo (the pre-log startup FATALs are the exception: the log does not exist yet).

## Findings JSONs outside this run's worklist are set aside, not deleted

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`reconcile_findings_with_worklist`, `worklist_hashes`)

### Context
Issue #56. L2 reads every findings JSON in the directory, and a forced rerun reuses the directory, so a JSON left by an earlier run for a session this run's worklist no longer owns would reach the report as that day's work. It is silent: a stale `<hash>.json` is a well-formed record.

### Decision
Before the pre-L1 cache snapshot, once per run, each 12-hex `<hash>.json` outside the worklist is moved to `findings/<date>/outside-worklist/`, which L2's glob does not reach, and counted (`FINDINGS_OUTSIDE_WORKLIST`) and named in the log. Moved, not deleted: deleting findings is not this runner's call, and a later rebuild whose worklist owns the session again gets its JSON back before L1 runs (the first loop restores from `outside-worklist/`), so the rerun does not pay for the triage twice. A restore is skipped, with a WARNING, if the findings dir already holds that hash, and a restore or set-aside whose `mv` fails logs a WARNING and carries on (a failed set-aside means L2 will read that JSON; a failed restore means the session is triaged again). It also runs on the zero-session early exit, ahead of `scan_worklist_leftovers`. Never overwrite an earlier set-aside copy: a second one gets a timestamped name (`<hash>.json.<epoch>`).

`worklist_hashes` prints each hash on its own line because `session_hash` prints no trailing newline, and the `grep -x` matching would never match two hashes run together.

See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to" (Findings left by an earlier run (#56)).

### Consequences
A clean rebuild still means removing the date's findings directory first if the stale files should go for good.

## a report is complete when it carries the end marker, never merely when its path is non-empty

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_complete`), `bin/report-format.sh` (`report_finishes`)

### Context

`-s` cannot tell a finished report from one the aggregator was killed halfway through writing; a truncated report satisfies it as well as a good one. That mattered three ways: the L2 retry loop would break after attempt 1 on a partial file, the superseded good copy would be deleted, and the consume gate would archive the user's notes and stamp bookmarks read against a half-written report. Mid-write death is exactly the sleep-kill scenario the retry machinery exists for. The marker (`<!-- autodream:open-questions=N -->`) closes the Open questions section, which is the last section PROMPT.md has L2 write, so its presence means the write reached the end. (The original comment called it the last thing PROMPT.md emits; the stdout grammar since added `AUTODREAM_REPORT_END`, which the runner strips before the report is stored.) See docs/adr/0001-runner-lifecycle.md#background-sleep-resilience, "Sleep resilience" and "Operator notes".

### Decision

`report_complete` calls `report_finishes "$REPORT_PATH" "$TARGET_DATE"`, which needs a non-empty file, the open-questions marker, and (for dates from the questions epoch) the questions block. It deliberately does NOT use `L2_RC -eq 0`: the CLI can exit non-zero after a perfectly good write. The live gate (`report_complete`), the abandoned-date sweep (`unassembled_dates`) and the pin sweep (`sweep_stranded_pins`) all end in `report_finishes`, so they cannot disagree about whether a date is finished. The idempotency guard's `report_finishes_date` adds one allowance: a report from before `AUTODREAM_MARKER_EPOCH` (default 2026-08-19) counts as finished without a marker.

### Consequences

Do not weaken the gate to a size test or an exit code. A new consumer of "is the report done" must call `report_finishes`.

## a helper's `AUTODREAM_*_BIN` override is authoritative, with no existability fallback

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`ROOT_PROBE`, `STATS`, `OVERLAP`, `VAULT_NOTES`, `XBOOKMARKS`, `REPORT_SCRIPTS`, `PRUNE_WORKTREES`, `TRIAGE_CANDIDATES` resolution blocks)

### Context
Tests need to force a stubbed, missing or deliberately broken helper: a nonexistent sidecar generator (#27), a missing or stubbed overlap binary so `compute_overlap_stats` takes its "not measured" paths (#26), a stub root prober so the scan fallbacks run deterministically, a missing vault or bookmark helper. The ordinary `[ -x "$X" ] || X="$AUTODREAM_DIR/..."` chain would rescue a nonexistent override back to the working repo copy and defeat the override.

### Decision
When `AUTODREAM_ROOTPROBE_BIN`, `AUTODREAM_STATS_BIN`, `AUTODREAM_OVERLAP_BIN`, `AUTODREAM_VAULT_BIN`, `AUTODREAM_XBOOKMARKS_BIN`, `AUTODREAM_REPORTS_BIN`, `AUTODREAM_PRUNE_BIN` or `AUTODREAM_TRIAGE_BIN` is set (non-empty), its value is used as is; only the unset case runs the "next to this script, then the install dir" lookup. The helpers are optional context-gatherers (vault-notes degrades to the plain notes.md when no vault is set, x-bookmarks to a "not configured" stub, the pruner is opt-in through `AUTODREAM_PRUNE_ROOTS` and a no-op otherwise, the triage list is on by default because it only reads issues, the report-script collector exists because L2 has Read and Glob only and a missing conf means no reports).

### Consequences
Do not add an existability fallback to an override branch; the tests that exercise missing-helper paths would silently pass against the real script. A new helper with a test-facing override follows the same two-branch shape. See docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, "Report scripts" and "Operator notes".

## helpers and libraries are found through `find_lib` (script dir, then the runner's real bin dir), not SCRIPT_DIR alone

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`SCRIPT_DIR`, `RUNNER_SRC`, `RUNNER_BIN_DIR`, `find_lib`, the `. report-format.sh` / `err-cause.sh` sources, `APPLY_PINS`, `FAILURE_CLASS`, `portable.sh` lookup)

### Context
`install.sh` symlinks each script into `~/.claude/autodream` individually, so a merge swaps the run.sh those links point at instantly, while newer helpers (`lib-project.sh`, `adapters.sh`, `preflight.sh`, `adapters/`, `apply-pins.sh`, `failure-class.sh`, ...) stay missing from the install dir until `install.sh` is re-run. Sourcing only from SCRIPT_DIR then skips them in silence and the run dies later on `session_hash: command not found`, with no report and nothing saying why.

### Decision
- The symlink walk (`RUNNER_SRC`) resolves this script to its real location, so the repo's own `bin/` is the fallback. The installed dir comes first, because that is the layout the nightly is supposed to have and the one whose files are meant to win. `find_lib <basename>` prints the first readable copy, or nothing: SCRIPT_DIR first, then `RUNNER_BIN_DIR` (empty when the walk gave up on a symlink, so then only SCRIPT_DIR is searched).
- `portable.sh` is looked up the same way (own dir, then the readlink target's dir) because installed copies are symlinks and a merge updates them before install.sh links a new helper.
- Libraries whose absence would corrupt the run are NOT optional: `report-format.sh` and `err-cause.sh` stop the run with a `FATAL` before any work, because an unfound lib would turn every read of a report into "command not found" after L1 had already been paid for.
- `apply-pins.sh` and `session-window.sh` use `find_lib` for the same reason; `failure-class.sh` is looked up in SCRIPT_DIR, the runner's repo dir, then AUTODREAM_DIR, after the runner walk, because an install made before it existed has a link for every other script but not this one and updating the checkout must not break that install's nightly (Codex review of omp-autodream b19ec84). The directory the run.sh link points at always has it. If none of the three has it the run exits 1 with `fatal: required failure classifier not found`.

### Consequences
A new helper must be resolved with `find_lib` (or the failure-class pattern) and must have a decided missing-helper behaviour: fatal for a library, degrade-and-say-so for an optional feature. See docs/adr/0001-runner-lifecycle.md#background-which-code-actually-ran-runner_commit, "Which code actually ran" and the install notes.

## a finished report makes later triggers cheap no-ops (the idempotency guard)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `report_finishes_date`)

### Context
Sleep resilience relies on several wake-time launchd triggers per morning. A run that failed overnight left no report and must proceed; once the night succeeded the later triggers must cost nothing.

### Decision
A report is only written after a successful L2 and carries the open-questions marker when whole, so a report that `report_finishes_date` accepts means the date is complete. `report_finishes_date` plus `AUTODREAM_FORCE != 1` logs `report already exists ... nothing to do`, records a `noop` outcome and returns 0 (`AUTODREAM_FORCE=1` rebuilds). A failed overnight run left no report, so it proceeds and finishes the work. A non-empty report that fails the check (no marker) logs `lacks the open-questions marker; treating <date> as unfinished and rebuilding it` and proceeds; the move-aside before L2 sets it aside as `.stale-<epoch>`, keeps it if the rebuild fails and discards it once a complete report replaces it.

### Consequences
See docs/adr/0001-runner-lifecycle.md#background-sleep-resilience, "Sleep resilience" (idempotency guard; a marker-less report is moved aside and rebuilt, #111).

## A finished report needs the open-questions marker, not just a non-empty file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_finishes_date`)

### Context
The idempotency guard (#111) used to test only `-s "$REPORT_PATH"`. A half-written report (a run killed mid-write, or an older runner's partial) read as done: every later trigger no-opped, and question-streaks cleared the board over it.

### Decision
`report_finishes_date` returns success when the report is non-empty and `report_complete` holds (`report_finishes`: the open-questions marker is present and, for dates on or after `AUTODREAM_QUESTIONS_EPOCH`, so is the questions block). A report for a date before `AUTODREAM_MARKER_EPOCH` (default `2026-08-19`) predates the marker and counts as finished. `unassembled_dates()` makes the same exemption, so the two agree about whether a date is finished. Unmarked reports under the epoch are named in the log line `note: unmarked reports predating AUTODREAM_MARKER_EPOCH (treated as complete)` and under their own key in `unassembled_dates`, so the exemption is visible. The exemption is a date and not a heuristic because a non-empty unmarked report is either legacy or a truncated capture, and only the date the contract began separates them; the scan window (`AUTODREAM_UNASSEMBLED_WINDOW`, 7 days) bounds the damage of a wrong epoch, and the epoch is the thing to set when backfilling older dates.

See docs/adr/0001-runner-lifecycle.md#background-sleep-resilience, "Sleep resilience" (idempotency guard).

### Consequences
The default `2026-08-19` is written in three places (the knob documentation in `docs/run-knobs.md`, `report_finishes_date`, `unassembled_dates`): change all three together or the guard and the sweep disagree. A marker-less report on or after the epoch is moved aside as `.stale-<epoch>` before L2 and rebuilt; the copy is kept if the rebuild fails and discarded once a complete report replaces it. See `finished-run-requires-end-marker` for why a non-empty file is not proof of completion.

## The per-run L1 ledgers are truncated past the idempotency guard

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `: > l1-timeouts.txt` block)

### Context
- A catch-up trigger that no-ops on a finished date must not wipe that date's record of what timed out. This point is past the idempotency guard, which is why the ledger is truncated here and not where `FINDINGS_DIR` is created.
- The chunk ledgers are append-only per run like the two above them. `l1-chunks.txt` holds one "hash chunks elided" line each time a session is planned (a retry plans it again, so readers keep the last line per hash). `l1-chunk-calls.txt` holds one "hash round chunk" line per engine call actually made, a reused answer making none, which is what a night cost in model calls.

### Decision
`l1-timeouts.txt` and `l1-netdown.txt` are truncated here, and `l1-chunks.txt` and `l1-chunk-calls.txt` too when `L1_CHUNKING` is 1.

### Consequences
- Moving the truncation above the guard lets a no-op catch-up trigger erase timeout evidence.
- Readers of `l1-chunks.txt` must take the last line per hash.

## numeric env knobs are refused or normalised at startup, never discovered at 03:15

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `case ... in ''|*[!0-9]*` blocks after `FANOUT`: `AUTODREAM_L1_TIMEOUT`, `AUTODREAM_L1_WARMUP_TIMEOUT`, `AUTODREAM_L1_CHUNK_BYTES`, `AUTODREAM_L1_MAX_CHUNKS`, `AUTODREAM_SANDBOX_SHAPE_MIN`, the noise-gate loop)

### Context
Each knob has its own way of failing silently if it is unvalidated:
- `AUTODREAM_L1_TIMEOUT` / `AUTODREAM_L1_WARMUP_TIMEOUT`: GNU timeout treats a duration of 0 as "no timeout", so an unvalidated 0 restores the exact hang the timeout bounds while the startup log still reports a timeout is set; a non-numeric value is worse (timeout rejects it and every worker fails). The warmup runs before every recovery path, so an unbounded warmup wedges the run.
- Chunk knobs: 0 is a real value for `AUTODREAM_L1_CHUNK_BYTES` (chunking off), so only a non-number is refused there; `AUTODREAM_L1_MAX_CHUNKS` below 1 would mean no chunk is ever read. Bash arithmetic reads `08` as an invalid octal number.
- `AUTODREAM_SANDBOX_SHAPE_MIN`: 0 would list every session, so the floor is 1. L2 cannot read the environment, so `write_rollup` hands it the value through run-stats (`sandbox_shape_denies_min`).
- `AUTODREAM_MIN_USER_TURNS` / `AUTODREAM_MIN_MINUTES` reach jq through `--argjson` with stderr discarded: a non-number makes jq fail, the noise gate comes back empty, and every session goes to a model call with no message.

### Decision
Each knob is checked with a digits-only `case` and, where 0 or less is wrong, a `-gt 0` / `-ge 1` test; the script exits 1 with a `FATAL:` line on stderr (the run log does not exist yet). Knobs that are used in arithmetic are rewritten with `$((10#$X))` so a leading zero is decimal whatever the user wrote. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage" for the chunk gate.

### Consequences
A new numeric knob needs the same treatment, with the reason its zero or non-number is dangerous. Do not relax the timeout zero check: it re-creates the 2026-08 hang.

## An orphaned .err is counted and named, never retried

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_worklist_leftovers`, `worklist_hashes`)

### Context
Issue #113. An orphaned `.err` is a failed triage nobody has finished: no findings JSON beside it, and its session is not in the worklist (the file is gone, or this run no longer places it in the day). While its session is in the worklist the retry loop owns it and `l1_missing_count` counts it. One with no owner is retried by nothing and seen by no other counter, so `l1_err_files` could not tell "two workers crashed tonight" from "two crashed last week and nobody retried".

### Decision
`scan_worklist_leftovers` sets `L1_ERR_ORPHANED` and `ORPHAN_ERR_NAMES` for each `*.json.err` with no findings JSON whose hash is outside `worklist_hashes`, and logs a WARNING. It reads `SESSIONS_LIST`, which is empty on a night that found nothing, so the same scan serves the early stub exit. It counts and names; it does not retry, because the `.err` is the only record of which session it was, and a worker with the Write tool could have put any path in it. A findings JSON outside the worklist is handled by `findings-outside-worklist-set-aside`.

`worklist_hashes` prints each hash on its own line, because `session_hash` prints no trailing newline and the `grep -x` match against whole lines would never match two hashes run together.

See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to" (Both halves of #113).

### Consequences
`l1_err_files` still counts every `.err` in the directory; `l1_err_files_orphaned` is the subset with no owner.

## run.sh appends its extra directories to the caller's PATH instead of replacing it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `export PATH=` line before `TIMEOUT_BIN`)

### Context
launchd hands the job a minimal PATH that lacks the engine binaries and git, which is why run.sh adds directories at all. Replacing the caller's PATH meant an interactive run and the nightly could resolve different binaries, and a test could not put a `curl` shim in front.

### Decision
`PATH="${PATH:+$PATH:}$HOME/.cargo/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"`: the caller's entries win, as in a shell, and the launchd case is still covered. docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37 records this under the network-defer notes ("`run.sh` appends to the caller's `PATH` instead of replacing it").

### Consequences
Do not prepend or reassign. The plist PATH written by install.sh is the other half (see docs/adr/0023-install-and-scheduling.md#background-what-goes-in-the-plist-path, "What goes in the plist PATH").

## One run per date at a time, through an flock held by a holder process

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`acquire_lock`, `release_lock`, `lock_take_dir`, `lock_names_live_run`, `lock_is_held`, `LOCK_HOLD_PY`, `acquire_run_lock`, `release_run_lock`, `proc_start`, `run`), plan `docs/plans/2026-11-21-fix_run-lock-liveness.md`

### Context
launchd serialises a label against itself and nothing more, and `autodream-now.sh` runs under a different label than the scheduled nightly (issue #55). An on-demand run and a trigger for the same date are two processes sharing one findings dir, one sidecar set and one report path, and the second one's move-aside would even carry off the first one's report mid-build.

The lock was first a `mkdir` plus a judgment about the holder's pid (issue #242). A failed `kill -0` read as dead though EPERM means a live process of another user, an empty `ps` read as a reused pid, a pid-less directory was reclaimed after three tries, and the `mv` that put a displaced lock back could nest it inside one another run had taken. A shell cannot make "judge the holder gone, then take its lock" atomic.

### Decision
- An `flock(2)` on `$AUTODREAM_DIR/locks/run-<date>.flock` decides who holds the lock. The kernel drops it when its holder ends, so nothing is judged or reclaimed. The lock sits outside the findings dir, so clearing a date's findings for a clean rebuild cannot release it under a live run. The directory `run-<date>.lock` only reports the owner's pid and start time (`proc_start`, from `ps -o lstart=`) for the web dashboard, and it is removed on release.
- The flock file sits beside the directory and is never removed. A file unlinked while a contender has it open lets two processes hold two inodes, and one kept inside the directory would show every finished date as "starting" in the dashboard. It is opened read-only with create, because `flock` needs no write access, so a run of another user can lock it. A file this user cannot open belongs to someone else and reads as held.
- A small python holder process owns the descriptor, not `run.sh`. Every child of a run (L1 workers, an engine, a banner, a sync job) would inherit an fd in the shell, and a leaked grandchild would keep the date locked after the run was killed.
- The owner is the shell that forked the holder, which the holder reads with `getppid` as its first act and reports in its answer (`ok <pid>`); that pid goes in the lock directory. `$$` is the top-level shell even inside a pipeline or background subshell, so an interactive run (a pipeline element) or a remote sync job (a background subshell) would be watched through the wrong process: killed, its holder would keep the date locked while the top-level shell waited on `tee`. A holder whose parent is already pid 1 never takes the lock. The holder checks the owner with `kill -0` before every attempt and again before it answers, counts a pid it cannot signal as alive, and leaves when the owner is gone, so a holder waiting behind another holder still notices. A pid reused within a quarter second of the owner's death is not covered.
- Release acts only for a lock this process recorded. A pid read from a directory proves nothing once pids are reused: a later process with a dead run's pid that found the lock held would remove the real holder's directory. `run` is a wrapper that sets the EXIT trap and releases in its own process, because an interactive run is a pipeline element whose subshell the parent's trap cannot see. `release_run_lock` is also the EXIT trap, which a run that never took the lock reaches too.
- A runner from before the flock holds only the directory. After the flock, a directory whose pid file names a live process that still has the recorded start reads as held (`lock_names_live_run`). A pid `ps` can see but `kill` cannot signal counts as alive, and a start `ps` cannot report counts as a match. A directory with no usable pid that is under a minute old is an older runner between its `mkdir` and its pid write, and reads as held; an older one is a crashed run's. The directory is taken over in place: a missing directory is made with a plain `mkdir` (which fails, and reads as held, when an older runner made it first), and a stale one is kept while its `start` and then its `pid` are overwritten. The runner never moves, renames or removes a directory it did not make: three review rounds each added a step (a rename aside, a judgment on the copy, a put-back) and each step opened a window, the last by making the older runner's own pid write fail. An older runner can only be one that was already running when the code was linked, so its directory is complete. An older-code process that starts after the link, or that is still inside its reclaim loop at the moment of the link, is not covered, and neither is a new runner against an older runner reclaiming the same stale directory at the same instant. It is the one pid judgment left, and it fails toward held: liveness is `os.kill(pid, 0)` in python, which prints one word, `dead` only for "no such process" and `alive` otherwise, and only the word `dead` from a probe that exited 0 counts: no output, any other word and any non-zero exit read as alive, so a pid another user owns, a probe that cannot answer and an interpreter that fails or exits with any code read as alive, and a pid of 0 or with a leading zero is no pid, because `kill -0 0` signals the caller's own process group. A lock path that is a symlink or a regular file is never written through, and a directory whose `start` or `pid` is a symlink, a directory or a file this user cannot write is refused before anything is touched, so a refusal leaves the directory as found. The two writes put the old contents back if the second one fails. Release removes the `pid` and `start` this process wrote and then `rmdir`s only when this run made the directory; a stale directory taken over in place is left as it is, holding this run's pid and start, which the next run and the dashboard read as a dead holder. Release does nothing to a lock that was not taken. The pin sweep opens the flock file and reads anything but "no such file" as held, so a locks directory it cannot enter is not read as idle, and answers held when python3 is missing.
- `acquire_lock <dir> [wait]` waits inside the holder. The run lock waits two seconds, because the sweep's probe takes the flock for milliseconds. The remote lock waits `AUTODREAM_REMOTE_LOCK_WAIT`. The holder answers through a file in the locks directory, and one a killed acquire left is swept after ten minutes.
- `acquire_lock` returns 3 in two different situations, and the log line says which. Before the flock is taken (no python3, no writable locks directory, a holder that never answered) the run goes on without the lock, with a WARNING saying so. After the flock is taken, a pid or start write that fails (a read-only locks directory, a stale directory with a file this user cannot change) also returns 3, but the flock stays held until `release_lock`: the run goes on with the date locked and only the dashboard's report of it missing, and the WARNING says that instead of "running without it".
- `sleep` in this code is plain `sleep`: under bash 3.2, `command -p sleep` inside a command substitution in a background job kills the subshell silently, which failed every remote sync until it was replaced.

### Consequences
The remote sync lock uses the same helpers with its own flock (see ADR 0015). The X browser lock in `x-bookmarks.sh` is still a `mkdir` lock with a pid and is not changed here. The pin sweep's window between probing a date and applying its pins existed with the pid check and still does. A change to the pid or start format in the lock directory affects the dashboard's Progress view and `lock_names_live_run`.

## Preflight runs below the idempotency guard, above enumeration, through bash, and owns the dependency checks

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the preflight block after the report-already-exists guard)

### Context
- With `shasum` absent, the artifact hash assignment yields an empty string and every session in the night writes to the same findings filename. A run that got that far would produce one record where it should have produced a hundred and report success. Stopping before enumeration costs a night; continuing corrupts one.
- Above the idempotency guard, a host missing one dependency turned an already-complete date from a one-second no-op into a failed run and an exit 1 on each of the four morning triggers.
- `install.sh`'s own comment worries about a distribution path that loses the exec bit (a zip, a restrictive umask). An `[ -x ]` gate answers that by skipping the check silently, which lands back in the empty-hash corruption preflight exists to stop.
- An earlier commit moved a `[ -x "$CLAUDE_BIN" ]` test to this spot, and its message claimed that made preflight's `--l2-bin` branch reachable. It did not: the `[ -x ]` test still ran first, and for an absolute path (the `CLAUDE_BIN` default) `command -v` cannot fail once `[ -x ]` has passed, so the `l2_engine` branch stayed exercised only by its own test suite. Two gates for one dependency, the second one dead.
- `L2_BIN` was always empty before `--l2-bin` was passed, so preflight's `l2_engine` check could only fire from its own test suite: a dependency gate with a branch production never reached.

### Decision
- `run` checks no `claude` binary itself. Preflight owns it, so the check that reports the failure is the one that fires.
- Preflight runs after the "report already exists" guard and before `scan_roots`/enumeration.
- It is gated on `-r "$PREFLIGHT"` and invoked as `bash "$PREFLIGHT" --l2-bin "$CLAUDE_BIN"`, not gated on `-x`. A present-but-unreadable preflight logs `WARNING: preflight not readable ...; the shared-dependency check did NOT run`.
- A preflight failure is `log_fatal`, `fatal_exit`, return 1, "Nothing was enumerated."

### Consequences
- Do not re-add a `[ -x "$CLAUDE_BIN" ]` check above preflight, and do not gate preflight on `-x`.
- Moving preflight above the idempotency guard makes a missing dependency fail finished dates on every catch-up trigger.
- Moving it below enumeration lets the empty-hash corruption write a record for the night.
- Dropping `--l2-bin` makes the `l2_engine` check unreachable in production again.

## PROJECTS_DIR's default is applied at startup and whether the caller set it is recorded separately

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`PROJECTS_DIR_EXPLICIT`, top of file)

### Context
Session-root resolution is SESSION_ROOTS, then PROJECTS_DIR (only when the caller chose it), then autodetect. `${PROJECTS_DIR:-default}` cannot tell "unset" from "set to the default value".

### Decision
`PROJECTS_DIR_EXPLICIT` is set from `${PROJECTS_DIR+x}` before the default is applied (a variable set but empty counts as explicit and takes the default value). `probe_roots` treats PROJECTS_DIR as a single root only when that flag is 1 and `SESSION_ROOTS` is empty. See docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, "Session roots: one dir is not the corpus".

### Consequences
Treating the always-present default as explicit would make autodetect unreachable (every run would be a single-root run). Do not collapse the flag into the `:-` default.

## how a run ended is written to a per-token outcome file, and nothing else tells the watcher

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`write_run_outcome`), `bin/autodream-now.sh` (`--watch`)

### Context

`autodream-now.sh --watch` must know whether a report was delivered. The runner is the only one that knows. The log (which also holds model text), the report's mtime (a whole second) and a completeness predicate the watcher evaluates for itself (with another config's epoch) each gave the wrong answer. See docs/adr/0023-install-and-scheduling.md#background-running-on-demand-without-the-10-min-cap-autodream-nowsh, "Running on-demand without the 10-min cap".

### Decision

`write_run_outcome <delivered|noop>` appends `<token> <state>` to `logs/run-<date>.outcome`. The token is the watcher's own id for the launch (`AUTODREAM_RUN_TOKEN`), so a line from an earlier run is never mistaken for this one and no clock is involved. A token outside `[0-9A-Za-z._-]` or no token writes nothing, which is every scheduled run. `delivered` means a validated report stands (the L2 report, or the no-sessions stub when it was written and passes `report_complete`; a stub that could not be written logs a warning and writes nothing); `noop` means a finished report already existed and nothing was rebuilt. A run that ends any other way writes nothing.

### Consequences

Do not infer readiness in the watcher from the log, the mtime or a re-evaluated predicate. A new way a run can legitimately end with a report must write one of the two states. `test_run_outcome_is_written_only_for_a_delivered_or_untouched_report` pins it.

## run.sh sources the config in a nounset-off, `set -a` block and replays the caller's exported environment

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `AUTODREAM_CONFIG` block after `AUTODREAM_DIR`)

### Context
run.sh historically ignored `~/.claude/autodream/config`; only review.sh sourced it. That was fine while every key was review-only, and stopped being fine when a key had to reach the nightly run (`AUTODREAM_VAULT_DIR`). The script runs under `set -u`, and sourcing a user-edited file under nounset makes ANY unbound reference in it (for example a typo'd `X_CREDS_FILE=$AUTODREAM_HOME/x-credentials`, meaning AUTODREAM_DIR) abort the shell before LOG_DIR or `log()` exist, so nothing reaches the run log and no report is produced. `|| echo WARNING` cannot catch that, because nounset kills the shell instead of making `.` return non-zero. run.sh never sourced the file before the vault-notes feature, so a typo that used to be harmless would silently cost a night.

### Decision
See docs/adr/0001-runner-lifecycle.md#background-runsh-sources-the-config-now, "run.sh sources the config now". In the code:
- The block runs after AUTODREAM_DIR is resolved, so AUTODREAM_DIR itself must come from the environment, not the config (it names the config's own location).
- The caller's exported environment is snapshotted (`export -p`), the config is sourced, and the snapshot is replayed with `eval`, so names the caller set win and names only the config sets survive. The config uses plain `KEY=value`, so a bare `.` would let it clobber a variable the caller deliberately exported (tests set env; `AUTODREAM_VAULT_DIR= run.sh` must disable the vault).
- `set -a` wraps the source: helper scripts are separate processes, so a config key that stays an unexported shell variable reaches nothing.
- Pass 1 sources the config in a throwaway subshell under `set -u`, only so bash's own error (which names the unbound variable) can be surfaced as a WARNING. A subshell dying from `set -u` does not kill this shell and touches no real state.
- Pass 2 sources for real with nounset off, so a bad reference degrades to an empty expansion for that one reference and every other key (before or after the bad line) is still set and exported.

### Consequences
Both helper scripts that source the config need the same guard (fixing only run.sh left them dying). Keep the probe subshell: removing it loses the diagnostic naming the bad variable. Keep `set -a` and the snapshot replay together.

## sweeps that need only files on disk run above the idempotency guard, so a catch-up trigger that no-ops for today still does them

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `write_unindexed_flag`, `sweep_stranded_pins`)

### Context
The idempotency guard returns early once today's report is finished, and launchd fires several catch-up triggers, so most triggers return at the guard. Anything placed below it only happens on the one trigger that does the work.

### Decision
- `write_unindexed_flag` writes the found-but-not-indexed Claude folders for the report (never a prompt here) before the guard, so a catch-up trigger still reports folders that appeared since setup.
- `sweep_stranded_pins` applies pins an earlier run left unapplied, whichever date they belong to, before the guard can return. It needs only files on disk, so it runs whether or not this date has work to do.

### Consequences
Do not move either below the guard. `unassembled_dates` follows the same rule (see its ADR). See docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, "Session roots: one dir is not the corpus".

## the runner's symlink walk is capped at 8 hops

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`RUNNER_SRC`, `runner_hops`)

### Context
A symlink can point at another symlink, and a target can be relative to the link's own directory rather than to `$PWD`. A cycle must not hang the run. A cap has to be reachable in a test: macOS refuses to execute anything behind 16+ links (ELOOP), so a cap at or above 16 could never fire on a script that got far enough to run this code, and an untestable guard is a guess. Linux allows 40, where a larger cap could genuinely fire.

### Decision
The loop follows at most 8 links, resolving a relative target against the link's directory. A real install is one hop.

### Consequences
Do not raise the cap to a "rounder" number. A walk that stops while still on a symlink means it gave up; `runner-provenance-stamp` depends on that (it stamps no sha for a still-linked path).

## every write and read of the session worklist and its provenance index fails closed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter`, `build_source_sidecar`)

### Context

Collision detection exists so two sessions never reach dispatch onto one `<hash>.json`. Every way its bookkeeping can fail silently arrives at that same overwrite:

- Losing one half of the paired write (`sessions.txt.raw` or `.src`) desynchronises the worklist from its provenance, and the collision detector reads the provenance half.
- If `.hash-to-path` cannot be written, every path looks unseen and no collision is ever detected. If `.collided` cannot be appended, the drop set is short and the fatal dedup block is bypassed.
- `grep -qxF ... || continue` treated "legitimately absent" (exit 1, dropped at enumeration) and "grep failed" (exit >1) as the same thing. On an I/O error that skips the row silently, so a collision may never be detected and the unchanged worklist is dispatched with both paths on one artifact: failing open on the way in to a check that fails closed on the way out.
- A write-only `.hash-to-path` passes the truncate and append guards and still cannot be read, so awk's read error returns empty, indistinguishable from "hash unseen"; every path would look new and `.collided` would stay empty.
- A silent `|| :` on the sidecar write drops rows on a full disk, and `SESSIONS_BY_SOURCE` is then computed from the short sidecar and reported as fact.

### Decision

The paired session-list writes in `scan_one_adapter` are both checked (`log_fatal`, and `rm -f` of the `.enum.*` staging file on that exit too: under `AUTODREAM_FORCE=1` the findings dir is reused across reruns, so repeated failures would pile up `.enum.*` files in the directory the aggregator globs). `build_source_sidecar` truncates `sessions-source.txt`, `.hash-to-path` and `.collided` up front and refuses to run blind if any cannot be written. The worklist membership check switches on grep's status (0 present, 1 skip, other fatal). The `.hash-to-path` lookup checks awk's status. The sidecar append is checked, and so is the read of `sessions.txt.src` itself (`done < ... || { log_fatal ...; return 1; }`). Each failure is `log_fatal` plus `return 1`.

### Consequences

Do not add a `|| :` or `|| continue` to any of these to make a test pass. The only deliberately survivable failures in this function are the sidecar row rewrites, see `collided-sessions-dropped-both-and-verified`.

## a sleeping laptop is survived by re-dispatching missing sessions across wake cycles and retrying L2

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the sleep and network helpers: `wait_for_network`, `l1_missing_count`, the L1 and L2 retry loops)

### Context

A laptop that sleeps mid-run loses the network and whole batches of workers fail: started on a brief wake, slept through the run, about half the workers errored and L2 produced no report. See docs/adr/0001-runner-lifecycle.md#background-sleep-resilience, "Sleep resilience", which carries the full record (the 104 of 215 worker failures, the launchd facts).

### Decision

The L1 worker is idempotent, since a session with a findings JSON is skipped, so the run re-dispatches only the still-missing sessions across wake and sleep cycles until they land, and retries L2 until a report exists. The knobs are tunable (`AUTODREAM_L1_ROUNDS` default 5, `AUTODREAM_L2_ATTEMPTS` default 3, `AUTODREAM_RETRY_WAIT` default 60 seconds); the network wait and the sleeps are disabled in tests.

### Consequences

Idempotence of the worker is what makes retry cheap; a change that makes a re-run of a session non-idempotent breaks this design.

## in-place list rewrites go through two helpers that replace the file atomically and account for every failure

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sort_unique_inplace`, `rewrite_filtered`)

### Context

`sort -u FILE -o FILE` can leave FILE empty or partial when it fails, and every consumer downstream trusts the damaged file. The worklist and the collision drop set both used the unchecked form; the drop set was fixed first and the worklist left, a half-fix.

The same three-line grep-then-mv pattern was patched site by site across four review rounds, and each patch closed one hole and left another: the grep status was swallowed, then checked but the `mv` was not, then the `mv` was guarded but its failure was silent. Three copies meant three chances to get it wrong.

### Decision

`sort_unique_inplace FILE WHAT` sorts to `FILE.su.$$` and `mv`s it over FILE; on failure it removes the temp, `log_fatal`s and returns 1. `rewrite_filtered FILE WHAT <grep args>` writes to `FILE.rw.$$`, treats grep exit 1 as a legitimate empty result and exit >1 as failure, and replaces the file only if the `mv` succeeds. On any failure the original is untouched, a reason is logged and the caller gets a nonzero status to decide whether that is survivable. One helper per job, all callers use it.

### Consequences

Do not inline a new `grep ... > tmp && mv` variant at a call site. The caller decides survivability: the worklist rewrite is fatal, the provenance-row rewrites are `|| :` (see `collided-sessions-dropped-both-and-verified`).

## an existing dream is moved aside before L2, and a failed move disarms consuming

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `STALE_REPORT`, `CONSUME_SAFE`, `PINS_SAFE`)

### Context
The only way to reach this point with `$REPORT_PATH` already non-empty is `AUTODREAM_FORCE=1`. Nothing below distinguishes "this run wrote it" from "it was already there": `report_complete` and the consume gate both read the path. The retired comment also said an old report would stop the retry loop after attempt 1; that half is stale, since the loop now breaks on `L2_DELIVERED` plus `report_complete`, not on `-s`. What remains is that a leftover report would satisfy `report_complete` and so the pins and consume gates (for instance if the post-loop partial move also failed), and the consume gate would archive the vault note and mark bookmarks read as if something had read them. That is the overnight failure mode (Mac sleeps mid-run, every L2 attempt fails) turning into silent, unrecoverable data loss for the user's notes and bookmarks.

### Decision
The old file is moved to `$REPORT_PATH.stale-<epoch>` first, so a non-empty path again means "this run produced it". It is moved, not deleted: if every L2 attempt fails, the last good report for this date stays recoverable. If the move fails, `CONSUME_SAFE=0` disarms archive and mark-read for the run (and pins), rather than warning and carrying on; that is the point of the block, not a side effect. See docs/adr/0017-operator-notes-and-vault.md#background-what-the-consume-gate-actually-has-to-check-pr-37-review, "What the consume gate actually has to check (PR #37 review)".

### Consequences
"A guard whose failure path continues is not a guard." The copy is retired by `superseded-dream-copies-retired-outside-existence-test`.

## the run names dates whose findings were never assembled into a complete report, judging completeness by the open-questions marker with a dated exemption for legacy reports (#36)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`unassembled_dates`, `run`)

### Context
A run killed during L2 leaves a full findings dir and no report, and nothing notices: `notify.sh` never runs, so there is not even a quiet banner. 2026-07-26 sat that way for two days and was found during an unrelated investigation; 2026-08-01 did it again. The catch-up triggers cannot cover it, because launchd will not start a second instance of a label that is already running, so a run slow enough to span its own catch-up window turns those triggers into nothing at all. Recovery is cheap whenever the findings survive (`autodream-now.sh <date>` skips straight to L2), so the gap was never the data; it was that nobody was told.

The marker became mandatory partway through this tool's life, so every report written before that is non-empty, complete and unmarked. Judged by the marker alone they all looked abandoned: on the author's host the check named six consecutive good reports every night, which trains a real warning into background noise. "Non-empty but unmarked" is genuinely ambiguous (a legacy report or a truncated capture), and the only fact that separates them is when the contract began.

### Decision
`unassembled_dates` scans the trailing `AUTODREAM_UNASSEMBLED_WINDOW` days (default 7) of findings dirs, skipping `TARGET_DATE` (this run is about to assemble it, and a stub dir from an earlier attempt would report itself as a failure), and prints `unassembled|legacy`, both comma-separated and either empty.
- A date counts when its dir holds a findings JSON (not just `*.stats.json` sidecars, which were never triaged), or a `run-stats.txt` carrying `fatal:` (a night that died before it could triage anything has no other surface: no report, no notification, nothing to rebuild from).
- Completeness is `report_finishes` (the marker, plus the questions block for dates on or after `AUTODREAM_QUESTIONS_EPOCH`; not `-s`: a report killed mid-write is not a report). A missing or empty report is always listed as abandoned. A non-empty report that fails `report_finishes` and is dated before `AUTODREAM_MARKER_EPOCH` (default 2026-08-19; ISO dates compare lexicographically, so this is chronological) is listed under `legacy` and not as abandoned, under its own key so the exemption is visible.
- The `fatal:` reason is carried with the date, with commas replaced by semicolons, because PROMPT.md tells L2 to read the value as a comma-separated date list and the likeliest reason embeds one (`rejected: claude,evil` turned one dead date into three entries). `fatal_exit` writes the reason into that date's own `run-stats.txt` and L2 only reads its own date's file, so without carrying it the marker was written and read by nothing.
- `run` calls it above the idempotency guard, logs a WARNING plus the `autodream-now.sh <date>` rebuild command, and logs legacy dates as a `note:` (not a warning) so a date that should not be legacy is visible. The result reaches run-stats as `unassembled_dates`.

### Consequences
The exposure is bounded: an epoch that is wrong for a given install self-corrects within a week of upgrading; set `AUTODREAM_MARKER_EPOCH` when backfilling older dates. See docs/adr/0001-runner-lifecycle.md#background-nobody-was-told-unassembled_dates, "Nobody was told (`unassembled_dates`)".

## an unattended run logs to a file, and SIGPIPE is ignored on the interactive path

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the tail of the script: `trap '' PIPE`, `trap release_run_lock EXIT`, the `[ -t 1 ]` branch)

### Context
`run 2>&1 | tee -a "$RUN_LOG"` turns every log line into a write to a pipe, so whatever kills `tee` kills the run on its very next log call, by SIGPIPE with no error line, before the L2 retry loop, the move-aside blocks, or the consume gate are ever reached. Three runs on 2026-08-02 died exactly there and left 2026-08-01 with no report at all: `Terminated: 15` on `tee`, `Broken pipe: 13` on run, and a log ending mid-sentence at "L2 aggregation attempt 1/3...". Every recovery path in this script assumes it gets to run, and a logger that can revoke that assumption defeats all of them at once.

### Decision
A file has no reader to lose, so an unattended run writes to `$RUN_LOG` directly (`run >> "$RUN_LOG" 2>&1`). Ignoring SIGPIPE covers the interactive path too, where `tee` is still worth having and a closed terminal should cost the run its output rather than its life. See docs/adr/0001-runner-lifecycle.md#background-the-logger-could-kill-the-run-and-did-2026-08-02, "The logger could kill the run, and did (2026-08-02)" (the source of the SIGTERM on `tee` is still unnamed). Pinned by `test_dead_stdout_does_not_kill_the_run`.

### Consequences
Do not restore a pipe to `tee` for the non-TTY path.

## A night with nothing to triage still cleans up, reconciles, and writes the full run-stats key set

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `COUNT -eq 0` early path)

### Context
- A zero-session night is not always an empty night. Every session can be rejected for an unrepresentable path or dropped by collision handling. Without run-stats on this path the report said "no sessions were modified" while the counters that would have contradicted it were never recorded.
- PROMPT.md tells L2 that keys missing from `run-stats.txt` mean the runner predated the stat. A zero-session night on CURRENT code therefore produced a morning report blaming a stale checkout for the gap. A night with nothing to triage genuinely did zero L1 rounds and measured no overlap; saying so differs from not saying it.
- The first draft of the key set emitted `l1_missing`, `oversized_slimmed`, `overlap_pairs` and `elapsed`, none of which the full-run block writes. That would have left the real keys missing while adding four L2 has never seen.
- An empty worklist owns nothing, so every `.err` with no findings JSON is orphaned and every findings JSON is outside it. A night that found no session must not report zero over a directory that holds stale failures.
- PROMPT.md defines an empty `unassembled_dates` as "none" and tells L2 to name the dates for any non-empty value, so writing `none` handed L2 a date list to report.

### Decision
- `sweep_killed_leftovers` runs before the exit: a night with no sessions still owes the cleanup.
- No L2 runs on this path, so no model reads a report file tonight: report scripts are not collected here, as operator notes and bookmarks are not. See docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, 'Report scripts' ("A zero-session day collects nothing, on purpose").
- `reconcile_findings_with_worklist` and `scan_worklist_leftovers` run here and `l1_err_files` is counted from disk.
- `run-stats.txt` is written with the full-run key set as real zeroes (or the real values), with the key names copied from the full-run block. Keys the full run appends after that block (`x_queryid_source`, `x_fetch_path`, `l2_engine`, `l2_model`, `citations_*`) are not written on this path, and neither is `legacy_marker_reports`, which only the full-run block writes. `self_sessions_excluded` and `sessions_skipped_empty` are emitted so a night of worker transcripts or empty shells does not look like a night with no files. The shortfall counters (`roots_partially_enumerated`, `roots_unavailable`, `roots_failed`, `session_roots`) belong here most of all, because a partial walk or a single-root regression is exactly what would explain the empty night. `overlap_measured: no` is emitted with zero events and zero sessions, which is not the same as the overlap pass having failed. `unassembled_dates` is written empty, never `none`.

- The stub body does not state an empty night as fact when it cannot support it. A failed or unavailable session root (counted against `ROOTS_CONFIGURED`, not `ROOTS_SCANNED`, because a root that was never a directory is missing from `ROOTS_SCANNED` entirely) or a remote host that did not fully sync says "whether this was an empty night is unknown". Files modified since the day began but with no record inside it are said with their count, not as "no files were modified". Refused paths never reach `sessions.txt.raw`, so they are counted beside `RAW` and not folded into it. This is what made removing the fatal for a single failed root defensible: on a single-root host that shape is a quiet date plus a transient find error, and losing the night is the wrong trade.

### Consequences
- A key added to the full-run block needs the same line here, with a real value or an honest zero.
- Do not invent key names here; copy them from the full-run block.
