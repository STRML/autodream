# 0028: How the test suite is organized, sharded and run

Status: accepted · Governs: `.github/ci-scope.sh`, `.review-gate/pretest`

This record holds 3 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: The test suite](#background-the-test-suite)
- [ci-scope prints `web` only when every changed path is known to be web or prose](#ci-scope-prints-web-only-when-every-changed-path-is-known-to-be-web-or-prose)
- [the review-gate pretest runs the unit suites inside a fixed budget and says what it skipped](#the-review-gate-pretest-runs-the-unit-suites-inside-a-fixed-budget-and-says-what-it-skipped)

## Background: The test suite

This section was moved here from the former CLAUDE.md. Its original title: "The test suite".

`tests/run-all.sh` drives the real `run.sh` against `tests/mock-claude.sh` (no network, no model). Mock modes: `good` (default), `l1_incomplete` (worker writes nothing), `l1_flaky` (fails first dispatch per session, succeeds on retry). The suite forces `AUTODREAM_NETCHECK=0 AUTODREAM_RETRY_WAIT=0` and a low `AUTODREAM_L1_ROUNDS` so it never sleeps or hits the network. Runs on macOS and Linux since 2026-10-07: every `date -v`, `date -j -f`, `date -r <epoch>` and `stat -f` goes through `bin/portable.sh` (`pdate_*`, `pstat_*`), which `tests/portable.sh` pins with literal expected values on both. A new script or test that needs one of those calls the helper, never the raw tool: GNU `date -d` also accepts "tomorrow", so the helpers check the shape first. CI split: `tests.yml` runs everything but the launchd suites on Linux; `launchd.yml` runs `install-*`, `scheduler-label`, `autodream-now` and `portable` on macOS only when a launchd file or `portable.sh` changes, plus the whole suite weekly (cron) and on dispatch, in four `/bin/bash` shards (one job outgrew its 20-minute timeout and was cancelled 2026-11-09 and 11-16; `tests/shard.sh` pins that matrix too; cost history in `docs/investigations/2026-11-17-ci-cost.md`), because bash 3.2 and BSD flags are where the silent failures have come from and a Linux-only gate never sees them. `tests.yml` skips docs-only changes with a `paths` list of negations, not `paths-ignore`, because the prompts and `adapters/*/triage.md` and `facts.md` are markdown the suite asserts on: a prompt-only PR (#175) skipped CI under a plain `**.md` ignore and left two tests red on main (#178). A PR whose every path is web dashboard code (or prose markdown) runs only `tests/autodream-web.sh`, on shard 0: `.github/ci-scope.sh` decides from `git diff HEAD^1 HEAD` and prints `full` for any path it has no rule for, and `tests/ci-scope.sh` checks that no code the Linux suite runs names a file it calls web (that is why `web/threads.*` is not web). Pushes to main always run the whole suite. Markdown a test reads goes back into that list as a positive pattern after the `!**.md` line; `skills/autodream/SKILL.md` is in `launchd.yml`'s list for the same reason. Locally, the Linux half runs in docker: copy the repo, run as a non-root user (root defeats every chmod-based test), one fresh copy per suite. It runs `run.sh` under `/bin/bash`, the interpreter its shebang names and launchd uses (3.2 on macOS), not whatever `bash` is first on PATH: under bash 5 an empty array expands to nothing, under 3.2 with `set -u` it is an unbound-variable error, and a warmup that aborted for exactly that reason passed the whole suite until the suite ran the shipped interpreter. Run it after any run.sh/prompt change — it now also invokes the five unit suites (`lib-project`, `preflight`, `adapters`, `adapter-claude`, `adapter-contract`) and folds their counts into its totals, so one command covers everything CI runs. They were workflow-only for a while, which meant a local pre-push run skipped adapter containment, the manifest-name check and the whole contract suite.

**Sharding (2026-10-20).** The suite is slow because it runs `run.sh` hundreds of times, not because any one test is: 64 of about 280 tests take over 5 seconds and they account for half the time (measured per test on a dev machine). So CI runs it as eight shards at once (four until 2026-11-17, when each of the four took 4 to 6 minutes), and a developer can shard it too. `RUNALL_SHARD=i/n bash tests/run-all.sh` runs every n-th test and unit suite, counted in the order they appear in the file, so n shards run the whole suite exactly once; `tests/run-parallel.sh [n]` runs n shards on this machine with a temp dir each and prints one total (about 6 minutes where a sequential run takes 15 to 19, a 3x gain rather than 4x because the shards share one machine; in CI each shard has its own runner; at four shards they finished in about 1.5 minutes in October, where the single job needed 6 to 7, and the suite has roughly doubled since). `RUNALL_LIST=1` prints what a shard would run and runs nothing, and `RUNALL_TIMES=<file>` appends `<seconds> <name>` for every test and suite it runs (CI prints each shard's slowest twelve, which is the data a weighted split would need: shard 0 ran about 65 seconds behind the others in the first CI run, because `prune-worktrees` and `tmp-cleanup` sit in it together with a 46-second test). A new test is added as a `_run test_name` line, never a direct call: `tests/shard.sh` fails on any direct call to a `test_` function (bare, indented, or after `&&`, `||`, `;`, `then` or `do`), because that test would then run in every shard. The same suite also fails when the matrix in `tests.yml` and the `/8` in its run line disagree, since a shard no job runs is an eighth of the suite nobody runs. The unit suites used to run a second time in their own CI step, which `run-all.sh` already made redundant. Round-robin balances well because the slow tests are spread through the file (from the per-test timings, the longest of four shards held 26% of the total, ideal being 25%; at eight, the first CI run's shards took 125 to 184 seconds); weight shards by duration only if that stops being true. Fixtures must not depend on a long `TMPDIR`: one omp chunking assertion parsed a header line that sits 9 characters under the slimmer's 400-character cap, so a `TMPDIR` 9 characters longer cut it mid-JSON. It now checks the line's prefix.

The `threads-state` unit suite is in the registry above. The integration cases in `tests/run-all.sh` pin dropped-thread reporting, catch-up, resume briefs and bounded backfill. Keep shell changes Bash 3.2 compatible, use `bin/portable.sh` for date/stat operations, and keep thread status and membership in one atomic JSONL file, following the single-rename rule documented under question-streaks.

`threads.sh explore` renders and opens `threads.html`, then launches Claude in a right cmux split. It declares only Read and Bash tools with `--permission-mode default`, disables MCP servers, slash commands and hooks, and limits Bash auto-permission to the installed `threads.sh` command. The prompt points to the JSONL index and dashboard without inlining their contents. `test_threads_explore_*` pins the launch arguments, shell quoting and visible cmux failure. cmux types `--command` into the user's login shell, which can be fish, and fish rejects bash's `$'...'` quoting, so `explore` and `resume --launch` write the bash command to a 0600 file that removes itself and hand cmux only `/bin/bash '<file>'`.

`tests/session-window.sh` covers `bin/session-window.sh` directly: the bounds on DST days in New York, London and Sydney (expected values are literals worked out separately, not the `date` call the helper uses), the inclusive start and exclusive end, fractional seconds, torn lines, no-clock files placed by mtime, clocks in a shape it does not read, an out-of-order file, `autodream_meta`, and the `parentId` handling. Its integration side is the `test_window_*` and `test_rebuild_*` cases in `tests/run-all.sh`.

`tests/apply-pins.sh` covers `bin/apply-pins.sh` directly: schema validation, the ledger that stops a rerun double-writing, an unobserved project, a missing `cwd`, a missing `pin-projects.tsv`, and shell-metacharacter payloads in a pin body. `tests/mock-shared-memory.sh` stands in for the `shared-memory` CLI. `SHARED_MEMORY_BIN` is pinned to that mock everywhere the suite runs `apply-pins.sh`, so no test call can write real Mnemopi memory.

The suite pins `AUTODREAM_CONFIG` into its sandbox now that `run.sh` sources the config. Without that pin, a developer whose real config points `AUTODREAM_VAULT_DIR` at a live Obsidian vault would have the test suite writing notes and reports into it. `MOCK_MODE=l2_fail` makes the aggregator write nothing and exit 1, which is how the "don't archive an unread note" guard is tested; pair it with `AUTODREAM_L2_ATTEMPTS=1` so the test doesn't sit through the retry loop.

`tests/x-bookmarks.sh` covers the bookmark fetcher with `curl` shimmed and the queryId cache pre-seeded, so nothing touches X. The bundle-scraping walk is untested on purpose — it runs against a live third party and a fake proves nothing about it. Everything downstream of the HTTP call is pinned hard, because that is where both development bugs lived: the emit came out oldest-first (it trusted file order, which is only chronological within one run), and `mark-read` silently no-opped on every row (`$ids | index(.id)` rebinds `.` to the array before `.id` is read, so it indexed an array with a string). Neither showed up in a smoke test and both would have quietly wasted the feature.

`tests/cookie-cadence.sh` pins `bin/cookie-cadence.sh`'s classification against every header shape the fetcher writes. Fixtures rather than a smoke test, because a misclassification produces a number that looks exactly as authoritative as a correct one.

`tests/review-skip.sh` covers `bin/review.sh`'s skip/launch decision against fixture reports, with an inline mock claude that just touches a marker file — if the marker exists, review.sh reached `exec claude`. It pins `AUTODREAM_CONFIG` to a nonexistent path so the host's own config (`AUTODREAM_TRIAGE_SURFACE=cmux`) can't leak in and spawn a real workspace mid-test. Run it after any review.sh change, and after changing PROMPT.md's Open-questions marker contract.

`tests/review-cmux.sh` covers `bin/review.sh`'s `AUTODREAM_TRIAGE_SURFACE=cmux` launch path (the morning review job's workspace popup) with a mock cmux binary — no real workspace ever spawns. It pins the same-day dedup marker contract against the report: first trigger opens and stamps a confirmed token (claim dir + `.confirmed` sibling), a same-day same-digest trigger is deduped, `--force` bypasses the marker, a failed create releases the claim and exits non-zero, the marker binds to the report content digest (a rebuilt report opens again), stale claims and tokens >14 days get reaped, a confirmed marker survives the reclaim grace window while an abandoned (unconfirmed, old) claim is reclaimed and a young unconfirmed claim suppresses concurrent triggers, a headless (non-TTY) run with missing cmux fails non-zero instead of falling back to a headless inline claude, and a logs dir that can't be created fails loudly. Run it after any change to the cmux branch of review.sh.

## ci-scope prints `web` only when every changed path is known to be web or prose

Status: accepted · Date: 2026-11-17 · Code: `.github/ci-scope.sh`

### Context

A PR that changes only the web dashboard does not need the whole suite, so `tests.yml` asks `.github/ci-scope.sh` whether it may run only `tests/autodream-web.sh`. A wrong `full` costs a few minutes. A wrong `web` merges a change the suite would have caught. `tests/ci-scope.sh` pins every rule.

Plain `git diff --name-only` reports a rename by its new path alone, so moving `bin/run.sh` into `web/` would read as a web-only change.

Some paths look like web code and are not:

| Path | Why it is not web |
|---|---|
| `web/threads.*` | `bin/threads-render.py` inlines them into the page `run-all.sh` asserts on |
| `bin/autodream-web` | the shell launcher `install.sh` links |
| `tests/autodream-web.sh`, `.github/ci-scope.sh`, any workflow | they change how tests run |
| markdown under `prompts/`, `adapters/` or `skills/` | the suites assert on what it says (#178: a prompt-only PR skipped CI and left two tests red on main) |

### Decision

Invocations: `ci-scope.sh BASE HEAD` diffs two revisions with `--no-renames` and sends the changed paths to stderr; `ci-scope.sh < paths` reads one path per line. It prints `web` only when every path belongs to the web dashboard (or is prose markdown) and at least one is web code. Anything else prints `full`: a path with no rule, a path containing `..`, no paths at all, a failed `git diff`.

### Consequences

A new top-level directory needs a rule only if it should ever be web. The default is `full`. Adding a web path means adding a case and a row in `tests/ci-scope.sh`, which also checks that no code the Linux suite runs names a file the selector calls web. See `tests-ci-scope-and-shard-guards`.

## the review-gate pretest runs the unit suites inside a fixed budget and says what it skipped

Status: accepted · Date: 2026-10-05 · Code: `.review-gate/pretest`

### Context

The review gate (`~/.claude/scripts/review-gate-lib.sh`, `rg_pretest`) runs this script before a review round, outside the headless lane's classifier, and inlines the output into the review prompt, which keeps only the last 150 lines. The block a reviewer reads is therefore the `PRETEST SUMMARY` at the end. The harness kills the script at 900 seconds.

`tests/run-all.sh` takes over 10 minutes, so it cannot run here; it is run by hand before merging a `run.sh` change. Mocks and `replay.sh` (needs arguments) are not suites.

`tests/adapter-claude.sh` needs a usable `ps` and `tests/review-cmux.sh` needs a pty. The Claude Code sandbox denies both, and both pass outside it.

### Decision

The script runs every `tests/*.sh` except `mock-*`, `replay.sh` and `run-all.sh`, with a total budget of 800 seconds and at most 120 seconds per suite. A suite past its cap is marked `TIMEOUT` and the rest still run. Suites left when the budget is spent are listed as `NOT RUN`.

The two environment-bound suites are probed for the capability they need (`can_ps`, `can_pty`) and not for the sandbox, so they run wherever the capability exists and are listed as `skipped` otherwise. `can_ps` is the same test as `ps_usable` in `tests/adapter-claude.sh`.

### Consequences

A skipped suite did not run in the review lane, and the summary line says each passes outside the sandbox. If the suite count grows past the budget, the tail silently moves to `NOT RUN`, so watch that line. Changing the 800 and 900 numbers means changing the harness timeout too.
