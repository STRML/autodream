# runsh: the L1 noise gate skips low-signal sessions from the stats sidecar and biases to triage whenever it cannot measure

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, noise gate)

## Context
Gating needs no model call: it reads the mechanical stats sidecar (`session-stats.sh`, computed once during enumeration). Subagent transcripts and tool-heavy sessions are legitimate work that is often short on user turns.

## Decision
The gate writes a `skipped: below_noise_gate` record when the sidecar says a session is not a sidechain, has fewer than 5 tool calls, and either has fewer than `AUTODREAM_MIN_USER_TURNS` (default 2) user turns or a computable duration under `AUTODREAM_MIN_MINUTES` (default 1). Either condition alone gates. A duration of 0 (zero or one timestamped line) never gates on the duration rule, and a missing or unparseable sidecar never gates: both bias to triage.

## Consequences
The cost of biasing to triage is one wasted model call, which is cheaper than dropping a real session, so keep the bias. A broken sidecar degrades several counters at once and is counted by `stats_sidecars_unparseable`. See CLAUDE.md, "Degraded measurements must say so, not read as zero".
