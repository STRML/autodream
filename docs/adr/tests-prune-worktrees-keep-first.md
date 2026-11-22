# tests-prune-worktrees: most cases pin a KEEP, because a wrong delete cannot be undone

Status: accepted · Date: 2026-11-22 · Code: `tests/prune-worktrees.sh` (pass 1 and the later passes)

## Context

The script deletes branches on a remote. `CLAUDE.md` ("Where state lives", `worktree-prune`) says a new rule there needs a test that pins a KEEP before it needs one that pins a removal. A wrong delete is permanent; a wrong keep costs one more night.

## Decision

Pass 1 puts one repo in every state at once and asserts the KEEP cases: a dirty tree (untracked files included, with `status.showUntrackedFiles no` set on purpose), an unpushed commit, an open PR, a fresh file, a lock, a protected name, a PR whose head is not the tip, a fork PR, a non-default base, a branch that is the base of an open PR, a rebase in progress, a submodule. Later passes pin the failure paths: gh down, trash failing, no ledger, no pin, a hard cap, a stale volume. Each ends in nothing deleted.

## Consequences

When adding a removal rule, add the case that must still be kept first. A suite that only asserts removals cannot show a rule too eager.
