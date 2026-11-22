# bin-a: RunAtLoad is the only trigger for the one-shot, with no kickstart

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (the `launchctl bootout` and `bootstrap` calls)

## Context

The script boots out any finished instance of its label and then bootstraps the one-shot plist, whose `RunAtLoad` starts `run.sh`.

## Decision

`RunAtLoad` is the only trigger, so the run fires exactly once. The script does not also `launchctl kickstart`: a fast run (the idempotency no-op, for instance) would execute twice.

## Consequences

CLAUDE.md, "Running on-demand without the 10-min cap", says the same. Adding a kickstart "to be sure" duplicates runs.
