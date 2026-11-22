# bin-b: only the label refusal (exit 3) is survivable; every other schedule failure fails the install

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule` and its caller)

## Context

A foreign job holding our label leaves the symlinks installed and the run still works by hand, so the install can finish. Any other failure (a plist failing `plutil -lint`, a bootstrap that did not take) would print "everything is in place" over a silently broken schedule, the state that went unnoticed for 18 days (see `bin-b-install-label-ownership`).

The caller runs `install_schedule || schedule_rc=$?`, and that form disables `set -e` for the whole function body. A bootstrap failure left to errexit would therefore print `scheduled:` over a job that was never bootstrapped.

## Decision

- Inside `install_schedule` the `launchctl bootstrap` result is checked explicitly and returns 1 on failure; the `bootout` before it is `|| true` (RunAtLoad is false, so bootstrap arms the schedule without firing a run).
- The caller treats exit 3 as "schedule not installed, everything else in place" and any other non-zero as a hard failure with that exit code.

## Consequences

New steps inside `install_schedule` need their own `|| return` guards; errexit does not protect them.
