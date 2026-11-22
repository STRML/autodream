# runsh: A missing or failing self-session pruner falls back to the raw session list

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `PRUNE --filter` step)

## Context
Autodream's own headless worker and aggregator transcripts must not be re-triaged. New runs leave none (`--no-session-persistence`), but runs predating that fix littered `~/.claude/projects/`. The prune helper owns the "is this ours?" predicate. See CLAUDE.md, 'Self-pollution'.

## Decision
If `$PRUNE` is executable, `sessions.txt.raw` is filtered through `"$PRUNE" --filter` into `sessions.txt`. If the helper is missing, or the filter fails, `sessions.txt.raw` is copied unchanged.

## Consequences
- The fallback is deliberate: failing open re-triages some of autodream's own transcripts left by runs predating the fix, while failing closed would silently drop real sessions from the night.
- Do not change the fallback to an error without deciding which loss is worse.
