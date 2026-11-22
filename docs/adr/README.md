# Architecture decision records

One record per decision area, numbered in reading order: the core pipeline first (0001-0013), then the features (0014-0026), then the test suite (0027-0050).

Each record opens with its scope and a list of its decisions. Every decision is its own section with a status, a date, the code it governs, and the context, decision and consequences. A section named "Background" carries the narrative that used to live in `CLAUDE.md`: the incident, the measurement, and why the rule exists.

## Index

| No. | Decision area | Governs |
|---|---|---|
| 0001 | [The runner: lifecycle, guards, locks and config](0001-runner-lifecycle.md) | `bin/run.sh`, `tests/preflight.sh`, `bin/preflight.sh`, `bin/autodream-note.sh` and 2 more |
| 0002 | [Sessions: roots, enumeration, the report day and accounting](0002-session-enumeration.md) | `bin/run.sh`, `tests/session-window.sh`, `tests/lib-project.sh`, `bin/session-window.sh` and 3 more |
| 0003 | [Adapters and engines: who runs L1 and L2](0003-adapters-and-engines.md) | `bin/run.sh`, `bin/adapters.sh`, `adapters/claude/adapter.sh`, `adapters/_fixture/adapter.sh` and 1 more |
| 0004 | [The OMP adapter](0004-omp-adapter.md) | `adapters/omp/adapter.sh`, `adapters/omp/skills-inventory.sh`, `adapters/omp/linearize.sh`, `adapters/omp/stats.sh` |
| 0005 | [L1 workers: dispatch, input, validation and retry](0005-l1-workers.md) | `bin/run.sh` |
| 0006 | [L1 confinement: the sandbox, the stage and what a worker may write](0006-l1-confinement.md) | `bin/run.sh`, `bin/l1-confine.sh`, `adapters/claude/adapter.sh` |
| 0007 | [Long sessions: chunked triage](0007-l1-chunked-triage.md) | `bin/slim-transcript.sh`, `tests/merge-chunks.sh`, `bin/run.sh`, `bin/chunk-transcript.sh` and 1 more |
| 0008 | [Failure classes, network health and deferral](0008-failure-and-network.md) | `bin/run.sh`, `bin/failure-class.sh`, `bin/err-cause.sh` |
| 0009 | [L2: the aggregator, the report and its delivery](0009-l2-aggregation.md) | `bin/run.sh`, `bin/report-format.sh`, `bin/citation-check.sh`, `bin/dream-grounding.sh` |
| 0010 | [Counting and self-audit: rollup, run-stats and the measured-or-unknown rule](0010-rollup-and-run-stats.md) | `bin/run.sh`, `bin/rollup.sh`, `bin/oversized-gate.sh`, `bin/session-stats.sh` and 2 more |
| 0011 | [Self-pollution: workers must not become sessions](0011-self-pollution.md) | `bin/run.sh`, `bin/prune-self-sessions.sh` |
| 0012 | [Shared shell helpers: flock, path state and portable date and stat](0012-shared-shell-helpers.md) | `bin/lib-flock.sh`, `bin/portable.sh`, `bin/lib-path-state.sh` |
| 0013 | [Memory pins: proposal, authorization and application](0013-pins.md) | `bin/run.sh`, `bin/apply-pins.sh` |
| 0014 | [Upstream changelog watch](0014-changelog-watch.md) | `bin/run.sh` |
| 0015 | [Remote host sync](0015-remote-sync.md) | `bin/run.sh`, `bin/remote-sync.sh` |
| 0016 | [Report scripts: operator-requested commands](0016-report-scripts.md) | `bin/report-scripts.sh`, `bin/run.sh`, `bin/stop-check-counts.sh` |
| 0017 | [Operator notes and the vault inbox](0017-operator-notes-and-vault.md) | `bin/run.sh`, `bin/vault-notes.sh` |
| 0018 | [Focus tags: marking a turn for the next run](0018-focus-tags.md) | `bin/autodream-focus.sh`, `extensions/omp/autodream-focus.ts`, `extensions/omp/focus-core.ts`, `bin/vault-notes.sh` and 4 more |
| 0019 | [X bookmarks as idea fuel](0019-x-bookmarks.md) | `bin/x-bookmarks.sh`, `bin/run.sh`, `bin/cookie-cadence.sh` |
| 0020 | [Open questions that never get answered](0020-question-streaks.md) | `bin/question-streaks.sh`, `bin/run.sh`, `bin/session-window.sh` |
| 0021 | [Dropped threads index](0021-dropped-threads.md) | `bin/threads.sh` |
| 0022 | [Review and triage of open questions](0022-review-and-triage.md) | `bin/review.sh`, `mods/autodream-band/hooks/lib.ts`, `mods/autodream-band/hooks/register.tsx`, `bin/triage-candidates.sh` and 5 more |
| 0023 | [Install, scheduling and on-demand runs](0023-install-and-scheduling.md) | `install.sh`, `bin/autodream-now.sh`, `tests/autodream-now.sh`, `bin/scheduler-label.sh` and 7 more |
| 0024 | [Notifications and banners](0024-notifications.md) | `bin/notify.sh`, `bin/make-notifier.sh` |
| 0025 | [The local web dashboard](0025-web-dashboard.md) | `docs/demo/demo-fetch.js`, `tests/autodream-web-browser.py`, `bin/autodream-web.py`, `bin/autodream_web_data.py` and 2 more |
| 0026 | [Worktree and branch pruning](0026-worktree-pruning.md) | `bin/prune-worktrees.sh` |
| 0027 | [No new comments: the ratchet and where decisions go](0027-comment-ratchet.md) | `tests/comment-ratchet.sh`, `bin/comment-count.sh`, `.comment-baseline` |
| 0028 | [How the test suite is organized, sharded and run](0028-test-suite-organization.md) | `tests/run-all.sh`, `tests/shard.sh`, `.github/ci-scope.sh`, `.review-gate/pretest` |
| 0029 | [adapter-claude suite: trap, process group and SIGTERM handling](0029-tests-adapters-claude-suite-process-control.md) | `tests/adapter-claude.sh` |
| 0030 | [adapter suites: atomic writes, rejects, contract and the pinned L1 argv](0030-tests-adapters-fixtures-and-contract.md) | `tests/adapter-contract.sh`, `tests/adapters.sh`, `tests/adapter-claude.sh` |
| 0031 | [adapter-omp suite: provenance, tool calls, skill reads and the overlay](0031-tests-adapters-omp-stats-and-overlay.md) | `tests/adapter-omp.sh` |
| 0032 | [ci-scope and shard guard suites](0032-tests-ci-scope-and-shard-guards.md) | `tests/ci-scope.sh`, `tests/shard.sh`, `tests/run-parallel.sh` |
| 0033 | [chunk-transcript, notes-path, preflight, session-window, report-format and report-scripts suites](0033-tests-data-helper-suites.md) | `tests/notes-path.sh`, `tests/run-all.sh`, `tests/report-scripts.sh`, `tests/session-window.sh` and 5 more |
| 0034 | [install, scheduler-label and prune-worktrees suites](0034-tests-install-and-scheduler-suites.md) | `tests/scheduler-label.sh`, `tests/prune-worktrees.sh`, `tests/install-dir.sh`, `tests/install-path.sh` |
| 0035 | [l1-confine suites: sandbox skips, WAL fixture and the real-engine check](0035-tests-l1-confine-suites.md) | `tests/l1-confine-real.sh`, `tests/l1-confine.sh` |
| 0036 | [lib-project and lib-store suites must not pass vacuously](0036-tests-lib-project-and-store-checks.md) | `tests/lib-project.sh`, `tests/lib-store-unchanged.sh` |
| 0037 | [the mock claude and mock shared-memory contracts](0037-tests-mocks.md) | `tests/mock-claude.sh`, `tests/mock-shared-memory.sh`, `tests/dream-triage.sh` |
| 0038 | [replay and rollup suites](0038-tests-replay-and-rollup-suites.md) | `tests/replay.sh`, `tests/rollup.sh` |
| 0039 | [review.sh suites: isolation, skip fixtures, cmux marker and the questions-only prompt](0039-tests-review-suites.md) | `tests/review-cmux.sh`, `tests/review-prompt.sh`, `tests/review-skip.sh` |
| 0040 | [run-all: changelog and notify fixtures](0040-tests-run-all-changelog-and-notify-fixtures.md) | `tests/run-all.sh` |
| 0041 | [run-all: tests that keep failures visible](0041-tests-run-all-failure-visibility-tests.md) | `tests/run-all.sh` |
| 0042 | [run-all: fixtures reproduce the real on-disk shapes and dates](0042-tests-run-all-fixtures-mirror-real-shapes.md) | `tests/run-all.sh` |
| 0043 | [run-all: focus, chunking and threads fixtures](0043-tests-run-all-focus-chunking-and-threads-fixtures.md) | `tests/run-all.sh` |
| 0044 | [run-all: harness, env and engine isolation, and how the suite counts failures](0044-tests-run-all-harness-and-engine-isolation.md) | `tests/run-all.sh` |
| 0045 | [run-all: install, upgrade and adapter-enablement fixtures](0045-tests-run-all-install-and-adapter-fixtures.md) | `tests/run-all.sh` |
| 0046 | [run-all: pins, report lifecycle, citations and question-streak fixtures](0046-tests-run-all-pins-report-and-streak-fixtures.md) | `tests/run-all.sh` |
| 0047 | [run-all: retry, network, timeout and L2 tests prove effects, not exit codes](0047-tests-run-all-retry-network-timeout-and-l2-fixtures.md) | `tests/run-all.sh` |
| 0048 | [slim-transcript suite: assertions that can fail and discriminating fixtures](0048-tests-slim-transcript-suite.md) | `tests/slim-transcript.sh` |
| 0049 | [tmp, portable and pty test helpers](0049-tests-tmp-portable-and-pty-helpers.md) | `tests/lib-tmp.sh`, `tests/tmp-cleanup.sh`, `tests/portable.sh`, `tests/with-pty.py` and 1 more |
| 0050 | [x-bookmarks suite: shim boundary, fixture traps and the browser watchdog](0050-tests-x-bookmarks-suite.md) | `tests/x-bookmarks.sh` |

## Adding a decision

1. Find the record whose area owns the code you are changing. A new area gets the next free number and a row above.
2. Append a section: title, `Status: accepted · Date: YYYY-MM-DD · Code: ...`, then Context, Decision, Consequences. Record the incident or measurement, not the diff.
3. Do not leave the reason in a code comment. `tests/comment-ratchet.sh` fails a PR that raises a file's comment count above `.comment-baseline`.

## Ledgers

`_ledger-*.tsv` maps every comment the audit deleted to where its reason lives. Columns are `file`, `line` (in the file before the audit), `class` and `target`.

| Class | Target |
|---|---|
| `decision` | the record and section that hold the decision (a link into this directory), or `docs/run-knobs.md` for a knob description |
| `excuse` | the issue that tracks the hack the comment excused |
| `tautology`, `stale`, `help` | `-`: the comment repeated the code (`tautology`), was wrong (`stale`), or was a help header the script now prints from `usage()` (`help`) |
