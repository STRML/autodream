# runsh: the runner's git commit is read from the real checkout, and only a resolved, tracked-state-dirty answer is stamped

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`RUNNER_REPO_DIR`, `RUNNER_COMMIT`, `RUNNER_DIRTY`)

## Context
Issue #29: `run-stats.txt` must say which code actually ran. `install.sh` symlinks each script individually into `~/.claude/autodream`, so that directory is real and has no `.git`, and `cd "$(dirname "$0")"` resolves symlinked directories but not a symlinked file: it lands in the install dir every time. Six of the eight runs through 2026-08-03 wrote `runner_commit: unknown` for that reason alone; the two that stamped a sha were launched from the repo by hand. See CLAUDE.md, "Which code actually ran (`runner_commit`)".

## Decision
- The repo dir comes from the symlink walk (`RUNNER_SRC`, see `runner-symlink-walk-hop-cap`), not from `SCRIPT_DIR`, which is a working directory and not a checkout (`SCRIPT_DIR` stays as it is: helper lookup genuinely wants the install dir).
- Still a symlink after the walk means it gave up (a cycle, or a chain past the cap) rather than arriving anywhere: `RUNNER_REPO_DIR` is empty. Resolving the truncated path would stamp whatever checkout it happens to sit in, and a confidently wrong sha is worse than no sha.
- The empty case short-circuits before git rather than leaning on git to reject it: `git -C "" rev-parse HEAD` does NOT fail, it silently stays in `$PWD` and answers for whatever repo the caller launched from, and launchd starts this job from an unrelated cwd, so git would stamp a stranger's sha.
- `git status --porcelain --untracked-files=no` for the dirty check: "dirty" warns that the run used code that exists in nobody's history, which only tracked modifications can cause. Counting untracked files made the first production run report `runner_dirty: yes` over a stray scratch directory, the kind of false alarm that gets a signal ignored.
- Everything degrades to `unknown` / `no`: a tarball install with no git, or no git binary, is a supported way to run this and must not fail the run.

## Consequences
A `run-stats.txt` that is missing keys (rather than holding odd values) means an old runner. Keep the empty-dir short-circuit.
