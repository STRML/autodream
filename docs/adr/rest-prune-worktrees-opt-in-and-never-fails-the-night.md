# rest: pruning is opt-in, and the helper never returns a failure to run.sh

Status: accepted · Date: 2026-10-13 · Code: `bin/prune-worktrees.sh` (argument handling, `finish`, sourcing of `portable.sh`), `bin/run.sh` (`PRUNE_WORKTREES`)

## Context

The step deletes things on a remote and in other repos, so a fresh install must not do it. It also runs unattended after the report's inputs are gathered, so a failure in it must not cost the night's report. The helper is symlinked into `~/.claude/autodream/` by `install.sh`.

## Decision

- **Opt-in.** With `AUTODREAM_PRUNE_ROOTS` unset or empty the helper does nothing. Otherwise it searches each colon-separated root for repos to a depth of 3. `--dry-run` (or `AUTODREAM_PRUNE_DRY_RUN=1`) reports what it would remove and writes nothing to the ledger.
- **Usage.** `prune-worktrees.sh [--dry-run] <out-dir>` writes `<out-dir>/worktree-prune.tsv` (action, repo, branch, path, reason) and `worktree-prune.md`, and prints one summary line. A missing out-dir is the only exit 2.
- **Always exit 0 once there is an out-dir**, including after a bad knob, a failed `mkdir`, a watchdog stop, or a `gh` outage. The knobs are `AUTODREAM_PRUNE_GRACE_MIN` (720), `_MAX` (25), `_CLOSED_DAYS` (7), `_BUDGET_SEC` (1200), `_KILL_SLACK` (120), `_CALL_SEC` (60), `_OPEN_LIMIT` (200), `_TRASH` (1), `_PROTECT`, `_LEDGER`. They are listed in `docs/run-knobs.md`. `run.sh` sources `~/.claude/autodream/config` with `set -a` first, so the config can set them.
- **`portable.sh` is found through the symlink.** Installed copies are symlinks, and a merge updates them before `install.sh` links a newly added helper. When `portable.sh` is not next to the link, the script resolves the link target and looks beside that.

## Consequences

Do not make the helper exit non-zero to signal a prune problem: `run.sh` logs `prune-worktrees.sh not found` and continues, and nothing else tolerates a failing step. A new knob needs a line in `docs/run-knobs.md` and, if it is numeric, a place in the integer check loop so a bad value cannot reach arithmetic. The helper depends on `portable.sh` (`tmo`, `pdate_fmt_epoch`, `_p_is_int`, `repo_slug`), so a new install-time link must be added to `install.sh` beside the others.
