# 0007: Long sessions: chunked triage

Status: accepted · Governs: `bin/chunk-transcript.sh`, `bin/merge-chunks.sh`, `bin/slim-transcript.sh`, `bin/run.sh`

This record holds 11 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Reading a long session: chunked triage](#background-reading-a-long-session-chunked-triage)
- [the chunker keeps every line, cuts only at line boundaries, and when over the cap drops the middle](#the-chunker-keeps-every-line-cuts-only-at-line-boundaries-and-when-over-the-cap-drops-the-middle)
- [a chunk answer is untrusted, `--check` judges exactly one value, and the merge refuses to merge around a bad one](#a-chunk-answer-is-untrusted---check-judges-exactly-one-value-and-the-merge-refuses-to-merge-around-a-bad-one)
- [the chunk merge is mechanical, with a fixed rule for each field when answers disagree](#the-chunk-merge-is-mechanical-with-a-fixed-rule-for-each-field-when-answers-disagree)
- [the pre-pass never invents a key, never stringifies null, and strips an image where its data lives](#the-pre-pass-never-invents-a-key-never-stringifies-null-and-strips-an-image-where-its-data-lives)
- [`AUTODREAM_SLIM_FULL=1` keeps every line, applies no byte cap and appends no footer](#autodream_slim_full1-keeps-every-line-applies-no-byte-cap-and-appends-no-footer)
- [an oversized transcript is read through a lossy, representative slim](#an-oversized-transcript-is-read-through-a-lossy-representative-slim)
- [the slim output is mode 0600 even into a destination the caller already made](#the-slim-output-is-mode-0600-even-into-a-destination-the-caller-already-made)
- [reshape drops Claude Code bookkeeping by a denylist of record types and attachment subtypes, never an allowlist](#reshape-drops-claude-code-bookkeeping-by-a-denylist-of-record-types-and-attachment-subtypes-never-an-allowlist)
- [the jq pre-pass strips tool payloads for both the Claude Code and the OMP schema](#the-jq-pre-pass-strips-tool-payloads-for-both-the-claude-code-and-the-omp-schema)
- [chunked triage is one switch, on only when asked for and when both helpers are found](#chunked-triage-is-one-switch-on-only-when-asked-for-and-when-both-helpers-are-found)

## Background: Reading a long session: chunked triage

This section was moved here from the former CLAUDE.md. Its original title: "Reading a long session: chunked triage".

Layer 1 used to read an oversized transcript through `slim-transcript.sh`: the first 400 and last 200 lines of the raw stream, cut to 400 characters. Measured 2026-10-02 on a real 3,479-line session, only 36% of the lines were conversation (24% hook and reminder attachments, 21% `mode`, `permission-mode`, `last-prompt` and `bridge-session` records), the head and tail were mostly that noise, and the timestamp sat after the message so the line cut deleted it: the worker saw 17% of the lines and about 2% of the text, and returned nothing. Issue #12 stayed closed behind a failure-rate gate because the failure rate was never the problem; the yield was. A controlled test on one session had Haiku find nothing on the old slim and on the full conversation, and Opus find a real permission-gate issue only on the full conversation, so there are two causes (what the worker is shown, and what Haiku makes of it) and this change fixes the first. On this host's 2026-10-02 (70 oversized sessions after the day cut) the old view showed 1,330 of the 6,099 conversation lines and the new one shows all of them in 1.9 MB instead of 2.9 MB.

- **One gate, off is the old behaviour.** `AUTODREAM_L1_CHUNK_BYTES` (default 0, which is off; 300000 is the value it was replayed with) and `AUTODREAM_L1_MAX_CHUNKS` (default 8) are validated at startup like the timeout knobs (`10#`, so `08` is not an invalid octal). `L1_CHUNKING` is 1 only when the knob is above 0 and BOTH `chunk-transcript.sh` and `merge-chunks.sh` are found with `find_lib`; a missing helper reads the old way and logs a WARNING. With it 0 the slimmer is called with `AUTODREAM_SLIM_RESHAPE=0 AUTODREAM_SLIM_FULL=0` (its defaults), no chunker, no merge, no chunk note, no ledger files: on a fixture run against the previous runner, every transcript a worker read, every prompt and every findings JSON was byte-identical, and so were the 70 findings of a replay of 2026-10-02.
- **The slimmer.** `RESHAPE=1` drops bookkeeping by a DENYLIST (record types `bridge-session last-prompt permission-mode mode atis-latch ai-title queue-operation file-history-snapshot file-history-delta dev-mods`, attachment subtypes that are hook and reminder machinery, `system/stop_hook_summary` and `system/turn_duration`) and rebuilds `user`, `assistant`, `attachment` and `system` records with `type` and `timestamp` first and the message reduced to `role` and `content`. It is a denylist of attachment subtypes too, because an unknown subtype costs bytes when kept and costs signal when dropped, and an allowlist of user and assistant would delete every OMP record. Before dropping a record type, grep the prompts for it: `skill_listing` and `queued_command` are named by SESSION_TRIAGE.md and the first draft's denylist caught one of them. OMP and unknown-schema records come out of the reshape exactly as without it (the pre-pass has always re-serialised every record and stripped OMP toolResult payloads, so they are not raw-identical to the file, and the test says so). `FULL=1` keeps every surviving line: no head/tail, no cap, no footer, because the footer would land in the last chunk as a line that is not JSON. Lines are still cut to `AUTODREAM_SLIM_MAXLINE`, so "each chunk parses as JSONL" holds for the chunker's own contract (it splits only at line boundaries) and not for a slimmed input, whose long lines are cut.
- **The chunker** counts bytes (`LC_ALL=C awk`), cuts only at line boundaries, makes a line longer than the limit a chunk of its own, and keeps the first ceil(MAX/2) and last floor(MAX/2) chunks when there are more than MAX: the start holds the goal and the end holds the outcome. A cap of 1 keeps the first chunk only. It prints `COUNT ELIDED` and leaves no file behind on a failure. A tool call and its result are separate lines, so a cut puts one at the end of a chunk and the other at the start of the next; the chunk note tells the worker to expect that.
- **The worker.** The input over the limit is split into `findings/<date>/.chunks/<hash>/in/chunk-NN.jsonl`, one engine call per chunk IN SEQUENCE in the same xargs slot, each answering to `.chunks/<hash>/NN-<sha of the chunk>-<cfg>.chunkout`. The name carries the chunk's hash and an 8-character digest of everything else the answer depended on (SESSION_TRIAGE.md, the harness addendum, the engine and model, and the session's stats sidecar, which the merge copies from chunk 1), so a retry reuses an answer only for an identical chunk read under identical instructions: a changed prompt, model or session redoes the chunk instead of merging a stale answer with fresh ones. The `.chunkout` suffix and the hidden directory keep every consumer that globs `*.json` away from them (`findings_json_count` and the gated count scan the findings dir with `-maxdepth 1`, which never reaches `.chunks/`; the suffix is the second guard, for any consumer that walks deeper). The chunk note goes before the stats block, because SESSION_TRIAGE.md says the stats come last, and says the stats describe the whole session. The merged findings carry `meta: {chunks, chunks_elided}` and each finding a `chunk` tag.
- **A chunk answer is untrusted.** `merge-chunks.sh --check` is the single definition (one JSON value, an object, no `error` key, a `findings` array) used on the way out of every call, before a cached answer is reused, and again inside the merge, which refuses (exit 3, nothing on stdout) when any chunk fails it. Plain `jq -e .findings` judges only the LAST value in a file and is truthy for a string, which is how an error object followed by a good one, or `{"findings":"oops"}`, used to count. A session is merged only when every chunk passed; otherwise nothing is published for it that round, the failed chunk is redone alone next round, and on the last round the session gets the ordinary stub, now carrying `meta.chunks`, never a merge of the chunks that did answer.
- **A chunk failure is a worker failure.** `l1_attempt` writes the same evidence to a per-chunk `NN.err` and the first failing chunk's is copied to `<hash>.json.err`, so a later chunk that succeeds cannot erase it. The chunk is named inside the existing `worker produced no findings JSON for ...` line, which `failure-class.sh` skips by prefix; any NEW line in the `.err` would be read as worker output (before the exit-code line) or as worker stdout (after it, until a known marker), so none was added. A no-route or permanent provider refusal ends that session's chunk loop, since the other chunks would fail the same way and each burns a call, and defers the date as for any worker. The circuit breaker counts a new chunk answer as progress, because a round that finishes most chunks and no whole session is not barren and would otherwise trip it after two rounds. `l1_timed_out` counts sessions (the ledger is `sort -u` by hash), so several chunk timeouts are one.
- **If the chunker fails**, the worker falls back to the exact off path (the default-mode slim of the same input), never to the uncapped full slim; if that cannot be made either it reads nothing this round and the last round writes the stub.
- **Cleanup without a trap.** There is no per-run temp directory and no signal trap in the worker, and a trapped TERM is deferred until the foreground engine exits (the adapter says so), so chunk inputs, which are transcript text, are mode 0600 and rebuilt every dispatch, removed by the worker when it can and by the dispatcher after every round whatever happened. Answers stay until the session has a findings JSON, a stub included.
- **What it costs.** A session that completes costs up to MAX_CHUNKS calls (8) plus one per retry of a failed chunk, and the absolute ceiling is MAX_CHUNKS x `AUTODREAM_L1_ROUNDS` (40) if every call fails, which the circuit breaker cuts to about three rounds. A night with no retries costs up to (oversized sessions x 8) + (the rest x 1): measured 73 calls for 70 oversized sessions on one real day, 560 at the cap. A session's wall time is up to 8 x `AUTODREAM_L1_TIMEOUT` since its chunks run in sequence. `run-stats.txt` has `l1_chunk_bytes`, `l1_max_chunks`, `l1_chunked_sessions`, `l1_chunks` (the workers the sessions needed), `l1_chunk_calls` (calls actually made) and `l1_chunks_elided` (chunks the cap dropped: a nonzero value is a degraded read).
- **omp** chunks the linearized copy after the day cut, in that order: `normalize`, then `day-file`, then slim, then chunk. The first chunk opens with the `autodream_meta` header.

Tests: `tests/chunk-transcript.sh` and `tests/merge-chunks.sh` are unit suites; the slimmer's modes are in `tests/slim-transcript.sh`; the integration cases are the `test_chunk*` functions in `tests/run-all.sh` with the mock's `MOCK_MODE=chunked`, `MOCK_FAIL_CHUNK`/`MOCK_FAIL_KIND`/`MOCK_FAIL_ONCE` and `MOCK_BAD_CHUNK`/`MOCK_BAD_KIND`. Run them with `TMPDIR` OUTSIDE every checkout and SHORT: the changelog tests run `git` against whatever repo contains `TMPDIR` when `git init` is denied, and `xargs -I {}` refuses an argument of 255 bytes or more.

## the chunker keeps every line, cuts only at line boundaries, and when over the cap drops the middle

Status: accepted · Date: 2026-11-21 · Code: `bin/chunk-transcript.sh` (the whole script)

### Context

A day of a long session slims to far more than one worker can read. Eliding its middle is how Layer 1 came to see about 2% of a conversation. docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage", has the measurements and the worker side of the design. `tests/chunk-transcript.sh` is the contract.

Call shape: `chunk-transcript.sh SRC OUTDIR CHUNK_BYTES MAX_CHUNKS`. Stdout is `COUNT ELIDED` and `OUTDIR` holds `chunk-01.jsonl` through `COUNT` files. Exit 0 is ok, 1 is an empty source, 2 is bad usage, an unreadable source or a failure writing the chunks.

### Decision

- Every line is kept. Chunks are cut only at line boundaries. A line longer than `CHUNK_BYTES` becomes a chunk of its own instead of being split, so no line is torn. A tool call and its result are separate lines, in order. When a cut falls between them, one ends a chunk and the other opens the next, and the caller says so in the chunk note.
- Over `MAX_CHUNKS` the middle is dropped, deliberately and loudly. `ELIDED` is how many chunks went. The first ceil(MAX/2) and the last floor(MAX/2) are kept, because the start holds the goal and the end holds the outcome. A cap of 1 keeps the first chunk only, so it is still a bounded read and never the whole transcript.
- Sizes are bytes, not characters: `LC_ALL=C` makes awk `length()` count bytes. A source whose last line has no newline gets one, so every chunk ends on a line.
- Numbers are read as decimal (`10#`), because bash arithmetic reads `08` as an invalid octal number.
- Chunks are transcript text, so `umask 077` keeps them private to the user whatever umask the caller has.
- Chunks and scratch files left by an earlier run are removed first, because the caller globs the directory. On a failure (exit 2) no chunk or scratch file is left, so the caller cannot mistake a partial split for a whole one.

### Consequences

The caller must report `ELIDED` to the worker and record it: a nonzero value is a degraded read (`l1_chunks_elided` in run-stats). Cutting inside a line, or keeping a partial directory after a failure, would hand a worker a transcript that looks complete and is not.

## a chunk answer is untrusted, `--check` judges exactly one value, and the merge refuses to merge around a bad one

Status: accepted · Date: 2026-11-21 · Code: `bin/merge-chunks.sh` (`CHUNK_OK`, `chunk_ok`, the pre-merge loop)

### Context

A worker can write the error object the prompt tells it to emit on malformed input, a bare `{}`, a wrongly typed field, or two values in one file, and a transcript can nudge it to. Plain `jq -e .findings` judges only the last value in a file, while the merge slurps them all. So an error object followed by a good object used to pass. docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage", describes the same rule from the runner's side, and `tests/merge-chunks.sh` is the contract.

Call shapes and exits:

- `merge-chunks.sh --check FILE` exits 0 only for a usable chunk answer, else 1.
- `merge-chunks.sh --session PATH [--elided N] CHUNK.json ...` writes the merged object to stdout and exits 0. It exits 2 on bad usage and 3 when any chunk fails `--check`, with stdout left empty. Any other nonzero comes from jq failing.

### Decision

- A usable answer is exactly one JSON value, an object, with no `error` key and a `findings` array. `CHUNK_OK` runs over the whole file with `jq -s`, so a second value cannot hide behind a good first one.
- The test is `has("error")`, not a null test, because the runner treats any `error` key as a failed triage.
- `--check` is the one definition. The runner uses it before it keeps an answer for a retry, and the merge enforces it again itself instead of trusting its caller to have.
- A bad answer is retried. It is never cached and never merged around, because a session built from some of its chunks would read as if it were all of them.

### Consequences

Any new place that keeps or reads a chunk answer must call `--check`. A weaker test (`jq -e .findings`, a null check on `error`) reopens the error-then-good-object hole.

## the chunk merge is mechanical, with a fixed rule for each field when answers disagree

Status: accepted · Date: 2026-11-21 · Code: `bin/merge-chunks.sh` (the jq program)

### Context

The per-chunk answers for one session become the one findings JSON that L2 and every other consumer already reads. No model call does this, so the merge has to say what each field means when the answers disagree. The stats fields in particular are copied by every worker from the same precomputed sidecar. `tests/merge-chunks.sh` is the contract.

### Decision

| Field | Rule |
|---|---|
| `session_path` | The original transcript, never a chunk file. |
| `underlying_goal` | The first non-empty one: the session says what it wants where it begins. |
| `outcome` | The last chunk that states one: the end state is where the outcome is judged. |
| stats fields | Taken once from the first chunk. Every worker copies the same sidecar verbatim, so summing them would be nonsense. |
| `findings` | Union, each tagged with its chunk. Exact duplicates on (`category`, `what`) are dropped, most severe first, capped at 10 (the schema cap). A finding with neither a category nor a `what` has no identity to merge on, so it is kept. |
| other lists | Order-preserving union. `instructions_given` is capped at 3 (the schema cap). |
| `deferred_ideas` | Chunk-order union by normalized (`idea`, `quote`), valid entries only, capped at 3. |
| `meta` | `chunks` (how many answered) and `chunks_elided` (how many the chunker dropped). |

Every read goes through the `arr`, `objs`, `strs` and `num` helpers, so a wrongly typed field is ignored. It does not abort the merge and with it the findings of every other chunk.

### Consequences

A new field in the findings schema needs a row here and a rule in the jq program. If it is left out, it comes from the first chunk only (the program starts from `$all[0]`).

## the pre-pass never invents a key, never stringifies null, and strips an image where its data lives

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (the pre-pass `jq` program: `payload`, `trunc`, `trunc_at`, `strip`)

### Context

The first version of the pre-pass fabricated structure it was supposed to remove. Each item below was a real bug, verified with jq before and after.

### Decision

- `trunc` applies `tostring` only to a value over the cap and never to null. Run unconditionally, it gave a `toolResult` with `.content` null the literal string `"null"`, invented the key on a record that had none, and flattened a structured `.arguments` object to an escaped string while it was 40 times under the cap.
- `trunc_at` and `strip` act only when the key is present or the value is a `payload` (not null, and not an empty object). A bare presence check is true for null, so every guard turned a null into a marker announcing a payload had been stripped, a false claim. A thinking block with no `thinking` key came out with `thinking: ""` for the same reason, which is why there is no `// ""`.
- The two image shapes keep their data in different places. Claude puts the base64 in `.source`, an OpenAI-style `image_url` block in `.image_url.url`, and OMP in `.data`. Each is stripped where its data lives. Setting `.source` for both left the `image_url` payload intact beside a marker saying it was removed.
- OMP `.data` is not always a payload: across 400 real OMP transcripts on this host, all 289 image blocks carry `blob:sha256:<hash>`, a 76-character content-addressed reference totalling 22 KB against a 262144-byte cap. Replacing them with a marker would delete an identifier triage can use and save nothing. Only a `data:` URI is stripped, and anything else goes through `trunc`.
- `tool_result` blocks keep `tool_use_id` and `is_error`, so triage still sees which call failed; only the content goes.

### Consequences

A new guard must pass the test for an absent key, an explicit null and an empty object. `tests/slim-transcript.sh` pins each case.

## `AUTODREAM_SLIM_FULL=1` keeps every line, applies no byte cap and appends no footer

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (the output block and the footer `printf`)

### Context

The chunker sizes pieces itself at line boundaries. The footer is plain text, so in full mode it would land in the last chunk as a line that is not JSON, which the worker would read as transcript. The chunk note and the triage prompt already say that long lines are cut.

### Decision

Full mode skips head/tail elision, the byte cap and the footer. Lines are still cut to `AUTODREAM_SLIM_MAXLINE`, so each chunk parses as JSONL only for the chunker's own contract, not for a slimmed input. With the mode off, a plain call writes exactly what it always did.

### Consequences

Turning chunking off restores the head/tail view byte for byte. docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage", is the rest of the design.

## an oversized transcript is read through a lossy, representative slim

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (default mode: line cut, head and tail, byte cap)

### Context

Some sessions are enormous: 4500+ lines, about 10 MB, with base64 images and giant tool outputs. The L1 haiku worker cannot read 20 such lines without blowing the 25k-token Read limit, so it gave up and returned an error finding instead of triaging. Those large sessions are often the most interesting ones.

### Decision

`run.sh` calls the slimmer for sessions over `AUTODREAM_SLIM_BYTES`, and as the fallback when the chunker fails; other sessions are read verbatim. The default mode caps the damage in three steps:

1. Cut every line to a maximum width, which removes base64 blobs and huge tool outputs.
2. Keep the head and the tail and elide the middle, which is usually repetitive churn.
3. Hard-cap the total bytes as a last safety net. The cap applies before the footer is appended, so the output can run a little over it.

A lossy view is acceptable because triage is fuzzy pattern-spotting, not strict JSON parsing: a representative transcript still yields useful findings.

### Consequences

Lossy has a measured limit. On a real 3,479-line session the head and tail were mostly bookkeeping records and the line cut deleted the timestamp, so the worker saw 17% of the lines and about 2% of the text. The reshape and full modes, and the chunked reader that uses them, exist for that reason; see the docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage section "Reading a long session: chunked triage" and `docs/adr/0007-l1-chunked-triage.md#reshape-drops-claude-code-bookkeeping-by-a-denylist-of-record-types-and-attachment-subtypes-never-an-allowlist`. With chunking off, the head/tail view above is what a worker sees, byte for byte.

## the slim output is mode 0600 even into a destination the caller already made

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (`umask 077`, the `chmod 600` on `$dst`)

### Context

Everything this script writes is derived from a session transcript, so none of it may be readable by another local account, whatever umask the caller has. `umask` only governs files this script creates: a destination the caller already made keeps its own mode through the redirects.

### Decision

`umask 077` covers the files created here, and the destination is truncated and `chmod 600` explicitly. The `.pre.jsonl` intermediate is created under the same umask.

### Consequences

`tests/slim-transcript.sh` checks that a destination made with mode 644 is tightened to 600 and its old contents are replaced.

## reshape drops Claude Code bookkeeping by a denylist of record types and attachment subtypes, never an allowlist

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (`reshape_defs`: `noise`, `noise_attachment`, `reshape`)

### Context

Measured 2026-10-02 on a 3,479-line session: 36% of the lines were conversation, 24% hook and reminder attachments and 21% `mode`, `permission-mode`, `last-prompt` and `bridge-session` records. The head/tail pass is positional, so on the raw stream it spent its whole budget on those and the worker saw about 2% of the conversation. On 24 hours of this host's Claude transcripts, `hook_success` and `total_tokens_reminder` alone were 12,000 and 8,000 of about 33,000 attachments.

Claude Code writes `message` before `timestamp`, so the 400-character line cut dropped the timestamp from a third of the lines. The envelope (`parentUuid`, `uuid`, `cwd`, `sessionId`, `version`, `gitBranch`, `userType`, `toolUseResult`, message id, model, usage) used about 185 characters before the content began.

### Decision

- With `AUTODREAM_SLIM_RESHAPE=1`, a denylist drops bookkeeping record types and hook and reminder attachment subtypes, plus `system/stop_hook_summary` and `system/turn_duration`.
- It is a denylist, never an allowlist of user and assistant. OMP transcripts come through this script too, and an allowlist would delete every one of their records, leaving an empty transcript and a findings list that reads like a quiet night. It is a denylist of attachment subtypes as well: keeping an unknown subtype costs bytes, dropping one silently costs signal.
- Kept on purpose: `attachment/queued_command` (the user typing mid-turn, the only place that text lives), `attachment/skill_listing` (SESSION_TRIAGE.md names it for the StructuredOutput rule and `missed_skill`), every `system` record but the two above (`compact_boundary` is the compaction marker), `pr-link` and summary records.
- Each kept Claude record is rebuilt with `type` then `timestamp` first and only the fields triage reads. A key is added only when the source has it, because inventing a null is the bug the guards in the main program exist to stop. The thinking `signature` is a base64 blob that filled whole lines.
- OMP and unknown-schema records come out of the reshape unchanged.

### Consequences

Before dropping a record type, grep the prompts for it: the first draft's denylist caught `queued_command`. docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage", has the replay figures.

## the jq pre-pass strips tool payloads for both the Claude Code and the OMP schema

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (the pre-pass `jq` program)

### Context

Two transcript schemas store tool output in different places: Claude Code in `tool_result` blocks inside `.message.content`, OMP in whole records with `.message.role == "toolResult"` carrying the payload in `.message.details` and `.message.content`, plus a `.message.providerPayload` blob on assistant turns.

Handling only the first is worse than doing nothing. jq still exits 0 and writes a valid file, so the fallback never fires, and the line pass then spends its 400-character budget on about 190 characters of OMP envelope (`id`, `parentId`, `timestamp`, `toolCallId`, `toolName`) and cuts off at `"content":[`. The worker gets ID soup with no payload and no goal, and returns no findings.

### Decision

Both schemas are stripped in the pre-pass. The line-based head/tail/cut pass still runs after it as a safety net, and the script falls back to it when jq is missing or the stream is not parseable JSONL.

### Consequences

A new transcript schema needs its payload location added to the pre-pass, not only a test that jq exits 0. `tests/slim-transcript.sh` covers both schemas.

## chunked triage is one switch, on only when asked for and when both helpers are found

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`CHUNKER`, `MERGER`, `L1_CHUNKING`)

### Context
A transcript too big for one worker is split at line boundaries (`chunk-transcript.sh`), one worker reads each chunk, and `merge-chunks.sh` merges the answers back into the one findings JSON per session that L2 reads. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage".

### Decision
`L1_CHUNKING=1` only when `AUTODREAM_L1_CHUNK_BYTES` is above 0 AND both helpers are found with `find_lib` (a merge swaps run.sh before install.sh links the new helpers). With either missing, the oversized transcript is read the old way (head/tail slim) and the run says so. Everything new sits behind this one switch: `L1_CHUNKING=0` reaches the slimmer with no reshape and no full mode, no chunker, no merge and no chunk note, so the off path is what it was.

### Consequences
New chunking behaviour must be gated on `L1_CHUNKING`, not on the byte knob alone, or the off path stops being byte-identical to the old behaviour.
