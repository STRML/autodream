# rest: no removal without a write-ahead ledger record and a pinned tip

Status: accepted · Date: 2026-10-14 · Code: `bin/prune-worktrees.sh` (`ledger`, `lstep`, `shq`, `recover_cmds`, `remove_item`)

## Context

The pruner deletes remote branches, and a wrong delete cannot be undone by git alone. Commit `46c1fb6` (2026-10-14) added a ledger so every removal can be reversed, and `299b79c` (the same day) closed a hole in it: after the branch and the worktree are gone, nothing else keeps a squash-merged tip reachable. `git gc` would prune it and the recorded undo commands would fail.

## Decision

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

## Consequences

Pins cost a few bytes each and accumulate by design. The README gives the command that deletes them once undo is no longer needed. Changing the column order breaks the recover instructions in the README and the assertions in `tests/prune-worktrees.sh` (`ledger_row`, `ledger_col`). Do not add a removal path that skips `remove_item`, and do not move the pin or the intent write after the first change.
