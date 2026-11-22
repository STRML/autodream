# runsh: run-stats counts sessions and L1 failures so each denominator is honest

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`; the oversized-gate computation just above it)

## Context
Counts that look similar measure different things, and the self-audit divides one by another. Facts the retired comments record:

- `gated`: sessions skipped before any model call (noise gate). They are within `sessions_triaged` but structurally cannot appear in `l1_findings_with_error` (they never reached a model), so the extraction-failure rate's denominator must subtract this out.
- `sessions_dropped_to_collision` is the vs.-raw denominator: a session lost to ANY path (prune misclassification, silent worker death, slim leftovers) shows up here. Always >= 0; if nonzero the aggregator should investigate even when `l1_missing` is 0. (Its line is followed by `sidecar_stale_rows` and `sessions_dropped_after_failures`.)
- `l1_errored_silent`, `l1_errored_provider`, `l1_errored_unclassified`: a silent worker death (exit 0, empty stdout), a provider refusal and an unclassifiable failure are not evidence that a transcript was too large. The size-attributable failure rate is `(errors - silent - provider - unclassified) / (triaged - gated)`.
- Oversized-transcript measurement gate (#12): the comment says "see the computation above `L1_ERRORED`", but the computation actually sits below it (the `OVERSIZED_*` block). Gate: if `oversized_errored / oversized_total` sustains >= 5% over a trailing week, the signal for issue #12 has opened. The runner only records counters; the L2 self-audit and the human do the trailing-week judgment.
- Sidecar health (#27): `stats_sidecars_unparseable` counts sessions of `sessions_triaged` whose stats sidecar was missing, empty, or without numeric `transcript_bytes`. Every sidecar consumer degrades when it is non-zero (`gated` under-counts, because an unreadable sidecar never gates by design, and oversized sizes came from a live read), so it caveats those two keys instead of duplicating a flag onto each.
- `l1_err_files_orphaned`: `.err` files with no findings JSON and no session in tonight's worklist, i.e. failed triage nothing will retry. Nonzero is a stale failure, not tonight's.
- `l1_findings_outside_worklist`: findings JSONs no session in tonight's worklist owns. L2 reads them all, so a nonzero value means the report includes sessions this run did not place in the day.
- `sessions_top_level` / `sessions_nested` (#79): the Activity snapshot's total split into top-level sessions and nested workers. Both count ungated sessions, the same set as the report's N; `fanouts.tsv` names each worker and its parent.

## Decision
The keys are emitted as listed, with the class counts beside both `l1_findings_with_error` and `oversized_errored`, so the audit can remove silent, provider and unclassified from the numerator and denominator. See CLAUDE.md, "A failed worker leaves its evidence, and the failure is classified", "Degraded measurements must say so", and "Which day a session belongs to".

## Consequences
Changing which sessions each counter includes silently changes the #12 rate and the report's N. If a key is renamed, PROMPT.md's self-audit must move with it. The pointer "see the computation above `L1_ERRORED`" is inexact (the block is below it); the ADR is the record.
