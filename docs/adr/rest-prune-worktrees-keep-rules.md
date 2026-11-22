# rest: a fixed list of keep rules overrides any proof that the work landed

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (`sweep_worktree`, `sweep_branches`, `is_protected`, `recent_edit`, `rebase_branch`, `ignored_beyond_build`, `prune_stale_worktrees`, `sweep_repo`)

## Context

A proof that the PR merged (see `rest-prune-worktrees-proof-before-delete`) says the branch's commits are safe. It says nothing about what else is in the worktree directory, or whether someone is using it. The nightly run removes a directory and a remote branch, so each way a finished-looking branch can still be in use became a keep rule. The report gives the reason for every keep (`worktree-prune.tsv` and `.md`), and the README has the user-facing table.

## Decision

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

## Consequences

The list is the safety contract. The README table and `tests/prune-worktrees.sh` move with it. A new rule needs a test that pins a KEEP. Do not turn a keep into a removal because the proof is strong: the proof is about the commits, and the keep rules are about everything else in the directory.
