# runsh: stale-row and per-source counts are measured from the final sidecar, and an error reads as unknown

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`build_source_sidecar`: `SIDECAR_STALE_ROWS`, `SESSIONS_BY_SOURCE`)

## Context

Collision resolution removes provenance rows after the fact, so a count taken during the walk reported sessions that no longer exist in the worklist. The first stale-row count was wrong in both directions: it added one when a rewrite ATTEMPT failed and then iterated dropped PATHS. A two-path collision with one persistent stale row reported 3 (one attempt plus the same hash found twice), and a transient failure that a later rewrite had repaired reported 1 when the honest answer was 0.

Staging matters: `producer || exit 1 | sort -u` is masked, because without `pipefail` `sort` exits 0 on empty input, so a failing producer produced an empty successful assignment and the metric read 0, the false zero this branch exists to avoid.

## Decision

`SIDECAR_STALE_ROWS` is computed once, after all rewrites: the dropped hashes are staged in `$FINDINGS_DIR/.stale-hashes.$$`, then `sort -u`'d, then each unique hash is looked up in the final sidecar (`grep -q`, 0 stale, 1 absent). A `grep` status above 1 sets `SIDECAR_STALE_ROWS=unknown` (an error is not "absent", the same refusal of a false-clean reading as `overlap_measured`); a staging or sort failure sets it to `unknown` too, with a WARNING ("reporting it as unknown rather than zero"). `SESSIONS_BY_SOURCE` is likewise counted from the final sidecar with `awk | sort | uniq -c`, not during the walk, and is `none` when empty. The metric is reported in run-stats as `sidecar_stale_rows` and `sessions_by_source`.

## Consequences

A measured count that cannot be measured must say `unknown`; this is the repo's rule for degraded measurements (see CLAUDE.md, "Degraded measurements must say so, not read as zero"). Do not move either count back into the loop.
