# bin-a: the stats and slim wrappers install no signal trap, and a killed run's temp file is swept by the runner

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`stats|slim`), `bin/run.sh` (`sweep_killed_leftovers`)

## Context

A run killed mid-flight leaves its `$2.tmp.XXXXXX` behind. That is real but cosmetic: nothing reads `*.tmp.*` (the findings glob is `*.json` and slim output is read by exact path). Adding `trap 'rm -f "$t"' ... TERM` was measured, not assumed: bash defers a trapped signal until the foreground child returns, and the delegate is that child, so the trap turns a prompt death into an adapter that ignores SIGTERM for as long as the delegate runs. The test hung for 120 seconds and left orphaned `slim-transcript.sh` processes holding their input open.

## Decision

No trap. Being killed mid-flight is this pipeline's normal failure, so a stale temp is accepted over a hung process. The runner sweeps `*.tmp.??????` and `*.pre.jsonl` out of the findings dir at the start of each run (`sweep_killed_leftovers`, #57). Backgrounding the delegate and killing it from a trap would work, at the cost of five lines of signal plumbing in a file whose claim is that nothing is invented here.

## Consequences

A trap is safe in the test suite and not in the adapter: the deferral is bounded there (every foreground child is a `sleep 0.05` or faster) and unbounded here. `docs/adr/tests-adapters-claude-suite-process-control.md` records the suite side. Do not add a trap to the adapter without reading it.
