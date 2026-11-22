# runsh: The L1 dispatcher gets its fixed configuration from exported environment variables

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `export` lines and the adapter/model maps before L1)

## Context
The L1 workers run inside `xargs` subshells that share no state with the runner, and a worker holds the Write tool, so anything the next worker reads from the findings dir can be rewritten. See CLAUDE.md, 'Who starts the L1 worker' ("The source map is held in the environment, not read from the findings dir") and 'Reading a long session: chunked triage' ("One gate, off is the old behaviour").

## Decision
- `L1_CHUNKING` is the one switch for chunked triage, exported with `CHUNKER`, `MERGER`, `AUTODREAM_L1_CHUNK_BYTES` and `AUTODREAM_L1_MAX_CHUNKS`: 0 leaves the slimmer in its default mode and never reaches the chunker or the merge.
- Which adapter runs each session (`AUTODREAM_SOURCE_MAP`) and which model each adapter's workers use (`AUTODREAM_L1_MODELS`) are fixed before the first model call and held in the environment. The models are resolved once per adapter, not per session.
- `TIMEOUT_BIN` is empty when no timeout binary exists, which the worker treats as run-unbounded (recorded as `l1_timeout_bin: none`).

## Consequences
- Do not make the worker re-read `sessions-source.txt` or any findings-dir file for these values.
- Test: `test_l1_engine_cannot_be_redirected_by_a_worker` in `tests/run-all.sh` (named in CLAUDE.md).
