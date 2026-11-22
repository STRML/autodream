# 0026: Worktree and branch pruning

Status: accepted · Governs: `bin/prune-worktrees.sh`, `bin/portable.sh`, `portable.sh`, `bin/run.sh`

This record holds 5 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [a fixed list of keep rules overrides any proof that the work landed](#a-fixed-list-of-keep-rules-overrides-any-proof-that-the-work-landed)
- [no removal without a write-ahead ledger record and a pinned tip](#no-removal-without-a-write-ahead-ledger-record-and-a-pinned-tip)
- [no call the pruner makes can hang the nightly run](#no-call-the-pruner-makes-can-hang-the-nightly-run)
- [pruning is opt-in, and the helper never returns a failure to run.sh](#pruning-is-opt-in-and-the-helper-never-returns-a-failure-to-runsh)
- [a branch is deleted only on exact proof that the work landed](#a-branch-is-deleted-only-on-exact-proof-that-the-work-landed)

## a fixed list of keep rules overrides any proof that the work landed

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (`sweep_worktree`, `sweep_branches`, `is_protected`, `recent_edit`, `rebase_branch`, `ignored_beyond_build`, `prune_stale_worktrees`, `sweep_repo`)

### Context

A proof that the PR merged (see `rest-prune-worktrees-proof-before-delete`) says the branch's commits are safe. It says nothing about what else is in the worktree directory, or whether someone is using it. The nightly run removes a directory and a remote branch, so each way a finished-looking branch can still be in use became a keep rule. The report gives the reason for every keep (`worktree-prune.tsv` and `.md`), and the README has the user-facing table.

### Decision

A keep rule applies whatever else is true. `sweep_worktree` tests them in this order.

| Reason | Why it exists |
|---|---|
| `unmanaged-path` | A worktree outside `.claude/worktrees` and `.worktrees` was not made by a session, so it is not ours to remove. The repo path is made physical (`cd -P`, `pwd -P`) before sweeping. Git prints physical worktree paths, so under a symlinked parent (`/tmp`, an iCloud path) the managed-path check would reject every worktree. |
| `locked` | `git worktree lock` is an explicit request to leave it alone. |
| `protected` | main, master, develop, dev, development, trunk, staging, stage, production, prod, next, canary, gh-pages, `release*`, `v<digit>*`, the default branch, and `AUTODREAM_PRUNE_PROTECT` (colon-separated globs). |
| `recent` | A file in the worktree or its gitdir changed inside the grace window (default 12 hours, `AUTODREAM_PRUNE_GRACE_MIN`). This also covers a session still running there. The file search skips `.git`, `node_modules` and `target`, so a build does not keep a worktree alive; the gitdir is searched on its own, so a commit, fetch or checkout counts. A gitdir that cannot be resolved counts as recent. |
| `rebase-or-bisect` | A rebase or bisect is in progress. `rebase_branch` also names the branch being rebased, so the branch sweep skips it although HEAD is detached. |
| `submodules` | A `.gitmodules` means the submodules' git data lives in the worktree's gitdir, which deletion would destroy. |
| `dirty` | Uncommitted or untracked files (`status --porcelain --untracked-files=all`). A failed `status` is kept as `status-failed`. |
| `ignored-files` | Ignored files other than build output (`node_modules target dist build .next __pycache__ .venv`) and no Trash to put them in. Files such as `.env` exist nowhere else, and `git worktree remove` deletes them for good. |
| `trash-failed` | `trash` exists and failed, so the directory would not be recoverable. The step stops there and does not fall back to deleting it. |
| `open-pr`, `base-of-open-pr`, `base-of-pr` | See the proof ADR. |
| `gh-unavailable` | `gh` is missing, logged out, or failed for the repo, or the open-PR list reached `AUTODREAM_PRUNE_OPEN_LIMIT` (default 200). At the limit the list may be truncated and an open PR could be missing, so the repo is kept whole instead of trusting a partial list. Without `gh` there is no proof. |
| `time-budget`, `cap` | `AUTODREAM_PRUNE_BUDGET_SEC` ran out, or `AUTODREAM_PRUNE_MAX` removals already happened this run. Both limit the damage of one bad night. |

The branch sweep skips any branch that a worktree has checked out, or that is being rebased (`checked`), and any branch younger than the grace window.

`prune_stale_worktrees` forgets worktree records whose directory is gone. When the parent directory of any such record is also missing, it leaves all of them alone (`volume-missing`), because that looks like an unmounted volume and not a deleted worktree.

### Consequences

The list is the safety contract. The README table and `tests/prune-worktrees.sh` move with it. A new rule needs a test that pins a KEEP. Do not turn a keep into a removal because the proof is strong: the proof is about the commits, and the keep rules are about everything else in the directory.

## no removal without a write-ahead ledger record and a pinned tip

Status: accepted · Date: 2026-10-14 · Code: `bin/prune-worktrees.sh` (`ledger`, `lstep`, `shq`, `recover_cmds`, `remove_item`)

### Context

The pruner deletes remote branches, and a wrong delete cannot be undone by git alone. Commit `46c1fb6` (2026-10-14) added a ledger so every removal can be reversed, and `299b79c` (the same day) closed a hole in it: after the branch and the worktree are gone, nothing else keeps a squash-merged tip reachable. `git gc` would prune it and the recorded undo commands would fail.

### Decision

Every real run appends to one file that is never rewritten, `AUTODREAM_PRUNE_LEDGER` (default `~/.claude/autodream/prune-ledger.tsv`). A run opens with `run-start` and closes with `run-end`. Per removal, `remove_item` writes an `intent` line before it touches anything, then one line per step, then `complete`. Columns: time (UTC), run id, event, repo, owner/repo, branch, local tip, remote tip before the delete, worktree path, detail (the proof: PR URL, state, head, base), recover. A dry run writes nothing.

The `recover` column holds the exact commands that put the branch back, local and remote:

```
git -C <repo> branch <branch> <tip> ; git -C <repo> push origin <tip>:refs/heads/<branch>
```

The push half appears only when the branch existed on the remote. A worktree directory goes to the Trash under its own name, and the ledger says so.

- **No log, no delete.** If the ledger cannot be written (`run-start` fails, or the `intent` line fails), nothing is removed: `ledger-unwritable` or `ledger-write-failed`. The intent is written before the first change, so a crash leaves the undo on disk.
- **Pin first.** `remove_item` creates `refs/prune-ledger/<run id>/<branch>` at the tip before any change, with an empty old value so the pin is create-only and an existing pin of that name is never overwritten. The pin is never removed. A failed pin means nothing is removed (`pin-failed: no safe undo, no delete`). If the intent line then fails, the pin is deleted again, because nothing was changed.
- **One append, one line.** `ledger` returns 1 on a failed append. A tab or newline inside a field would shift the columns, so both become spaces. `lstep` records a failed step append in `LBAD`, so the final `complete` row and the report say `ledger-incomplete`. The intent line still holds the undo.
- **The recover commands are quoted by `shq`**, which wraps a string in single quotes. `printf %q` prints `$'..'` for some names, which fish cannot read. The commands run unchanged in bash, zsh and fish.
- **An interrupted run is recorded.** The watchdog TERM handler writes an `interrupted` line for the removal in flight, naming what to check (worktree, remote branch, local branch). See `rest-prune-worktrees-no-call-can-hang-the-night`.

### Consequences

Pins cost a few bytes each and accumulate by design. The README gives the command that deletes them once undo is no longer needed. Changing the column order breaks the recover instructions in the README and the assertions in `tests/prune-worktrees.sh` (`ledger_row`, `ledger_col`). Do not add a removal path that skips `remove_item`, and do not move the pin or the intent write after the first change.

## no call the pruner makes can hang the nightly run

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (`on_term`, the watchdog subshell, `tmo` from `bin/portable.sh`)

### Context

The pruner makes network calls (`gh`, `git fetch`, `git push`) and runs `trash` inside the nightly run. One call that waits for a password, a dead host, or a stuck filesystem would stall the whole run and the night's report. Commit `1075a87` (2026-10-13) bounded every call. docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command (under "A watchdog takes its own `sleep` with it") records the later fix to the watchdog subshell here and in two sibling scripts.

### Decision

- **Prompts are off.** `GIT_TERMINAL_PROMPT=0` and `GH_PROMPT_DISABLED=1` are exported. Without a tty (launchd) ssh and git cannot prompt either. `GIT_HTTP_LOW_SPEED_LIMIT=1000` and `GIT_HTTP_LOW_SPEED_TIME=$CALL_SEC` make a slow transfer abort on its own.
- **Every network call and `trash` runs under `tmo "$CALL_SEC"`** (`AUTODREAM_PRUNE_CALL_SEC`, default 60). `tmo` uses `timeout`, `gtimeout`, or a built-in watchdog when neither exists. The remote delete and the fetch get twice that.
- **A hard cap covers everything else.** A watchdog subshell sleeps `AUTODREAM_PRUNE_BUDGET_SEC` plus `AUTODREAM_PRUNE_KILL_SLACK` (defaults 1200 and 120 seconds) from the start, then sends TERM to the script. `on_term` kills the children (`pkill -P`), writes an `interrupted` ledger line if a removal was in flight, adds a `skipped` row (`watchdog: the run outlasted its time cap`), writes the report, and exits 0.
- **The watchdog kills the children right after the TERM.** Bash runs a trap only after its foreground child exits, so a script blocked in a hung child would never reach `on_term` on its own.
- **The watchdog subshell traps TERM and kills its own `sleep`**, so ending the watchdog ends the sleep (otherwise the sleep lingers until its timeout, and a watchdog woken late could signal a recycled pid).
- **The budget is also checked between steps** (`budget_ok`), which turns an overrun into `time-budget` rows before the hard cap is needed.
- **A bad number in any `AUTODREAM_PRUNE_*` knob exits 0** with a message, never a non-zero status.

### Consequences

The script exits 0 on every path once it has an out-dir, because a pruning problem must not cost the night's report; `run.sh` relies on that. A new external call must go through `tmo`. A new loop must check `budget_ok`. If `tmo` or the watchdog changes, run `tests/prune-worktrees.sh` and `tests/portable.sh`, since the TERM path is the only thing standing between a hung host and a missing report.

## pruning is opt-in, and the helper never returns a failure to run.sh

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (argument handling, `finish`, sourcing of `portable.sh`), `bin/run.sh` (`PRUNE_WORKTREES`)

### Context

The step deletes things on a remote and in other repos, so a fresh install must not do it. It also runs unattended after the report's inputs are gathered, so a failure in it must not cost the night's report. The helper is symlinked into `~/.claude/autodream/` by `install.sh`.

### Decision

- **Opt-in.** With `AUTODREAM_PRUNE_ROOTS` unset or empty the helper does nothing. Otherwise it searches each colon-separated root for repos to a depth of 3. `--dry-run` (or `AUTODREAM_PRUNE_DRY_RUN=1`) reports what it would remove and writes nothing to the ledger.
- **Usage.** `prune-worktrees.sh [--dry-run] <out-dir>` writes `<out-dir>/worktree-prune.tsv` (action, repo, branch, path, reason) and `worktree-prune.md`, and prints one summary line. A missing out-dir is the only exit 2.
- **Always exit 0 once there is an out-dir**, including after a bad knob, a failed `mkdir`, a watchdog stop, or a `gh` outage. The knobs are `AUTODREAM_PRUNE_GRACE_MIN` (720), `_MAX` (25), `_CLOSED_DAYS` (7), `_BUDGET_SEC` (1200), `_KILL_SLACK` (120), `_CALL_SEC` (60), `_OPEN_LIMIT` (200), `_TRASH` (1), `_PROTECT`, `_LEDGER`. They are listed in `docs/run-knobs.md`. `run.sh` sources `~/.claude/autodream/config` with `set -a` first, so the config can set them.
- **`portable.sh` is found through the symlink.** Installed copies are symlinks, and a merge updates them before `install.sh` links a newly added helper. When `portable.sh` is not next to the link, the script resolves the link target and looks beside that.

### Consequences

Do not make the helper exit non-zero to signal a prune problem: `run.sh` logs `prune-worktrees.sh not found` and continues, and nothing else tolerates a failing step. A new knob needs a line in `docs/run-knobs.md` and, if it is numeric, a place in the integer check loop so a bad value cannot reach arithmetic. The helper depends on `portable.sh` (`tmo`, `pdate_fmt_epoch`, `_p_is_int`, `repo_slug`), so a new install-time link must be added to `install.sh` beside the others.

## a branch is deleted only on exact proof that the work landed

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (`judge`, `delete_remote`, `default_facts`)

### Context

`prune-worktrees.sh` runs in the nightly pipeline. It removes worktrees under `<repo>/.claude/worktrees/` and `<repo>/.worktrees/`, and the branches that sessions left on the remote after the PR merged. It deletes branches on a remote, so the bar is proof, not a guess. A wrong keep costs one more night. A wrong delete cannot be undone. When any check is unclear the item stays, and the report says why. Commits `e0eff3e` and `1075a87` (2026-10-13) tightened the first version (`2410b7b`) to this standard.

Each proof is shaped by a failure it has to avoid:

- **Merged PR.** A PR from this repo into the default branch is MERGED and its `headRefOid` equals the branch tip. A squash merge leaves no ancestry between the branch and the default branch, so ancestry cannot be the proof on GitHub. Requiring the head commit to equal the tip also means local commits made after the merge are not covered, because nobody reviewed them.
- **Closed PR.** A PR from this repo was CLOSED unmerged at least `AUTODREAM_PRUNE_CLOSED_DAYS` (default 7) ago, its head commit is the branch tip, and the remote branch is at that tip. GitHub keeps `refs/pull/N/head`, so the commit stays recoverable. The remote-tip condition means the commit is on GitHub, not only in a local clone.
- **No remote at all.** The tip is an ancestor of the default branch, is not the default branch's own tip, and the branch's reflog holds more than its creation. A branch created at the default tip and never touched is trivially an ancestor, so the two extra conditions stop a brand-new branch from reading as finished work.
- **A remote that is not on GitHub** is never pruned (`non-github-remote: no proof source`).

Every PR test also requires `isCrossRepository == false`, so a fork PR that reuses the branch name proves nothing.

### Decision

`judge` returns `finished` only through one of those proofs. It records the evidence in `PROOF` (PR URL, state, head, base) so the ledger can quote it. Any failed lookup keeps the branch: `gh` missing, the open-PR list at its limit, the per-branch lookup failing.

After either PR proof, `judge` asks whether any PR, open or not, ever used the branch as its base (`gh pr list --base`). A branch that other PRs have targeted is long-lived, and deleting it on the remote would close those PRs. It is kept as `base-of-pr`, and an error in that lookup keeps it too.

The remote branch is deleted with `git push --force-with-lease=refs/heads/<b>:<tip> origin :refs/heads/<b>`. The proven commit is the lease, so a push that landed after the fetch makes GitHub refuse the delete. `delete_remote` also declines up front when the remote-tracking ref no longer equals the proven tip (`remote kept: moved since the proof`). No branch name is ever put in a URL; the test branches `fix#42` and `it's` pin that names with odd characters take the same path.

`default_facts` asks the remote for the default branch every night (`git remote set-head origin -a`). A renamed default branch leaves `origin/HEAD` pointing at the old name, and every proof compares against `DEF_NAME`. A repo whose default branch cannot be learned is skipped (`default-branch-unknown`).

### Consequences

A change that makes a proof more lenient is unrecoverable on the remote. A new proof needs a test in `tests/prune-worktrees.sh` that pins a KEEP before any test that pins a removal. Cases already pinned there: `closedold`, `closednew`, `closedlater`, `fork`, `qa2`, `hiddenopen`. Loosening `headRefOid == tip` to ancestry would delete squash-merged branches that have post-merge commits. The way back from a mistake is the ledger, described in `rest-prune-worktrees-ledger-no-log-no-delete`.
