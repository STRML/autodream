# tests-run-all: the suite shards round-robin by position in the file

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`_owns`, `_run`, `_timed`, `RUNALL_SHARD`), `tests/shard.sh`

## Context

The suite is slow because it runs `run.sh` hundreds of times, not because any one test is slow. The slow tests are spread across the file. Measured when the scheme was chosen (four shards): the longest shard held 26% of the run time against an ideal 25%. CI has since moved to eight shards; CLAUDE.md "Sharding (2026-10-20)" has the later numbers.

## Decision

`RUNALL_SHARD=i/n` runs every n-th test and unit suite, counted in the order they appear in the file, so n jobs run the whole suite exactly once between them (`tests/shard.sh` proves it). `RUNALL_LIST=1` prints what a shard would run and runs nothing. Unset, the whole suite runs. `RUNALL_TIMES=<file>` appends `<seconds> <name>` per entry, which is the data a duration-weighted split would need. The shard value is validated strictly (digits, one slash, digits; `10#` so `08` is eight). Anything else exits 2 instead of reading as the whole suite.

## Consequences

Add a new test as a `_run test_name` line, never a direct call, or it runs in every shard. Weight shards by measured duration only if the slow tests stop being spread through the file.
