# runsh: a runner-side setup failure is ledgered as `staging`, writes no stub, and leaves the slot empty

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_infra_fail`, the decision point after the rounds)

## Context
A failure before the engine starts (no staging root, no stage, no state directory, no sandbox) says nothing about the session. The final-round metadata stub would fill the slot, satisfy the missing-work check and let a report publish over sessions that were never triaged.

## Decision
`l1_infra_fail` sets `netdown=staging`, appends `<hash> <round> staging` to `l1-netdown.txt`, adds an explanatory line to the `.err` and returns 1. The stub branches treat `staging` like an outage (no stub). When it is what the last round left missing, the run treats it as a fatal (banner, `fatal:` in run-stats, the marker the next run reads), not an outage deferral.

## Consequences
Waiting heals nothing here, so it is a fatal and not a deferral; with no findings JSON `unassembled_dates` would never name the date. See CLAUDE.md, "A host with no working sandbox says so".
