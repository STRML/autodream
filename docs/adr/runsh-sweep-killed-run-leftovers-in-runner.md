# runsh: temp files left by a killed run are swept by the runner, not by the adapter or a trap

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sweep_killed_leftovers`)

## Context
A run killed mid-flight (this pipeline's normal failure) leaves the temp its adapter was writing, `<out>.tmp.XXXXXX`, and slim-transcript.sh's `<dst>.pre.jsonl`. The adapter cannot clean up after its own death: a signal trap defers the signal until the delegate returns and hangs the run (`adapters/claude/adapter.sh` says why). Issue #57.

## Decision
The cleanup lives in the runner, where a killed process cannot skip it: the next run removes `*.tmp.??????`, `*.pre.jsonl`, `*.stage` and `.chunks/*/*.stage` under the findings dir and logs the count. Nothing reads these names (the findings glob is `*.json` and slim output is read by exact path), so this is about not accumulating them; a stale temp from a killed run is not a partial result anyone should read. It runs under the per-date lock, so no live writer of these files exists. The test is `-e` or `-L`, not `-f`: a symlink or a directory is what a worker leaves as its answer, and `-f` would skip both.

## Consequences
Do not move the sweep outside the per-date lock; a live writer's temp would be deleted. A new temp-file suffix in the findings dir has to be added to the glob list here.
