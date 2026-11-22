# CLAUDE.md — cc-autodream

This file is the map. Read it before changing `bin/run.sh`, the prompts or a launchd file. The README is the user-facing pitch. Every decision and incident behind a rule lives in `docs/adr/` (index: `docs/adr/README.md`); each area below names its records.

## What it is

A nightly two-layer pipeline. It reads yesterday's Claude Code and OMP session transcripts and writes a ranked report plus a few pins for the shared Mnemopi memory store.

```
sessions ─► run.sh ─► L1: one call per session ─► findings/DATE/<hash>.json
                      (claude-haiku-5-5, effort high)      │
                                                  rollup.sh (runner counts)
                                                           ▼
            dreams/DATE.md ◄─ run.sh ◄─ L2: one call, tools Glob + Read, report on stdout
            pins, threads.jsonl, notification
```

- Layer 1 prompt: `prompts/SESSION_TRIAGE.md`. Layer 2 prompt: `prompts/PROMPT.md`, with `prompts/L2_SYSTEM.txt` as the system prompt.
- `bin/run.sh` orchestrates both layers and everything around them. Legacy `MEMORY.md` memory is retired: autodream writes no `MEMORY.md` pins and runs no `claude-memory gc` (`docs/plans/2026-09-15-mnemopi-pins.md`).
- State lives under `$AUTODREAM_DIR` (default `~/.claude/autodream/`); reports go to `~/.claude/dreams/`. The file-by-file inventory is in [ADR 0001](docs/adr/0001-runner-lifecycle.md#background-where-state-lives).
- Scripts and prompts are symlinked into `~/.claude/autodream/` by `install.sh`, so editing the repo takes effect at once. The installed launchd job is `com.samuelreed.autodream`.

## Run it

```bash
~/.claude/autodream/run.sh 2026-05-29                       # process a date
AUTODREAM_FORCE=1 ~/.claude/autodream/run.sh 2026-05-29     # rebuild despite a report
~/.claude/autodream/autodream-now.sh [DATE] [--force] [--watch] [--dry-run]
```

- Prefer `autodream-now.sh` for a run you start from an agent: launchd owns the process, so a 10-minute task cap cannot kill it. Poll `dreams/<date>.md` for the `autodream:open-questions=` marker, or use `--watch`.
- For a clean rebuild, delete that date's `findings/` directory and report first; otherwise idempotency reuses old findings.
- Env knobs are in `docs/run-knobs.md` and the README.

## Test it

```bash
npm ci                                                   # once, node 20+: the ratchet and the lint need typescript and oxlint
TMPDIR=/tmp/adp1 /bin/bash tests/run-all.sh              # the whole suite, one shard
TMPDIR=/tmp/adp1 /bin/bash tests/run-parallel.sh 4       # four shards on this machine
RUNALL_SHARD=i/n RUNALL_LIST=1 bash tests/run-all.sh     # list what a shard would run
```

- `tests/run-all.sh` drives the real `run.sh` against `tests/mock-claude.sh`: no network, no model. It also runs the unit suites, so one command covers what CI runs.
- Point `TMPDIR` outside every checkout and keep it short. Under the Claude Code sandbox `git init` fails and the changelog tests then run git against the enclosing repo; `xargs -I {}` refuses 255-byte arguments.
- Add a test as a `_run test_name` line, never a direct call (`tests/shard.sh` fails on one). Docs-only changes still run the comment ratchet.
- Run the Linux half in docker as a non-root user, one fresh copy per suite. Run `run.sh` under `/bin/bash`, the interpreter its shebang names.
- The Claude Code sandbox denies writes under `~/.claude/`, including `rm` of symlinks; those operations need the sandbox off.
- Details and the per-suite decisions: [ADR 0028](docs/adr/0028-test-suite-organization.md).

## Rules

1. **Bash 3.2.** `run.sh` runs under macOS's `/bin/bash` 3.2. No associative arrays, no `${a[@]}` on a possibly empty array under `set -u`, no `mapfile`. Every `date -v`, `date -j -f`, `date -r <epoch>` and `stat -f` goes through `bin/portable.sh` (`pdate_*`, `pstat_*`) so Linux CI passes ([ADR 0012](docs/adr/0012-shared-shell-helpers.md)).
2. **No new comments.** Code carries its meaning in names and small functions. A decision the code cannot show goes in `docs/adr/`. `tests/comment-ratchet.sh` fails a PR that raises a file's comment count above `.comment-baseline`; tighten it with `tests/comment-ratchet.sh --update` (it refuses to raise a count without `--allow-increase` and a reason in the PR). Counter and trades: [ADR 0027](docs/adr/0027-comment-ratchet.md).
3. **The lean-query pattern, never `--bare`.** Both layers call `claude --print` with `--no-session-persistence`, `--tools Read Write` (L1) or `Glob Read` (L2), `--disable-slash-commands`, `--strict-mcp-config`, `--settings '{"disableAllHooks":true}'`, `--permission-mode bypassPermissions` and the env `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1`. `--bare` and `CLAUDE_CODE_SIMPLE=1` break OAuth login. L1 uses `--system-prompt` and `--effort` ([ADR 0003](docs/adr/0003-adapters-and-engines.md#background-how-claude-is-invoked--the-lean-query-pattern-do-not-use---bare)).
4. **A worker is untrusted.** L1 holds Write and reads untrusted transcripts, so the runner is the only writer of anything it trusts: it snapshots authorization lists, the source map and ledgers before the first model call, keeps them in memory, and takes each answer out of a private stage ([ADR 0006](docs/adr/0006-l1-confinement.md)). L2 holds Glob and Read only and answers on stdout. Never inline a long report into a system prompt; never launch intent-carrying work with a one-word prompt ([ADR 0022](docs/adr/0022-review-and-triage.md)).
5. **Fail closed, and say so.** A measurement that could not be taken is unknown, never zero (`overlap_measured`, `stats_sidecars_unparseable`, `remote_mirror_bytes_<label>: unknown`). A run killed mid-flight is the normal failure, so recovery paths come first ([ADR 0010](docs/adr/0010-rollup-and-run-stats.md), [ADR 0001](docs/adr/0001-runner-lifecycle.md)).
6. **State that changes together goes in one file, written with one rename**, in the destination directory. Two files have an order of writes to get wrong. `question-streaks.sh` and `threads.sh` lock with `flock(2)` through `bin/lib-flock.sh` ([ADR 0020](docs/adr/0020-question-streaks.md), [ADR 0012](docs/adr/0012-shared-shell-helpers.md)). The run lock and the remote-sync lock are `flock(2)` locks held by a holder process, and their lock directory only reports the owner ([ADR 0001](docs/adr/0001-runner-lifecycle.md), [ADR 0015](docs/adr/0015-remote-sync.md)). The X browser lock is still a reclaimable `mkdir` lock ([ADR 0019](docs/adr/0019-x-bookmarks.md)).
7. **Credentials never go in `argv`**; they go in a 0600 `curl --config` file in a per-run temp dir ([ADR 0019](docs/adr/0019-x-bookmarks.md)).
8. **L2 never lists a directory.** Glob stops at 200 entries and a findings dir holds thousands, so PROMPT.md names every file L2 reads by exact path. A new side file L2 needs gets a named line there, not a glob ([ADR 0010](docs/adr/0010-rollup-and-run-stats.md)).
9. **A review finding is a class, not a site.** Before fixing a pattern in one script, grep for it in the others.
10. **Shell traps that passed a smoke test and failed silently** are listed with their fixes in [ADR 0017](docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent). The L1 worker body is a single-quoted `bash -c`: a `'` in a comment there breaks quoting while `bash -n` still passes.

## Reviewing changes

Almost everything here is shell, and a shell bug fails silently on a nightly cron nobody watches. `/code-review` is a first pass, not the gate. Before merging a change to `run.sh`, `bin/*.sh`, `install.sh`, the launchd plists or the prompts, also run `/debate:run tight` (Codex + Gemini + DeepSeek) so at least one seat does not share Claude's blind spots. PR #37 had ten Claude verifiers quote `file:line` they had never read; more Claude seats do not catch that, a different vendor does. DeepSeek direct retains prompts, which is fine for this public repo; for private code swap the seat. Read every cited `file:line` before acting on a verdict.

## Areas and their decision records

Each record merges the decisions of one area, one section per decision, plus a `Background` section where this file used to carry the narrative.

| Area | Record |
|---|---|
| Runner lifecycle: idempotency guard, locks, sleep resilience, config sourcing, state layout | [ADR 0001](docs/adr/0001-runner-lifecycle.md) |
| Sessions: roots, enumeration, the report-day window (#113), accounting | [ADR 0002](docs/adr/0002-session-enumeration.md) |
| Adapters and engines: who runs L1 and L2, per-harness prompts | [ADR 0003](docs/adr/0003-adapters-and-engines.md) |
| The OMP adapter: linearize, stats, skills inventory, `l1-stage-env` | [ADR 0004](docs/adr/0004-omp-adapter.md) |
| L1 workers: dispatch, input, validation, retry, timeouts, circuit breaker | [ADR 0005](docs/adr/0005-l1-workers.md) |
| L1 confinement: sandbox-exec and bwrap, the stage, the write list | [ADR 0006](docs/adr/0006-l1-confinement.md) |
| Long sessions: chunked triage | [ADR 0007](docs/adr/0007-l1-chunked-triage.md) |
| Failure classes, network health, deferral of a date | [ADR 0008](docs/adr/0008-failure-and-network.md) |
| L2: stdout grammar, sentinels, delivery, stale and partial copies | [ADR 0009](docs/adr/0009-l2-aggregation.md) |
| Rollup, run-stats and the measured-or-unknown rule | [ADR 0010](docs/adr/0010-rollup-and-run-stats.md) |
| Self-pollution: workers must not become sessions | [ADR 0011](docs/adr/0011-self-pollution.md) |
| Shared helpers: `lib-flock.sh`, `lib-path-state.sh`, `portable.sh` | [ADR 0012](docs/adr/0012-shared-shell-helpers.md) |
| Memory pins | [ADR 0013](docs/adr/0013-pins.md) |
| Upstream changelog watch | [ADR 0014](docs/adr/0014-changelog-watch.md) |
| Remote host sync (#226-#230) | [ADR 0015](docs/adr/0015-remote-sync.md) |
| Report scripts | [ADR 0016](docs/adr/0016-report-scripts.md) |
| Operator notes and the vault inbox | [ADR 0017](docs/adr/0017-operator-notes-and-vault.md) |
| Focus tags and the `mods/autodream-focus` mod, OMP and Codex writers | [ADR 0018](docs/adr/0018-focus-tags.md) |
| X bookmarks, including the browser path (#166) | [ADR 0019](docs/adr/0019-x-bookmarks.md) |
| Open questions that never get answered (`question-streaks.sh`) | [ADR 0020](docs/adr/0020-question-streaks.md) |
| Dropped threads | [ADR 0021](docs/adr/0021-dropped-threads.md) |
| Review, triage and the `mods/autodream-band` mod | [ADR 0022](docs/adr/0022-review-and-triage.md) |
| Install, scheduler label ownership, on-demand runs | [ADR 0023](docs/adr/0023-install-and-scheduling.md) |
| Notifications | [ADR 0024](docs/adr/0024-notifications.md) |
| Local web dashboard (`autodream-web`) | [ADR 0025](docs/adr/0025-web-dashboard.md) |
| Worktree and branch pruning (`prune-worktrees.sh`) | [ADR 0026](docs/adr/0026-worktree-pruning.md) |
| Tests and CI | [ADR 0028](docs/adr/0028-test-suite-organization.md) and the numbered `tests-*` records in `docs/adr/README.md` |

Decision records are also reachable from code: every deleted comment is mapped to its record in `docs/adr/_ledger-*.tsv` (`file`, `line`, `class`, `target`).

## One repo, no sibling

omp-autodream is archived and its code lives here, so there is one copy of each helper and nothing to compare against ([ADR 0001](docs/adr/0001-runner-lifecycle.md#background-one-repo-no-sibling-to-drift-from)).

## Gotchas (host environment)

- The Claude Code sandbox denies writes under `~/.claude/` (including `rm` of symlinks and findings); those operations need the sandbox disabled.
- Subagent transcripts live in `projects/.../<session>/subagents/agent-*.jsonl` and are legitimate sessions to triage, not self-pollution.
- `claude --print` worker calls run from the isolated work dir (`$AUTODREAM_DIR/work`), so any AI-title stub lands in a bucket the runner owns and wipes ([ADR 0011](docs/adr/0011-self-pollution.md)).
