# tests-scheduler-label: the install rows drive the real installer, and put the checkout's file modes back

Status: accepted · Date: 2026-11-22 · Code: `tests/scheduler-label.sh` (install rows, `restore_modes`)

## Context

`bin/scheduler-label.sh` only advises. The #14 regression (a second install adopting and overwriting the first one's job) stops only if `install.sh` honours the non-zero status, so a unit test of the helper cannot show the guard works. `CLAUDE.md` ("The label is owned by a runner") covers the ownership rules.

## Decision

- The refusal rows run the real `install.sh` down its real scheduling path. `HOME` is the sandbox, so `install_schedule`'s `$HOME/Library/LaunchAgents` and the helper's default agree without a test-only override. `launchctl` is a shim that records its calls, so a broken refusal shows up as a recorded call and never mutates this machine's launchd.
- A real scheduling failure (a `launchctl` shim that fails) must still fail the install. The refusal path returns non-zero, so the caller swallows it; swallowing every non-zero return would turn a broken plist or failed bootstrap into an exit-0 install that claims all is in place, the same silent success as #14.
- `install.sh` runs `chmod +x "$REPO_DIR/bin/"*.sh` on the live checkout, so these rows change the working tree's file modes. The suite snapshots them (`stat -f '%p %N'`) and restores them in the EXIT trap.

## Consequences

Removing the `launchctl` shim or the mode restore makes the suite touch the host. Any new row that runs `install.sh` inherits both.
