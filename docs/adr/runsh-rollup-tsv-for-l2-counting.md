# runsh: L2 counts from rollup.tsv, categories.tsv and findings.tsv, written by the runner from trusted inputs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`write_rollup`)

## Context
L2's Glob and directory reads stop at 200 entries. On 2026-10-31 the findings dir held 2683 entries for 885 sessions, and the report counted a 90-file sample and never saw `fanouts.tsv`.

## Decision
`write_rollup` runs after the skill-field pass (which rewrites the fields the roll-up reads) and after `compute_fanout_stats` (whose `fanouts.tsv` gives each worker its parent). It passes `rollup.sh` the source map and the session rows (hash, bucket, cwd) built before any model ran, not `sessions-source.txt` or `session-cwds.tsv`, which an L1 worker can rewrite. A failure logs, says so in `run-stats.txt` (`rollup: helper missing` or `rollup: failed`) and leaves no stale file from an earlier run, so L2 reports the counts as unavailable rather than wrong. On failure all three files are removed together: one file without the others would be read as a whole roll-up. A success is judged by `rollup.sh`'s last line starting `rollup: rows=`; its counters go into run-stats as `rollup_<name>`, plus `sandbox_sessions` and `sandbox_shape_denies_min`.

See CLAUDE.md, "Where state lives" (`rollup.tsv`, `categories.tsv`, `findings.tsv`).

## Consequences
Never source the roll-up inputs from a file in the findings dir.
