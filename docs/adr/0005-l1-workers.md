# 0005: L1 workers: dispatch, input, validation and retry

Status: accepted · Governs: `bin/run.sh`, `tests/mock-claude.sh`, `tests/run-all.sh`, `bin/failure-class.sh`

This record holds 29 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: A hung worker, a cold token and a deterministic failure (omp-autodream, 2026-08 to 2026-09)](#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09)
- [A findings file's error is detected by its top-level key, not by text](#a-findings-files-error-is-detected-by-its-top-level-key-not-by-text)
- [l1_attempt is one engine call with a fixed argument contract, and it judges a chunk by the chunk rule](#l1_attempt-is-one-engine-call-with-a-fixed-argument-contract-and-it-judges-a-chunk-by-the-chunk-rule)
- [A serial, bounded, verified auth warmup runs per engine before the parallel L1 dispatch](#a-serial-bounded-verified-auth-warmup-runs-per-engine-before-the-parallel-l1-dispatch)
- [A cached L1 result is reused only if this run would accept it now](#a-cached-l1-result-is-reused-only-if-this-run-would-accept-it-now)
- [chunk inputs are rebuilt each dispatch, chunk answers are cached under a name that covers the chunk and every instruction it was read under](#chunk-inputs-are-rebuilt-each-dispatch-chunk-answers-are-cached-under-a-name-that-covers-the-chunk-and-every-instruction-it-was-read-under)
- [Chunk counters read the planning and call ledgers, and finished chunk answers count as progress](#chunk-counters-read-the-planning-and-call-ledgers-and-finished-chunk-answers-count-as-progress)
- [the chunk note tells each worker it holds one chunk of one session, and its wording is matched by the test mock](#the-chunk-note-tells-each-worker-it-holds-one-chunk-of-one-session-and-its-wording-is-matched-by-the-test-mock)
- [a chunked session is merged only when every chunk answered properly, and one failing chunk's evidence stands for the session](#a-chunked-session-is-merged-only-when-every-chunk-answered-properly-and-one-failing-chunks-evidence-stands-for-the-session)
- [when the chunker fails, the worker falls back to the capped head/tail slim, never to the uncapped input](#when-the-chunker-fails-the-worker-falls-back-to-the-capped-headtail-slim-never-to-the-uncapped-input)
- [The L1 circuit breaker counts a streak of barren rounds and still dispatches the stub round](#the-l1-circuit-breaker-counts-a-streak-of-barren-rounds-and-still-dispatches-the-stub-round)
- [a failure that retrying cannot change leaves a structured error record, not a missing file](#a-failure-that-retrying-cannot-change-leaves-a-structured-error-record-not-a-missing-file)
- [the L1 dispatcher hands each session path to its worker NUL-delimited, one argument per worker](#the-l1-dispatcher-hands-each-session-path-to-its-worker-nul-delimited-one-argument-per-worker)
- [The L1 dispatcher gets its fixed configuration from exported environment variables](#the-l1-dispatcher-gets-its-fixed-configuration-from-exported-environment-variables)
- [a failed L1 worker keeps its stdout, exit code and elapsed time as evidence](#a-failed-l1-worker-keeps-its-stdout-exit-code-and-elapsed-time-as-evidence)
- [a failed L1 worker gets a three-state network verdict from its own engine's host and a provider-refusal verdict, ledgered append-only per round](#a-failed-l1-worker-gets-a-three-state-network-verdict-from-its-own-engines-host-and-a-provider-refusal-verdict-ledgered-append-only-per-round)
- [on the final L1 round a failed session gets a metadata-only stub, except when the network was down or the provider refused outright](#on-the-final-l1-round-a-failed-session-gets-a-metadata-only-stub-except-when-the-network-was-down-or-the-provider-refused-outright)
- [One jq -s test defines a usable findings JSON](#one-jq--s-test-defines-a-usable-findings-json)
- [a findings JSON is validated both when a worker starts and when it finishes, and a rejected file is moved aside](#a-findings-json-is-validated-both-when-a-worker-starts-and-when-it-finishes-and-a-rejected-file-is-moved-aside)
- [a runner-side setup failure is ledgered as `staging`, writes no stub, and leaves the slot empty](#a-runner-side-setup-failure-is-ledgered-as-staging-writes-no-stub-and-leaves-the-slot-empty)
- [the L1 noise gate skips low-signal sessions from the stats sidecar and biases to triage whenever it cannot measure](#the-l1-noise-gate-skips-low-signal-sessions-from-the-stats-sidecar-and-biases-to-triage-whenever-it-cannot-measure)
- [the L1 prompt is assembled by a brace group piped to the engine, with paths passed as literal data](#the-l1-prompt-is-assembled-by-a-brace-group-piped-to-the-engine-with-paths-passed-as-literal-data)
- [the temp-copy path in a findings JSON is rewritten to the real session path with a literal jq replace, not sed](#the-temp-copy-path-in-a-findings-json-is-rewritten-to-the-real-session-path-with-a-literal-jq-replace-not-sed)
- [A runner that cannot set up its L1 workers is a fatal, not an outage deferral](#a-runner-that-cannot-set-up-its-l1-workers-is-a-fatal-not-an-outage-deferral)
- [L1 setup prepares only engines that still have a session to triage](#l1-setup-prepares-only-engines-that-still-have-a-session-to-triage)
- [the L1 worker timeout is a wrapper array set outside the pipe, and a timeout is recognised by exit code plus elapsed time](#the-l1-worker-timeout-is-a-wrapper-array-set-outside-the-pipe-and-a-timeout-is-recognised-by-exit-code-plus-elapsed-time)
- [L1 worker input is built in a fixed order: normalize, cut to the report day, slim, then chunk](#l1-worker-input-is-built-in-a-fixed-order-normalize-cut-to-the-report-day-slim-then-chunk)
- [the L1 worker body is a single-quoted `bash -c` with no apostrophes, and recomputes the session hash inline](#the-l1-worker-body-is-a-single-quoted-bash--c-with-no-apostrophes-and-recomputes-the-session-hash-inline)
- [every L1 worker runs under GNU timeout without --foreground, so the whole process group is signalled](#every-l1-worker-runs-under-gnu-timeout-without---foreground-so-the-whole-process-group-is-signalled)

## Background: A hung worker, a cold token and a deterministic failure (omp-autodream, 2026-08 to 2026-09)

This section was moved here from the former CLAUDE.md. Its original title: "A hung worker, a cold token and a deterministic failure (omp-autodream, 2026-08 to 2026-09)".

Three controls on the L1 loop, each from a night that went wrong in a way the retry budget could not see:

- **Workers are bounded** (`AUTODREAM_L1_TIMEOUT`, default 1200, SIGKILL 30s after the SIGTERM). A worker that never exits holds its `xargs -P` slot forever, so `FANOUT` hung workers stop the whole run with no error and no report; 2026-08-19 and 2026-08-22 each sat wedged for days with every slot taken by workers blocked on their own `node_repl` and `mnemopi_embed` children. GNU `timeout` without `--foreground` signals the whole process group, which is what reaps those grandchildren; a bare kill on the engine would leave them running. macOS ships no `timeout`, so with none on PATH the run degrades to unbounded and says so in run-stats (`l1_timeout_bin: none`). A timeout is recognised by exit 124 or 137 **and** elapsed time at or past the bound: GNU `timeout` propagates the child's own status, so a worker that exits 124 by itself, or is OOM-killed at second zero, looks identical to a real one (measured: a self-killed child returned 137 after 0s under a 100s bound). The timed-out hash goes in `l1-timeouts.txt`, an append-only per-run ledger, because the `.err` is deleted whenever a retry succeeds. The partial findings file is removed, because a worker killed mid-write leaves truncated JSON that would read as a result.
- **The auth warmup** is one serial `ping` per adapter before the parallel dispatch, so `FANOUT` cold workers do not all refresh the same expired token at once. Each adapter prints its own `warmup-argv`: the worker's flags with a system prompt that asks for one word. It is bounded by its own deadline (`AUTODREAM_L1_WARMUP_TIMEOUT`, default 120) because it runs ahead of every recovery path; with no `timeout` binary it is skipped, never run unbounded. The reply must be the word `ok` on stdout with exit 0: a worker that dies prints nothing and exits 0 with only chatter on stderr, which an exit-code check alone calls healthy. `l1_warmup` in run-stats says `ok`, `failed`, `skipped` or `skipped_no_timeout`.
- **The circuit breaker** stops the retry budget after two consecutive rounds that each recovered nothing. The budget is built for a Mac sleeping through a round; against a worker that dies the same way every time it buys nothing and hides the shape (2026-09-08 spent five rounds and 405s writing 16 empty stubs, and the run-stats read as a healthy retry loop). It is a streak, not a comparison of ending counts, which tripped it after one bad round when round 1 had recovered something. It still dispatches once more, at the budget, because the metadata-stub fallback only fires there and an empty slot is not a stub. `l1_breaker_fired: yes` and `l1_rounds_used` (the last round that actually dispatched) keep a short run from reading as a clean one.

## A findings file's error is detected by its top-level key, not by text

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`findings_has_error`)

### Context
The top-level `error` key is what the runner writes for a failed triage and what the L1 prompt tells a worker to write when it cannot fit a transcript. A text match on `"error":` would also fire on a successful file whose evidence quotes one, and with no `.err` to classify it that file would drop out of both sides of the size-attributable share.

### Decision
`findings_has_error` is `jq -e 'type == "object" and has("error")'`.

### Consequences
Do not replace it with `grep`. A parse failure reads as "no error key", which is the caller's separate concern (`L1_FINDINGS_OK`, see `l1-findings-ok-single-value-check`).

## l1_attempt is one engine call with a fixed argument contract, and it judges a chunk by the chunk rule

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`)

### Context
A session is read by one engine call, or by one call per chunk. Both paths need the same failure evidence, network verdict and ledger, and a chunk answer has a different validity rule from a whole-session answer.

### Decision
`l1_attempt TRANSCRIPT ANSWER ERRFILE OUTFILE [CHUNK_NOTE]`: `$1` is the transcript to read, `$2` the findings path the worker is told to write, `$3` and `$4` hold the engine stderr and stdout. It returns 0 only when `$2` ends up holding a findings object. On failure it leaves its evidence in `$3` and the network verdict in `netdown` (and in the ledger), and the caller decides what the failure costs. A set `$5` is the chunk note, and the answer is then judged by `merge-chunks.sh --check` (exactly one object, no `error` key) instead of a findings array alone. `l1_subject` names the session or a chunk of it in the diagnostic line.

### Consequences
That diagnostic line is skipped by `failure-class.sh` on its prefix, so naming a chunk there costs the classifier nothing; any new line added to the `.err` would be read as worker output. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "A chunk failure is a worker failure".

## A serial, bounded, verified auth warmup runs per engine before the parallel L1 dispatch

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `L1_WARMUP` block)

### Context
`FANOUT` workers starting cold at once all find the same expired token and all try to refresh it. See docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09, 'A hung worker, a cold token and a deterministic failure' (the auth warmup bullet).

### Decision
- One serial `ping` per adapter before the dispatch, so the refresh happens once. It never fails the run; the verdict lands in run-stats as `l1_warmup`.
- It is bounded by its own deadline (`AUTODREAM_L1_WARMUP_TIMEOUT`) because it runs ahead of every recovery path (the retry loop, the circuit breaker, `wait_for_network`). An unbounded warmup that hangs on exactly the cold-start condition it targets wedges the run before all of them, with launchd suppressing later triggers while the job stays alive. With no timeout binary it is skipped (`skipped_no_timeout`), not run unbounded.
- `AUTODREAM_L1_WARMUP=0` leaves it `skipped`. The command comes from the engine adapter's `warmup-argv`; an adapter that prints none records `failed`.
- It warms the engine the workers will call, which an `AUTODREAM_L1_ENGINE_<NAME>` override moves.
- The call expands the env array as `${_wenv[@]+"${_wenv[@]}"}`, not `"${_wenv[@]}"`: `run.sh` runs under `/bin/bash` 3.2 with `set -u`, where expanding an EMPTY array is an unbound-variable error. omp's `l1-env` prints nothing, so the pipeline aborted before `timeout` started and the warmup recorded `failed`, blaming a healthy provider.
- The reply must be the single word `ok` (case, surrounding whitespace and punctuation tolerated) with exit 0. Anything else on stdout with exit 0 is a diagnostic, not a reply, and must not read as a healthy provider.
- On failure the log line names both streams (`stdout=[...] stderr=[...]`; an empty stdout IS the finding), because the point of the warmup is that this line exists before 8 workers repeat the failure in parallel and bury it.

### Consequences
- Do not make the warmup fatal, unbounded, or judge it on exit code alone.
- Keep `${arr[@]+...}` for any array that can be empty under bash 3.2.

## A cached L1 result is reused only if this run would accept it now

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`drop_unacceptable_l1_cache`, `l1_record_has_no_engine`, `l1_source_has_engine`, `l1_record_is_runner_only`, `served_verdict`)

### Context
Two reasons to drop cached findings. A no-engine record (`no_engine`, written by `dispatch_l1` when a source had no usable engine: an engine choice naming no accepted adapter, a missing model, a login failing `AUTODREAM_REQUIRE_LOGIN`) is final only for the config that wrote it. And with `AUTODREAM_L1_REQUIRE_SERVED=1`, an answer from a run that did not require the served-model verdict must not be trusted.

### Decision
`drop_unacceptable_l1_cache` runs once, after `reconcile_findings_with_worklist` and before the pre-L1 cache snapshot, so the dispatcher, `l1_missing_count` and `L1_PRECACHED` all see the same set. It counts drops in `L1_CACHE_DROPPED` (run-stats `l1_cache_dropped`) and names them in the log.

- No-engine records are dropped once this run resolves an engine and a model for the session's source (`l1_source_has_engine`). The source comes from `AUTODREAM_SOURCE_MAP`, never from the record, which a worker could have written. Dropping only costs a triage, so the record's shape (`l1_record_has_no_engine`: `no_engine == true` or an error starting `no L1 engine for this session`, with `findings == []`) is enough, and a forged one buys itself a retriage, nothing more.
- With `REQUIRE_SERVED=1`, a findings JSON or chunk answer a model wrote is held to the verdict stored beside it (`<answer>.served`, field 4, from `served_verdict`): no verdict, or any verdict but `match`, is dropped. A record the runner wrote with no model behind it (noise-gate skip, unreadable session, normalize failure, no-engine record, final-round stub) is kept when its `.served` says `runner` and its findings are empty (`l1_record_is_runner_only`). Provenance comes from that marker, which the runner writes, never from the record's keys or shape: a worker can write `error`, `skipped` or `no_engine` as easily as the runner can (#167). The empty findings array is a second guard for a worker that rewrites another session's record in place. A runner record from before the marker is triaged once more and comes back marked.

See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "Who starts the L1 worker" (What answered, and whether it counts; No engine is an error for this run's config).

### Consequences
Known limit shared with the match verdict: every `.served` lives in the findings dir, where an unconfined worker with the Write tool can reach it, so a worker that rewrites ANOTHER session's record and its `.served` together is not caught here. The dispatcher replaces each worker's own `.served` after it exits, which covers the worker's own session only. Closing the cross-session case needs provenance a worker cannot write at all, not a better check on these files. (Since #169, a confined worker can write only its staging dir; see `l1-write-confinement-staging`.)

## chunk inputs are rebuilt each dispatch, chunk answers are cached under a name that covers the chunk and every instruction it was read under

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, chunked triage; `ccfg`)

### Context
A retry should be cheap and a failure partway through a session should not start over, but an answer merged with fresh ones after the prompt, engine, model or session changed would be a stale merge. Chunk answers are model output and must not be mistaken for sessions by anything that globs the findings directory.

### Decision
- Inputs live in `.chunks/<hash>/in/`, are deterministic for an unchanged transcript, are rebuilt on every dispatch, and are removed by the parent after the round whatever happened to the worker.
- Answers are kept under `.chunks/<hash>/` as `NN-<sha1 of the chunk, 12 chars>-<cfg>.chunkout`, with a non-`.json` suffix. `cfg` is the first 8 characters of a sha1 over SESSION_TRIAGE.md, the harness addendum, `src engine model nchunks elided` (the chunk count and omitted count the chunk note states) and the session's stats sidecar (merge-chunks.sh takes the stats fields from chunk 1). The engine is in its own right because one model id can be served by two engines through different system prompts and tools.
- A retry reuses an answer only when it passes `merge-chunks.sh --check`; otherwise only that chunk is redone.
- Chunk scratch is only worth keeping while a retry is pending: inputs never, answers until the session has a findings JSON (a stub included), when the worker removes `.chunks/<hash>`.

### Consequences
A new input to the chunk prompt must go into `ccfg`, or a retry will reuse an answer made under different instructions. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage".

## Chunk counters read the planning and call ledgers, and finished chunk answers count as progress

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_chunk_totals`, `l1_chunk_answers`)

### Context
Chunked triage cost needs to be visible in run-stats, and the L1 circuit breaker would otherwise read a round that finishes most chunks but no whole session as barren and trip after two rounds.

### Decision
`l1_chunk_totals` prints `sessions chunks elided calls`. Sessions and chunks count what the chunker planned, taking the last plan per session from `l1-chunks.txt` (a retry plans again); elided is the chunks dropped from the middle; calls is the number of lines in `l1-chunk-calls.txt`, the engine calls actually made. A night with chunking off, or with nothing over the limit, reads `0 0 0 0`. `l1_chunk_answers` counts finished `*.chunkout` files under `.chunks/`; it is 0 when chunking is off (the directory does not exist), so the breaker is what it was.

See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage" (A chunk failure is a worker failure; What it costs).

### Consequences
Summing plans instead of keeping the last per session would double count every retried session.

## the chunk note tells each worker it holds one chunk of one session, and its wording is matched by the test mock

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_chunk_note`); `tests/mock-claude.sh`; `tests/run-all.sh`

### Context
A chunk worker sees a slice of one transcript. A tool call and its result can fall in different chunks, and the goal and outcome may be in other chunks. The stats sidecar describes the whole session (or the report day), not one chunk, so they must be copied verbatim and not recounted.

### Decision
`l1_chunk_note i n elided` prints the paragraph appended to the worker's prompt before the stats block (SESSION_TRIAGE.md says the stats come last). When chunks were dropped from the middle it adds the omitted count.

### Consequences
The sentence "chunk I of N of ONE session" is matched by `tests/mock-claude.sh` (a `sed` that extracts the chunk index) and asserted in `tests/run-all.sh`; change the text and both together. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage" ("The worker").

## a chunked session is merged only when every chunk answered properly, and one failing chunk's evidence stands for the session

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, chunked branch)

### Context
A chunk answer is untrusted model output. A chunk failure is a worker failure, and a later chunk that succeeds must not overwrite what the first failure said. After a no-route or a permanent provider refusal the other chunks would fail the same way and each would burn a call. The merged answer can only be vouched for as far as its chunks were.

### Decision
- One engine call per chunk, in sequence in the xargs slot. A chunk counts only when `merge-chunks.sh --check` passes (exactly one findings object, no `error` key); anything else is discarded so the retry round redoes that chunk alone, and a finished answer is reused. After `netdown` is `true`, `provider` or `staging` the loop breaks.
- The session-level merge runs only when no chunk failed, and `merge-chunks.sh` refuses anything else itself. A merge that fails anyway drops every cached answer (and their `.served`) so the next round cannot loop on them.
- The merged `.served` verdict is `match` when every chunk answer says match, `mismatch` when any says mismatch, `unmeasured` otherwise (a chunk whose engine reports no model, or an answer cached before the verdict existed).
- When a chunk failed, the first failing chunk's `.err` is copied to `$errlog` (`failure-class.sh` classifies it as it does any); the final-round stub is the session level and only the session level.

### Consequences
See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "A chunk answer is untrusted" and "A chunk failure is a worker failure".

## when the chunker fails, the worker falls back to the capped head/tail slim, never to the uncapped input

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, chunker fallback)

### Context
The chunker can fail (a full disk, an unwritable directory). Handing one worker the whole uncapped slim is the failure chunking exists to avoid. A transcript under `AUTODREAM_SLIM_BYTES` was never slimmed, so there may be no slim file yet.

### Decision
On a chunker failure the worker resets to one chunk, removes the chunk inputs, and builds the exact off-path input: the head/tail slim (`AUTODREAM_SLIM_FULL=0`, `AUTODREAM_SLIM_RESHAPE=0`) of the same input (`slimsrc`, or `readpath` when it was never slimmed, creating the slim file from it). If the slimmer fails too, it cuts the first `AUTODREAM_SLIM_CAP` bytes (default 262144). If that also fails it sets `l1_blocked=1`: no engine call this round, the output stays absent, the session is retried, and the last round writes the stub.

### Consequences
Do not replace the fallback with the full slim to "save" a failing session. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "If the chunker fails".

## The L1 circuit breaker counts a streak of barren rounds and still dispatches the stub round

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `L1_NOPROGRESS`, `round_start_missing`, the breaker in the round loop)

### Context
The retry budget is built for a Mac sleeping through a round, and against that it works. Against a worker that dies the same way every time it buys nothing and hides the shape: 2026-09-08 spent all five rounds and 405s to write 16 empty stubs, and the run-stats it left (`l1_rounds_used` 5 of 5, `l1_timed_out` 0) read as a healthy retry loop rather than as five identical failures. See docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09, 'A hung worker, a cold token and a deterministic failure' (the circuit breaker bullet).

A comparison against the previous round's ending count is wrong: round 1 taking 3 missing down to 1 and round 2 recovering none leaves both ends equal at 1, which tripped the breaker after a single bad round and logged the lie that rounds 1 and 2 both recovered nothing.

### Decision
- `L1_NOPROGRESS` is a streak of consecutive rounds that recovered nothing; any recovery (fewer missing, or more chunk answers) resets it to zero. "Did THIS round recover anything" is answered from counts sampled before the dispatch (`round_start_missing`, `round_start_chunks`), not inferred from the previous round's ending count.
- Two consecutive barren rounds mean the failure is deterministic, not transient.
- The breaker still dispatches once more: the metadata-stub fallback fires only when the dispatcher sees `AUTODREAM_CURRENT_ROUND` at the budget, so breaking out here without that round would leave the slots empty, and an empty slot is not a stub. It jumps to the last round rather than skipping to the end: three dispatches instead of five, with the same artifacts on disk.
- The `round -lt L1_ROUNDS` guard matters at `AUTODREAM_L1_ROUNDS=2` (the suite runs low budgets): there the final round IS the stub round and has already run.
- `l1_breaker_fired: yes` and `l1_rounds_used` (the last round that actually dispatched) keep a short run from reading as a clean one.

### Consequences
- Do not replace the streak with an end-to-end count comparison.
- Do not break out of the loop without running the stub round.

## a failure that retrying cannot change leaves a structured error record, not a missing file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: unreadable session, normalize refusal, no engine)

### Context
A session path that enumeration found but that is gone or unreadable by dispatch time would send a worker into a cat/wc/Read retry loop. An adapter's normalizer can refuse a transcript (duplicate id, dangling parent, cycle, missing jq). A session can resolve no engine (not executable, no model, no accepted adapter, failed `AUTODREAM_REQUIRE_LOGIN`). In all three a retry in the same run cannot change the answer.

### Decision
The worker writes `{session_path, error, findings: []}` to `$output` plus a runner `.served` marker and exits 0:
- unreadable at dispatch: `session file not readable at dispatch`;
- normalize refused: `session could not be normalized by the <adapter> adapter: <reason>`, where the adapter's reason (first 300 bytes of its stderr) is kept so a refusal can be told from an environment fault by reading the record;
- no engine: the same shape with `no_engine: true`.

The record is skipped by the later rounds and counted by `l1_findings_with_error`. The no-engine case is deterministic for this run only: the engine choice, the model pin and the login check all come from the config, which can change, so `no_engine` marks the record and a later run whose config resolves an engine drops it and triages the session (`drop_unacceptable_l1_cache` in the parent).

### Consequences
Do not "fix" these by deleting the record so the next round retries. For the no-engine marker see docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "No engine is an error for this run's config, not forever".

## the L1 dispatcher hands each session path to its worker NUL-delimited, one argument per worker

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1`)

### Context
`xargs -I {}` turned a tab into a space, deleted a backslash and died on a quote with "unterminated quote", taking the whole night's dispatch with it (#54). `-I` also caps the substituted argument at 255 bytes.

### Decision
`tr '\n' '\0' < "$SESSIONS_LIST" | xargs -0 -n 1 -P "$FANOUT" bash -c '...' _` passes each path byte for byte as `$1`. `-n 1` without `-I` lifts the 255-byte limit. A newline cannot reach the list because enumeration refuses it (`sessions.txt` is line-based).

### Consequences
Do not return to `-I {}`. A new field in `sessions.txt` that could hold a newline breaks the invariant that makes the `tr` safe. See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to".

## The L1 dispatcher gets its fixed configuration from exported environment variables

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `export` lines and the adapter/model maps before L1)

### Context
The L1 workers run inside `xargs` subshells that share no state with the runner, and a worker holds the Write tool, so anything the next worker reads from the findings dir can be rewritten. See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, 'Who starts the L1 worker' ("The source map is held in the environment, not read from the findings dir") and 'Reading a long session: chunked triage' ("One gate, off is the old behaviour").

### Decision
- `L1_CHUNKING` is the one switch for chunked triage, exported with `CHUNKER`, `MERGER`, `AUTODREAM_L1_CHUNK_BYTES` and `AUTODREAM_L1_MAX_CHUNKS`: 0 leaves the slimmer in its default mode and never reaches the chunker or the merge.
- Which adapter runs each session (`AUTODREAM_SOURCE_MAP`) and which model each adapter's workers use (`AUTODREAM_L1_MODELS`) are fixed before the first model call and held in the environment. The models are resolved once per adapter, not per session.
- The report-day window (`WINDOW_ON`, `SESSION_WINDOW`, `WIN_START_EPOCH`, `WIN_END_EPOCH`, `TARGET_DATE`) is exported for the dispatcher subshell, which uses it to cut a multi-day transcript.
- `AUTODREAM_L1_ROUNDS` is exported so the dispatcher can tell whether this is the last retry round, which gates the metadata-stub fallback.
- `TIMEOUT_BIN` is empty when no timeout binary exists, which the worker treats as run-unbounded (recorded as `l1_timeout_bin: none`).

### Consequences
- Do not make the worker re-read `sessions-source.txt` or any findings-dir file for these values.
- Test: `test_l1_engine_cannot_be_redirected_by_a_worker` in `tests/run-all.sh` (named in docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation).

## a failed L1 worker keeps its stdout, exit code and elapsed time as evidence

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `outlog`, `l1_attempt`)

### Context
The worker printed its whole diagnosis to stdout and that used to go to `/dev/null`, so every failure looked the same: an `.err` holding the single line "Working..." and a hand-written sentence from the runner. On 2026-09-04 (omp-autodream) a dead network hid behind three fine transcripts and the report blamed their size. Without the exit code a provider refusal and a killed process read identically.

### Decision
Each engine call writes stdout to its `$4` and stderr to its `$3`: `<hash>.json.out` and `<hash>.json.err` for a whole session, `NN.out` and `NN.err` under `.chunks/<hash>/` for a chunk. When the call produces no findings JSON, `l1_attempt` appends to the `.err` the diagnostic line, `worker exit code: <rc> after <n>s`, and the last 40 lines of stdout under `--- worker stdout, last 40 lines ---` (or `worker stdout was empty`), then removes the `.out`, whose tail is now in the `.err`. An answer that exists but fails the validity check is treated as a failure too: the `.err` gets `worker wrote output with no usable .findings key; treating as a failure` and the first 2000 bytes of what was written, and the file is removed. The `.err` survives every failure and is deleted only when the worker succeeds (a chunk's `.err` and `.out` likewise).

### Consequences
The original comment said the `.out` is kept when the worker fails; the code removes it once its tail is in the `.err`, so the `.err` is the only evidence file left. `bin/failure-class.sh` reads these lines by exact text, so changing their wording changes failure classification. See docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "A failed worker leaves its evidence, and the failure is classified".

## a failed L1 worker gets a three-state network verdict from its own engine's host and a provider-refusal verdict, ledgered append-only per round

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt` failure path; `l1-netdown.txt`; `bin/failure-class.sh` `provider_is_permanent`)

### Context
Without a reachability check, a failure caused by a sleeping Mac is indistinguishable from a transcript the worker could not digest, and the oversized gate would count it as evidence it is not. An absent `curl` exits 127; the first version read that as "no route", so a host without curl would have excluded every worker failure from the oversized gate, permanently and invisibly. An omp worker on deepseek failing while api.anthropic.com answers is not "network up", and the reverse is not an outage. A bare hash in the ledger was wrong: the ledger is truncated once per run, so a round-1 outage entry survived into round 5 and excluded a round-5 failure with a completely different cause. A reachable network is not a working provider: a billing refusal (Z.ai code 1113, 2026-10-01 and 10-02) answers curl fine, so `netdown` was false and the stub consumed the session permanently.

### Decision
- One `curl` (5 s) runs only on the failure path, to the host the failing engine talks to (`AUTODREAM_L1_PROBE_URLS`, resolved before any model ran, keyed by source), never a fixed host.
- Three states: exit 126/127 is "cannot tell" (`unknown`: never ledgered and never suppresses the stub); an empty or `000` code is `true` (down); anything else is `false`.
- When the network is not down, `provider_is_permanent` on the `.err` (no balance or quota, Z.ai 1113, DeepSeek 402) sets `netdown=provider`: no stub, the session is left for a later run. A transient 429 or 5xx keeps its stub.
- Every classified failure is appended as `<hash> <round> <state>` and a line is never rewritten. Readers take the highest round per hash, so the last attempt counts. Append-only also keeps the parallel xargs subshells from racing, as for `l1-timeouts.txt`.

### Consequences
See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, "A dead network or a refusing provider defers the date; it never publishes a short corpus". A new permanent-refusal wording goes into `failure-class.sh` with a matrix row.

## on the final L1 round a failed session gets a metadata-only stub, except when the network was down or the provider refused outright

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, failure branch; `l1_missing_count`)

### Context
Without a stub the session is invisible to `L1_ERRORED` and the L2 aggregator and disappears into a silent `.err` file (2026-06-11 self-audit: 12 `.err` files with `l1_findings_with_error=0`). But a stub carries a `.findings` key, so it satisfies `l1_missing_count`: writing one marks the session done. MISSING drops to zero, the run never defers, L2 publishes on a short corpus, and the next run skips the session because its slot is filled.

### Decision
Earlier rounds leave `$output` absent so the next round retries. Only when `AUTODREAM_CURRENT_ROUND` has reached `AUTODREAM_L1_ROUNDS` (default 5, passed through the environment) does the worker write a stub (`error: worker exited without findings JSON after N rounds`, `meta` with bytes, lines, slimmed and any chunk counts, a runner `.served` marker). When `netdown` is `true`, `provider` or `staging` no stub is written and the log says the session is left for a later run: leaving the slot empty is what makes the retry work, and the run defers instead, so the silent-failure concern is answered by the deferral and not the stub.

### Consequences
Never write the stub on an outage branch. See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, "A dead network or a refusing provider defers the date" and "A hung worker, a cold token and a deterministic failure" (the breaker still dispatches once more at the budget because the stub only fires there).

## One jq -s test defines a usable findings JSON

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`L1_FINDINGS_OK`, `l1_missing_count`)

### Context
`jq -e` judges only the LAST value in a file, so a forged object followed by a good one passed the old `.findings | arrays` check and L2 read the first (#167). `merge-chunks.sh --check` is the same rule for chunk answers.

### Decision
`L1_FINDINGS_OK='length == 1 and (.[0] | type == "object" and (.findings | type) == "array")'`, run under `jq -s`: exactly one JSON value, an object, with a `findings` array. It is `export`ed because the worker is a separate `bash -c`. `l1_missing_count` counts a session missing unless `jq -s -e "$L1_FINDINGS_OK"` accepts its findings file, the same check the dispatcher applies on the way out. A session whose artifact hash cannot be derived or validated (`session_hash`: 12 hex characters) is counted missing too. An unvalidated hash would have the session counted missing forever, and the retry loop would re-dispatch it every round.

See docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "A failed worker leaves its evidence" (Non-empty is not valid).

### Consequences
Every reader of findings validity must use this variable, not a private `jq -e .findings`.

## a findings JSON is validated both when a worker starts and when it finishes, and a rejected file is moved aside

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, `l1_attempt`, `L1_FINDINGS_OK`)

### Context
`jq -e .findings` is truthy for a string or an object, so `{"findings":"oops"}` counted as a finished session and reached L2 (#167). A non-empty file that is malformed, or has no `.findings` array, is not a completed triage. On the way out, such a file used to take the success branch: diagnostics were deleted and the file left for L2, and by the next round the exit code, stdout capture and reason were gone. A chunk failure with the old file still in place skipped the final stub and the rejected file reached L2, because every later step reads a non-empty `$output` as "this round produced a result".

### Decision
- On the way in, the worker runs `jq -s -e "$L1_FINDINGS_OK"` and exits 0 only for a valid result. The filter comes from the environment (defined once in the parent) because the body is single-quoted, and `l1_missing_count` must run the same check.
- A file that fails is moved to `<hash>.json.rejected` (no `*.json` glob reaches it; removed if the move fails) and its `.served` is deleted.
- On the way out, `l1_attempt` checks the answer with `merge-chunks.sh --check` for a chunk and with `L1_FINDINGS_OK` otherwise. A bad write appends `worker wrote output with no usable .findings key; treating as a failure`, keeps the first 2000 bytes as evidence and removes the file, so the failure keeps its exit code and stdout.

### Consequences
Never loosen the check to `jq -e .findings`. Keep the in-check, the out-check and `l1_missing_count` on one definition. See docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "Non-empty is not valid".

## a runner-side setup failure is ledgered as `staging`, writes no stub, and leaves the slot empty

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_infra_fail`, the decision point after the rounds)

### Context
A failure before the engine starts (no staging root, no stage, no state directory, no sandbox) says nothing about the session. The final-round metadata stub would fill the slot, satisfy the missing-work check and let a report publish over sessions that were never triaged.

### Decision
`l1_infra_fail` sets `netdown=staging`, appends `<hash> <round> staging` to `l1-netdown.txt`, adds an explanatory line to the `.err` and returns 1. The stub branches treat `staging` like an outage (no stub). When it is what the last round left missing, the run treats it as a fatal (banner, `fatal:` in run-stats, the marker the next run reads), not an outage deferral.

### Consequences
Waiting heals nothing here, so it is a fatal and not a deferral; with no findings JSON `unassembled_dates` would never name the date. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A host with no working sandbox says so".

## the L1 noise gate skips low-signal sessions from the stats sidecar and biases to triage whenever it cannot measure

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, noise gate)

### Context
Gating needs no model call: it reads the mechanical stats sidecar (`session-stats.sh`, computed once during enumeration). Subagent transcripts and tool-heavy sessions are legitimate work that is often short on user turns.

### Decision
The gate writes a `skipped: below_noise_gate` record when the sidecar says a session is not a sidechain, has fewer than 5 tool calls, and either has fewer than `AUTODREAM_MIN_USER_TURNS` (default 2) user turns or a computable duration under `AUTODREAM_MIN_MINUTES` (default 1). Either condition alone gates. A duration of 0 (zero or one timestamped line) never gates on the duration rule, and a missing or unparseable sidecar never gates: both bias to triage.

### Consequences
The cost of biasing to triage is one wasted model call, which is cheaper than dropping a real session, so keep the bias. A broken sidecar degrades several counters at once and is counted by `stats_sidecars_unparseable`. See docs/adr/0010-rollup-and-run-stats.md#background-degraded-measurements-must-say-so-not-read-as-zero, "Degraded measurements must say so, not read as zero".

## the L1 prompt is assembled by a brace group piped to the engine, with paths passed as literal data

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`)

### Context
Passing the paths as `KEY=value` made a worker try to `$`-expand them in a shell; there is no such variable, so they expanded to nothing and the call failed (the failure mode that broke earlier runs). A `prompt=$(...)` capture strips trailing newlines, which would glue the SESSION_TRIAGE.md body onto the end of the output-path line and corrupt it.

### Decision
`l1_attempt` prints the transcript path and the output path as literal text lines, then `cat`s SESSION_TRIAGE.md (plus the adapter addendum, day note, chunk note and stats block) from one `{ ...; } | engine` brace group, so the blank-line separator printed by `printf` survives.

### Consequences
Any state the engine side of the pipe needs must be set outside the brace group (see the timeout wrapper ADR). Do not move the assembly into a `$(...)`.

## the temp-copy path in a findings JSON is rewritten to the real session path with a literal jq replace, not sed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, success path)

### Context
The worker read a slim, normalized or day-cut copy, so the findings name that copy. `sed` would read a `#` or `&` in the session path as part of its own syntax, and a quote or backslash in the path would break the JSON.

### Decision
`jq --arg a <copy> --arg b <session> 'walk(if type == "string" then split($a) | join($b) else . end)'` replaces the copy's path inside every JSON string literally, then the copies are removed.

### Consequences
Do not switch to `sed` on the raw JSON text. The loop runs over the slim, normalized and day-cut copies in turn, and a rewrite that fails leaves the findings file as it was (the `.rw` temp is removed).

## A runner that cannot set up its L1 workers is a fatal, not an outage deferral

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: the `staging` row check after the round loop)

### Context
A setup failure (stage directory, engine state, sandbox) heals nothing by waiting. A deferral would leave no report, no banner and (with no findings JSON) no `unassembled_dates` entry, every night. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, 'A host with no working sandbox says so' (the setup-failure sentences).

### Decision
When sessions are still missing and the last round that dispatched has a `staging` row in `l1-netdown.txt`, `run` removes the stage root, wipes the work bucket, then `log_fatal` and `fatal_exit` and returns 1. The fatal posts the banner and leaves the marker the next run reads. No stub is written, so the date has no report and a later run retries it.

### Consequences
- This check runs before the network/provider deferral check; reordering them turns a setup failure back into a silent deferral.

## L1 setup prepares only engines that still have a session to triage

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_missing_engines`, `l1_confine_setup`)

### Context
Preparing an engine nothing will run fatals a night whose findings are already complete (a retry after L2 failed) over a database that no worker needs.

### Decision
`l1_missing_engines` lists, one per line, the engines (from `AUTODREAM_SOURCE_MAP` then `AUTODREAM_L1_ENGINES`) that still have a session with no valid findings JSON. `l1_confine_setup` prepares only those (when none are missing it prepares nothing, sets `L1_CONFINED_STAT` to `n/a` with the reason "no L1 work this run: every session already has findings", and lists every engine in `L1_SETUP_SKIPPED`), and names the rest in `L1_SETUP_SKIPPED` so a worker that reaches a skipped engine anyway fails its attempt instead of running unconfined.

### Consequences
See `l1-write-confinement-staging`. A session whose hash cannot be derived is skipped here (its findings file cannot be named); `l1_missing_count` still counts it missing.

## the L1 worker timeout is a wrapper array set outside the pipe, and a timeout is recognised by exit code plus elapsed time

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `l1wrap`; `l1_attempt`: `l1start`, timeout check)

### Context
A worker that never exits holds its `xargs -P` slot forever (2026-08-19 and 2026-08-22 each sat wedged for days). A brace group in a pipeline runs in a subshell, so an assignment made inside it is invisible to the right-hand side. GNU `timeout` propagates the child's own status, so a worker that exits 124 by itself, or that the OOM killer SIGKILLs at second zero, looks like a real timeout (verified against coreutils 9.11: a self-killed child returned 137 after 0s under a 100s bound). `t0` is taken before validation, the noise gate and slimming, so a large transcript can burn real time before `timeout` is launched.

### Decision
- `l1wrap=("$TIMEOUT_BIN" -k "$L1_KILL_GRACE" "$AUTODREAM_L1_TIMEOUT")` is an array set outside the brace group, so the wrapper cannot silently disappear. (`${TIMEOUT_BIN:+...}` also handles a path with spaces; the array is used because it reads as an optional argv prefix.)
- The worker's exit status is `PIPESTATUS[1]`: index 0 is the prompt-assembling brace group, index 1 the engine side.
- `l1start` is stamped inside `l1_attempt`, right before the engine starts, never reused from `t0`.
- A timeout is declared only when `TIMEOUT_BIN` is set, the exit code is 124 or 137, and elapsed time is at least `AUTODREAM_L1_TIMEOUT`. 137 is 128+SIGKILL, which is what the `-k` grace period escalates to. Second resolution leaves a one-second boundary window against a twenty-minute bound.
- A timeout appends a line to the `.err` and the hash to `l1-timeouts.txt`. The ledger exists because the `.err` is truncated by the next retry and deleted whenever the worker succeeds or leaves output, so a timeout that later succeeds would vanish from the stats; the ledger is per-run and append-only.
- A timeout removes the findings file: a worker killed mid-write leaves truncated JSON that would read as success, delete the errlog and feed partial input to L2. The session retries like any other failure.

### Consequences
Without GNU `timeout` (macOS ships none) the run degrades to unbounded and says so (`l1_timeout_bin: none`). See docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09, "A hung worker, a cold token and a deterministic failure".

## L1 worker input is built in a fixed order: normalize, cut to the report day, slim, then chunk

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body)

### Context
Oversized transcripts (multi-MB, base64 images, giant tool outputs) blow the worker's token budget so it errors instead of triaging. An omp session is an append-only tree. A transcript can span more than the report day, and a worker handed a slice has no other way to know the first turn it reads is not the start of the session.

### Decision
1. An adapter listed in `AUTODREAM_NORMALIZE_SOURCES` (omp) is linearized first to the live conversation, and the worker reads `<hash>.norm.jsonl`. A session the adapter cannot prove is the live conversation gets a deterministic error record rather than a worker reading abandoned branches.
2. When the window is on, `session-window.sh day-file` cuts that to the report day. Status 0 wrote a slice, 1 means nothing to cut, 2 means the helper failed; the last two read the whole transcript, because a failed cut must cost a larger read and never the session. The stats sidecar the noise gate read was cut the same way. A worker handed a slice is told so in a `## Report day` paragraph.
3. Over `AUTODREAM_SLIM_BYTES` (default 262144) the transcript is slimmed and the worker reads the slim. While chunked triage is on the slimmer keeps every conversation line and drops Claude Code bookkeeping first (`AUTODREAM_SLIM_RESHAPE` and `AUTODREAM_SLIM_FULL` follow `L1_CHUNKING`). Off, both are 0 and it writes what it always wrote.
4. After a successful run the findings `session_path` is rewritten back to the original.

### Consequences
Normalize first, cut second: cutting the raw tree leaves entries whose parent was cut away, which `linearize.sh` refuses. See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to" and "Reading a long session: chunked triage".

## the L1 worker body is a single-quoted `bash -c` with no apostrophes, and recomputes the session hash inline

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body)

### Context
The worker is one single-quoted string passed to `bash -c`. A `'` anywhere in it, including a comment, silently ends the quoting while `bash -n` still passes. The body runs in a separate process, so functions defined in the parent (`session_hash`) are not in scope. An empty hash would send every worker to the same artifact.

### Decision
The body contains no apostrophes, comments included. It recomputes the hash inline with the same contract as the parent's `session_hash` (`bin/lib-project.sh`: 12 hex characters of the sha1 of the path) and exits 0 when the `shasum` fails or the result is not 12 lowercase hex characters, so a failed `shasum` cannot make workers share a file. Data the body needs crosses in the environment (for example `L1_FINDINGS_OK`).

### Consequences
When editing the body, re-run `bash -n` and the suite, and never add an apostrophe. If `session_hash` in the parent changes, change the inline copy with it. See docs/adr/0011-self-pollution.md#background-self-pollution-the-eating-its-own-tail-bug, "Self-pollution" ("Watch the apostrophes") and "Which day a session belongs to".

## every L1 worker runs under GNU timeout without --foreground, so the whole process group is signalled

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`AUTODREAM_L1_TIMEOUT`, `L1_KILL_GRACE`, `TIMEOUT_BIN`; the `l1wrap` prefix in `dispatch_l1`)

### Context
A worker that never exits holds its `xargs -P` slot forever, so FANOUT hung workers stop the whole run with no error and no report. 2026-08-19 and 2026-08-22 each sat wedged for days with all 8 slots taken by workers blocked on their own `node_repl` and `mnemopi_embed` children (omp-autodream).

### Decision
`dispatch_l1` prefixes the engine with `timeout -k "$L1_KILL_GRACE" "$AUTODREAM_L1_TIMEOUT"` (`AUTODREAM_L1_TIMEOUT` defaults to 1200 s; `L1_KILL_GRACE` is fixed at 30 s in the script and cannot be set from the environment). GNU timeout invoked WITHOUT `--foreground` runs the command in a new process group and signals the group, which reaps the grandchildren; a bare kill on the engine would leave them reparented (to launchd on macOS) and running. The worst-case bound is `AUTODREAM_L1_TIMEOUT + L1_KILL_GRACE`. `TIMEOUT_BIN` is `timeout` or else `gtimeout`; macOS ships neither in its base install, so with none on PATH (`TIMEOUT_BIN` is resolved after the PATH augmentation) the run degrades to unbounded instead of gaining a hard coreutils dependency, and run-stats records which way it went (`l1_timeout_bin`). See docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09, "A hung worker, a cold token and a deterministic failure".

### Consequences
Never add `--foreground`: it stops signalling the group and the grandchildren survive. The unbounded fallback is deliberate: it logs a WARNING ("no timeout binary found (brew install coreutils); L1 workers run unbounded and one hang stops the run") and run-stats reads `l1_timeout_bin: none`; the serial auth warmup is skipped too (`skipped_no_timeout`), since an unbounded warmup can wedge the run. Startup validation of the knob is in `numeric-knobs-validated-at-startup`.
