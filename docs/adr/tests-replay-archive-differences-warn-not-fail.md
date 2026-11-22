# tests-replay: a difference an archive explains is a WARN, and only checks about this code can FAIL

Status: accepted · Date: 2026-11-22 · Code: `tests/replay.sh` (`replay_artifacts`, `replay_ingest`, `cmp_num`, `cmp_num_warn`)

## Context

`tests/replay.sh` runs the current runner's code over archived data and compares each figure with the `run-stats.txt` the original night wrote. An archive is not frozen to the code under test: it can predate a counter, be rebuilt or pruned since, or have been counted by an older rule. Measured cases:

- The 2026-05-28 claude archive, the tool's first day, holds one findings JSON with no `findings` array.
- 2026-09-13 holds 7 findings JSONs where its run-stats recorded 9.
- Before advisor sidecars were dropped from the overlap pass (omp-autodream 2026-08-21), the old figure counted each advisor against its parent, and its sidecars carry no `is_advisor`. The replay therefore reads lower by design.
- A directory rebuilt in place keeps the sidecars of earlier runs, which the overlap pass reads along with the latest run's.
- A session resumed later changes its mtime, so a corpus can move after the night it was counted.

## Decision

- Counts of what is on disk (findings written, errors, gated, sessions found or triaged, overlap) go through `cmp_num_warn`: a mismatch is a WARN. A shape violation in an archive is reported with its count and is a WARN too, because the current runner would have refused that file and retried or stubbed it.
- The checks that can FAIL (`cmp_num`) are the ones about this code: failure classification, skill-field enforcement, that the overlap pass and the oversized gate run, and that every staged session is enumerated and triaged.
- The skill-field comparison covers only sessions the enforcement pass would touch. Gated stubs and error records are never rewritten by it and carry no skill fields.
- Where the cause is known, the WARN names it: the advisor count, or the sidecar count of a rebuilt directory against the run's session count.

## Consequences

Turning a WARN into a FAIL makes the replay fail on archives that are correct for their time. Add a FAIL only for a figure the current code computes alone. A new explained difference should say what explains it in the WARN text. The harness is kept honest by `test_replay_harness_works_on_synthetic_data` in `tests/run-all.sh`.
