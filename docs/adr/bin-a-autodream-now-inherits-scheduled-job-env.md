# bin-a: the one-shot copies the scheduled job's environment, never the caller's, and refuses when it cannot

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`xml_escape_into`, the `SCHED_PLIST` block, the plist write)

## Context

A login setting lives in the scheduled job's `EnvironmentVariables`: a host whose nightly runs on a non-default Claude profile sets `CLAUDE_CONFIG_DIR` there. A one-shot plist built from `PATH` alone ran the CLI on the default profile; with no login there, every L2 attempt wrote "Not logged in · Please run /login" and the date stayed unassembled.

## Decision

- The environment is the scheduled job's, minus the keys the script sets itself (`PATH`, `AUTODREAM_DIR`, `DREAMS_DIR`, `AUTODREAM_FORCE`, `AUTODREAM_RUN_TOKEN`). The caller's shell environment is deliberately not copied: a terminal inside another Claude profile would run the job under that login.
- `scheduler-label.sh --plist` applies the same ownership rule the label uses, so a plist that merely shares the label is never read. No scheduled job means nothing is inherited.
- A scheduled job whose environment cannot be read (no `plutil`, no `jq` on the job's own `PATH` or the caller's, a plist that will not convert, a failing `jq`) refuses the launch with exit 65: copying nothing would start the run logged out again. A key the plist does not have is an empty environment, not a failure.
- `jq` is looked up on the job's own `PATH` first, because the caller's `PATH` may lack `/opt/homebrew/bin`. `AUTODREAM_JQ_BIN` names the `jq` to use; the tests point it at a failing one.
- The pairs travel NUL-separated, so no value can be split or unescaped on the way through. `xml_escape_into` keeps trailing newlines: a command substitution would strip them, so the text carries a sentinel `x` through `sed`.
- The plist is written with `umask 077`, because the body now carries an environment that can hold more than paths. launchd only refuses group- or world-writable agent plists, so mode 600 loads.

## Consequences

CLAUDE.md, "Running on-demand without the 10-min cap", describes the same behavior from the outside. `tests/autodream-now.sh` pins the refusal and the copy. Do not simplify the escaper to `$(...)`, and do not source the caller's environment to save the plist read.
