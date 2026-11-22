# tests: install-and-scheduler-suites: install, scheduler-label and prune-worktrees suites

Status: accepted · Date: 2026-11-22 · Code: `tests/install-dir.sh` (`linkdir` and `thrdir` fixtures, the notify.sh note), `tests/install-path.sh` (`new_sandbox`), `tests/scheduler-label.sh` (install rows, `restore_modes`), `tests/prune-worktrees.sh` (`make_repo`, the `gh` and `trash` shims, `AUTODREAM_PRUNE_LEDGER`), `tests/prune-worktrees.sh` (pass 1 and the later passes)

## an installed script must start before install.sh links its newest helper

### Context

A merge updates the symlinks into the checkout at once. A helper's own link appears only when `install.sh` runs again. For that window an installed script finds its sibling helpers through the link it was started by and must still start (see `bin-b-install-helper-link-fallback.md`).

`notify.sh` has no behavioural row here: its usage check runs before the resolver, and any argument that passes the usage check raises a real banner. It is covered by the structural check (it calls `resolve_install_dir`, carries no marker test) only.

### Decision

- `linkdir` links the scripts but not `lib-install-dir.sh`, and each script is started and must print its usage or normal output, not "No such file".
- `thrdir` links every helper `threads.sh` needs except `lib-flock.sh`, so the only way it can start is by finding `lib-flock.sh` in the directory its own link points at.

### Consequences

When a script gains a new sourced helper, add a fixture that links everything else and leaves out only that helper. A fixture that leaves out several helpers cannot say which fallback broke.

## the sandbox path is normalized through cd and pwd before the plist PATH is compared

### Context

macOS `TMPDIR` ends in a slash, so `mktemp -d "${TMPDIR:-/tmp}/ccad-ip.XXXXXX"` returns a path holding `//`. `install.sh` writes the directories it finds through `cd` and `pwd`, which collapse the double slash, so a comparison against the raw `mktemp` path misses on every directory the test expects to find in the plist PATH.

### Decision

`new_sandbox` reassigns `SANDBOX=$(cd "$SANDBOX" && pwd)` right after `mktemp`, so every expected path is built in the same form the installer writes.

### Consequences

Build any path the plist must contain from `$SANDBOX`, not from `$TMPDIR`. Removing the normalization makes the PATH assertions fail on macOS and pass on Linux, where `TMPDIR` has no trailing slash.

## the install rows drive the real installer, and put the checkout's file modes back

### Context

`bin/scheduler-label.sh` only advises. The #14 regression (a second install adopting and overwriting the first one's job) stops only if `install.sh` honours the non-zero status, so a unit test of the helper cannot show the guard works. `CLAUDE.md` ("The label is owned by a runner") covers the ownership rules.

### Decision

- The refusal rows run the real `install.sh` down its real scheduling path. `HOME` is the sandbox, so `install_schedule`'s `$HOME/Library/LaunchAgents` and the helper's default agree without a test-only override. `launchctl` is a shim that records its calls, so a broken refusal shows up as a recorded call and never mutates this machine's launchd.
- A real scheduling failure (a `launchctl` shim that fails) must still fail the install. The refusal path returns non-zero, so the caller swallows it; swallowing every non-zero return would turn a broken plist or failed bootstrap into an exit-0 install that claims all is in place, the same silent success as #14.
- `install.sh` runs `chmod +x "$REPO_DIR/bin/"*.sh` on the live checkout, so these rows change the working tree's file modes. The suite snapshots them (`stat -f '%p %N'`) and restores them in the EXIT trap.

### Consequences

Removing the `launchctl` shim or the mode restore makes the suite touch the host. Any new row that runs `install.sh` inherits both.

## real git repos, a bare local remote and shimmed gh and trash

### Context

`bin/prune-worktrees.sh` deletes worktrees, local branches and remote branches, and asks GitHub whether a PR proves a branch finished. The proof rules run real `git` against a real remote and parse `gh pr list` output, so a mock `git` would test nothing.

### Decision

- Every case is a real repo in a temp dir. The remote is a local bare repo that a per-repo `url.insteadOf` makes answer to `https://github.com/test/<name>.git`, so the script's own GitHub-origin detection runs. `gh` is a shim on PATH serving PR state from files in `$FAKE_GH_DIR`; `trash` is a shim that moves the directory aside and can be told to fail. No network.
- `AUTODREAM_PRUNE_LEDGER` is exported to a temp path for the whole suite, so a call that forgets a ledger of its own cannot write the real one.
- A race (a push landing between the script's fetch and its delete) is injected from inside the shim: when `RACE_BRANCH` names the head being looked up, the shim advances the remote branch before answering.
- Every commit is dated 2020 (`GIT_AUTHOR_DATE`, `GIT_COMMITTER_DATE`), so a branch with no worktree clears the recent-commit gate; `age` pushes worktree mtimes back the same way, and the one `fresh` case is left young on purpose.

### Consequences

A new proof rule needs a fixture shape the shim can serve, not a new mock of git. Dropping the 2020 dates makes every branchless case look recent and keeps it.

## most cases pin a KEEP, because a wrong delete cannot be undone

### Context

The script deletes branches on a remote. `CLAUDE.md` ("Where state lives", `worktree-prune`) says a new rule there needs a test that pins a KEEP before it needs one that pins a removal. A wrong delete is permanent; a wrong keep costs one more night.

### Decision

Pass 1 puts one repo in every state at once and asserts the KEEP cases: a dirty tree (untracked files included, with `status.showUntrackedFiles no` set on purpose), an unpushed commit, an open PR, a fresh file, a lock, a protected name, a PR whose head is not the tip, a fork PR, a non-default base, a branch that is the base of an open PR, a rebase in progress, a submodule. Later passes pin the failure paths: gh down, trash failing, no ledger, no pin, a hard cap, a stale volume. Each ends in nothing deleted.

### Consequences

When adding a removal rule, add the case that must still be kept first. A suite that only asserts removals cannot show a rule too eager.
