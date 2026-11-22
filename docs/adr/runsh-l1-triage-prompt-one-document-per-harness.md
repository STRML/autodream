# runsh: one triage document serves every harness, and a harness that differs adds an addendum appended for its own sessions only

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`, prompt assembly)

## Decision
`l1_attempt` always appends `SESSION_TRIAGE.md`. When the session's source adapter (`$src`, which can differ from the L1 engine) ships `adapters/<name>/triage.md`, it is appended after a blank line for that adapter's sessions only, so a claude worker receives exactly the text it always did.

## Consequences
A new harness adds `adapters/<name>/triage.md` and no code here. The chunk cache name (`ccfg`) hashes the addendum, so editing it invalidates cached chunk answers. See CLAUDE.md, "One triage document, one addendum per harness that differs".
