# bin-b: opting out of the review agent, or losing cmux or claude, boots out and deletes its plist

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`, `review_off`)

## Context

`--no-review` is per run, like `--no-schedule`. `AUTODREAM_REVIEW_AGENT=0` (environment or config) is what makes the choice survive re-installs, which would otherwise provision the agent again. A machine that had cmux or claude at install time and lost one would keep a stale scheduled job firing a failing trigger forever. Booting the job out is not enough: launchd loads every plist in LaunchAgents at login, so a plist left on disk brings the failing job back at the next login.

## Decision

When the agent is opted out or cannot be provisioned, the installer boots out `<label>-review` and removes its plist (in a dry run, it prints the removal instead). Opt-out values are `0`, `no`, `off`, `false`, in lower or upper case.

## Consequences

CLAUDE.md, "The review triage LaunchAgent", and `tests/install-review-agent.sh` pin the behavior. A refused label never reaches this code, so another install's review agent is not touched.
