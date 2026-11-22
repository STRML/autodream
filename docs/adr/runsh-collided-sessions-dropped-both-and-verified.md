# runsh: two paths on one hash are both dropped from the worklist, the drop is verified, and the telemetry says what was enumerated

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`build_source_sidecar`)

## Context

Two different session paths can truncate to one 12-character hash and would race for one `<hash>.json`. There is no sensible winner. An earlier version logged "skipping both" while skipping neither: it removed the sidecar row and left both paths in `sessions.txt.raw`, so two workers still raced and silently overwrote each other. The log said one thing and the code did another, which is worse than not checking at all.

Other earlier faults, each fixed: `grep -v` exits 1 when it removes the only line, so a guarded `&& mv` left the stale mapping behind in the single-entry case; the earlier path is appended again for every later collision on one hash (three paths sharing a hash gave A,B,A,C, four lines for three drops) and the duplicate propagated into the telemetry; overwriting RAW with the post-drop worklist size made a forced two-session collision report `sessions_found_raw: 0` and "0 session file(s) were enumerated".

## Decision

On a collision the helper appends both paths to `.collided` and logs `COLLISION`. After the walk, if the drop set is non-empty:

- it is deduplicated with `sort_unique_inplace`; both the worklist filter and the post-filter verification read it, so a damaged one would let a collided path through while everything reports success;
- the worklist (`sessions.txt.raw`) is rewritten with `rewrite_filtered -vxF -f` and that rewrite FAILS CLOSED (`log_fatal`, return 1), because leaving it unchanged means two workers on one artifact;
- the drop is verified rather than trusted: `grep -qxF -f` must exit exactly 1; anything above 1 is an I/O error and refuses, because grep's "not found" is the wanted answer and the same code path would otherwise take success on an error;
- `RAW` stays the ENUMERATED count; `COLLIDED_DROPPED` counts the dropped paths separately;
- the provenance rows of the dropped hashes are removed, but only for COLLISION drops: the sidecar is built before the self-prune and the empty-session filter, so it still carries rows for worker transcripts and 0-turn shells that are later excluded. Nothing consumes it yet; the first consumer that joins it against `<hash>.json` must expect hashes with no findings record;
- sidecar row rewrites are DELIBERATELY survivable (`|| :`): a stale row overstates `sessions_by_source` by one and the helper has already logged why. The row rewrite is not counted at the attempt, see `sidecar-stale-row-count-measured-from-final-sidecar`.

## Consequences

Never make the worklist rewrite survivable, and never make the provenance row rewrite fatal without also deciding what a non-collided night should do. The worklist counts feed the `found ... excluded ... skipped` log line, so keep RAW as the enumerated total.
