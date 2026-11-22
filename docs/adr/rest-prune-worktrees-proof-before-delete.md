# rest: a branch is deleted only on exact proof that the work landed

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (`judge`, `delete_remote`, `default_facts`)

## Context

`prune-worktrees.sh` runs in the nightly pipeline. It removes worktrees under `<repo>/.claude/worktrees/` and `<repo>/.worktrees/`, and the branches that sessions left on the remote after the PR merged. It deletes branches on a remote, so the bar is proof, not a guess. A wrong keep costs one more night. A wrong delete cannot be undone. When any check is unclear the item stays, and the report says why. Commits `e0eff3e` and `1075a87` (2026-10-13) tightened the first version (`2410b7b`) to this standard.

Each proof is shaped by a failure it has to avoid:

- **Merged PR.** A PR from this repo into the default branch is MERGED and its `headRefOid` equals the branch tip. A squash merge leaves no ancestry between the branch and the default branch, so ancestry cannot be the proof on GitHub. Requiring the head commit to equal the tip also means local commits made after the merge are not covered, because nobody reviewed them.
- **Closed PR.** A PR from this repo was CLOSED unmerged at least `AUTODREAM_PRUNE_CLOSED_DAYS` (default 7) ago, its head commit is the branch tip, and the remote branch is at that tip. GitHub keeps `refs/pull/N/head`, so the commit stays recoverable. The remote-tip condition means the commit is on GitHub, not only in a local clone.
- **No remote at all.** The tip is an ancestor of the default branch, is not the default branch's own tip, and the branch's reflog holds more than its creation. A branch created at the default tip and never touched is trivially an ancestor, so the two extra conditions stop a brand-new branch from reading as finished work.
- **A remote that is not on GitHub** is never pruned (`non-github-remote: no proof source`).

Every PR test also requires `isCrossRepository == false`, so a fork PR that reuses the branch name proves nothing.

## Decision

`judge` returns `finished` only through one of those proofs. It records the evidence in `PROOF` (PR URL, state, head, base) so the ledger can quote it. Any failed lookup keeps the branch: `gh` missing, the open-PR list at its limit, the per-branch lookup failing.

After either PR proof, `judge` asks whether any PR, open or not, ever used the branch as its base (`gh pr list --base`). A branch that other PRs have targeted is long-lived, and deleting it on the remote would close those PRs. It is kept as `base-of-pr`, and an error in that lookup keeps it too.

The remote branch is deleted with `git push --force-with-lease=refs/heads/<b>:<tip> origin :refs/heads/<b>`. The proven commit is the lease, so a push that landed after the fetch makes GitHub refuse the delete. `delete_remote` also declines up front when the remote-tracking ref no longer equals the proven tip (`remote kept: moved since the proof`). No branch name is ever put in a URL; the test branches `fix#42` and `it's` pin that names with odd characters take the same path.

`default_facts` asks the remote for the default branch every night (`git remote set-head origin -a`). A renamed default branch leaves `origin/HEAD` pointing at the old name, and every proof compares against `DEF_NAME`. A repo whose default branch cannot be learned is skipped (`default-branch-unknown`).

## Consequences

A change that makes a proof more lenient is unrecoverable on the remote. A new proof needs a test in `tests/prune-worktrees.sh` that pins a KEEP before any test that pins a removal. Cases already pinned there: `closedold`, `closednew`, `closedlater`, `fork`, `qa2`, `hiddenopen`. Loosening `headRefOid == tip` to ancestry would delete squash-merged branches that have post-merge commits. The way back from a mistake is the ledger, described in `rest-prune-worktrees-ledger-no-log-no-delete`.
