# rest: the omp L1 write list is empty by default, extended only through AUTODREAM_L1_WRITES_EXTRA

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-writes`, `nl_refuse`)

## Context

`run.sh` runs the worker under an OS sandbox that can write nothing besides its staging directory and this list (#169, `bin/l1-confine.sh`; CLAUDE.md, "What the sandbox allows"). The claude adapter's list is default deny with the CLI cache on it (`bin-a-adapter-claude-l1-writes-default-deny.md`). omp cannot run on an empty list by itself, so `l1-stage-env` gives each confined worker a throwaway HOME inside its stage and every omp write lands there (`rest-omp-adapter-l1-stage-env-throwaway-home.md`). The measurement is in `docs/plans/2026-11-21-omp-l1-writes.md`.

## Decision

The list stays empty. A host whose confined call still fails names the path in `AUTODREAM_L1_WRITES_EXTRA` (colon-separated, absolute, a trailing `*` is a prefix) and accepts that path's exposure.

- The output is one path per line, so a path holding a newline would read as two. An extra entry that holds one is refused outright (exit 3, `l1-writes: refusing a path that holds a newline`), not split, because the second half could be a directory like `/Users/you`.
- Globbing is off (`set -f`) while the extras are split, so an entry such as `~/x.json*` stays a prefix and does not expand to the files that exist.
- IFS is restored and globbing turned back on afterwards.

## Consequences

Adding a default path widens what an injected worker can persist. `tests/run-all.sh` pins the output, the newline refusal and the unknown-verb exit. The test cases `sed` the `l1-writes)` label line to prove the runner copes with an adapter that lacks the verb, so keep that label at the start of its line.
