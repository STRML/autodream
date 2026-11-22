# tests-prune-worktrees: real git repos, a bare local remote and shimmed gh and trash

Status: accepted · Date: 2026-11-22 · Code: `tests/prune-worktrees.sh` (`make_repo`, the `gh` and `trash` shims, `AUTODREAM_PRUNE_LEDGER`)

## Context

`bin/prune-worktrees.sh` deletes worktrees, local branches and remote branches, and asks GitHub whether a PR proves a branch finished. The proof rules run real `git` against a real remote and parse `gh pr list` output, so a mock `git` would test nothing.

## Decision

- Every case is a real repo in a temp dir. The remote is a local bare repo that a per-repo `url.insteadOf` makes answer to `https://github.com/test/<name>.git`, so the script's own GitHub-origin detection runs. `gh` is a shim on PATH serving PR state from files in `$FAKE_GH_DIR`; `trash` is a shim that moves the directory aside and can be told to fail. No network.
- `AUTODREAM_PRUNE_LEDGER` is exported to a temp path for the whole suite, so a call that forgets a ledger of its own cannot write the real one.
- A race (a push landing between the script's fetch and its delete) is injected from inside the shim: when `RACE_BRANCH` names the head being looked up, the shim advances the remote branch before answering.
- Every commit is dated 2020 (`GIT_AUTHOR_DATE`, `GIT_COMMITTER_DATE`), so a branch with no worktree clears the recent-commit gate; `age` pushes worktree mtimes back the same way, and the one `fresh` case is left young on purpose.

## Consequences

A new proof rule needs a fixture shape the shim can serve, not a new mock of git. Dropping the 2020 dates makes every branchless case look recent and keeps it.
