# 0003: Adapters and engines: who runs L1 and L2

Status: accepted · Governs: `adapters/claude/adapter.sh`, `adapters/_fixture/adapter.sh`, `bin/run.sh`, `bin/adapters.sh`, `bin/l2-prompt.sh`, `l2-prompt.sh`, `prompts/L2_SYSTEM.txt`

This record holds 42 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: How claude is invoked — the lean-query pattern (do not use `--bare`)](#background-how-claude-is-invoked--the-lean-query-pattern-do-not-use---bare)
- [Background: Who starts the L1 worker (decision 2 of the consolidation)](#background-who-starts-the-l1-worker-decision-2-of-the-consolidation)
- [Background: Several harnesses in one run: enabled is a host decision, and every session goes through its own adapter](#background-several-harnesses-in-one-run-enabled-is-a-host-decision-and-every-session-goes-through-its-own-adapter)
- [Background: What L2 is told about each harness (`skills-inventory.txt`, `adapter-facts.md`)](#background-what-l2-is-told-about-each-harness-skills-inventorytxt-adapter-factsmd)
- [Background: One triage document, one addendum per harness that differs](#background-one-triage-document-one-addendum-per-harness-that-differs)
- [Background: Which engine runs L2](#background-which-engine-runs-l2)
- [adapter subcommands write through a unique temp in the destination directory, refuse a directory destination, and verify a regular file afterwards](#adapter-subcommands-write-through-a-unique-temp-in-the-destination-directory-refuse-a-directory-destination-and-verify-a-regular-file-afterwards)
- [the claude adapter delegates to the existing bin/ scripts and never reimplements their predicates](#the-claude-adapter-delegates-to-the-existing-bin-scripts-and-never-reimplements-their-predicates)
- [enumerate is an mtime window only and keeps find's stderr](#enumerate-is-an-mtime-window-only-and-keeps-finds-stderr)
- [the L1 worker runs with a replaced system prompt, JSON output and an explicit effort, and the warmup shares its permission, model, effort and isolation flags](#the-l1-worker-runs-with-a-replaced-system-prompt-json-output-and-an-explicit-effort-and-the-warmup-shares-its-permission-model-effort-and-isolation-flags)
- [l2-argv exposes only Glob and Read, and produces no argv when the system prompt file is missing](#l2-argv-exposes-only-glob-and-read-and-produces-no-argv-when-the-system-prompt-file-is-missing)
- [the stats and slim wrappers install no signal trap, and a killed run's temp file is swept by the runner](#the-stats-and-slim-wrappers-install-no-signal-trap-and-a-killed-runs-temp-file-is-swept-by-the-runner)
- [the claude adapter reads a session's cwd with jq, never grep](#the-claude-adapter-reads-a-sessions-cwd-with-jq-never-grep)
- [the claude adapter judges whether the requested model answered](#the-claude-adapter-judges-whether-the-requested-model-answered)
- [a usage error exits 2 and an unreadable input exits 3, so neither reads as a skip or as "not ours"](#a-usage-error-exits-2-and-an-unreadable-input-exits-3-so-neither-reads-as-a-skip-or-as-not-ours)
- [`whoami` reads the login with `claude auth status --json` and makes no model call](#whoami-reads-the-login-with-claude-auth-status---json-and-makes-no-model-call)
- [the fixture adapter uses a session format that resembles neither real harness](#the-fixture-adapter-uses-a-session-format-that-resembles-neither-real-harness)
- [L1 resolves the engine first and keys the model by the engine, not by the session's source](#l1-resolves-the-engine-first-and-keys-the-model-by-the-engine-not-by-the-sessions-source)
- [an adapter's manifest is data read with jq, its identity is its directory basename, and containment is resolved, not assumed](#an-adapters-manifest-is-data-read-with-jq-its-identity-is-its-directory-basename-and-containment-is-resolved-not-assumed)
- [the adapter name check lists its characters instead of using ranges](#the-adapter-name-check-lists-its-characters-instead-of-using-ranges)
- [the network probe URL is derived from the model each layer calls, and an unknown provider means "cannot answer"](#the-network-probe-url-is-derived-from-the-model-each-layer-calls-and-an-unknown-provider-means-cannot-answer)
- [refusals are recorded in a file, and an unreadable record reports `unknown`, never `none`](#refusals-are-recorded-in-a-file-and-an-unreadable-record-reports-unknown-never-none)
- [the L2 system prompt has one copy, found through the install symlink, and a missing or blank copy is an error](#the-l2-system-prompt-has-one-copy-found-through-the-install-symlink-and-a-missing-or-blank-copy-is-an-error)
- [the built-in `claude` adapter fallback fires only when the adapter machinery is absent, never when the loader accepted nothing](#the-built-in-claude-adapter-fallback-fires-only-when-the-adapter-machinery-is-absent-never-when-the-loader-accepted-nothing)
- [the claude adapter scans root-probe's roots; every other adapter uses its own configured or manifest roots; roots are newline-terminated](#the-claude-adapter-scans-root-probes-roots-every-other-adapter-uses-its-own-configured-or-manifest-roots-roots-are-newline-terminated)
- [a directory under adapters/ makes an adapter accepted, not enabled; the host enables it with AUTODREAM_ADAPTERS](#a-directory-under-adapters-makes-an-adapter-accepted-not-enabled-the-host-enables-it-with-autodream_adapters)
- [Adapter refusals are logged under this run's findings dir, not in the installed source tree](#adapter-refusals-are-logged-under-this-runs-findings-dir-not-in-the-installed-source-tree)
- [an engine's login is read once with a model-free whoami, checked against AUTODREAM_REQUIRE_LOGIN, and an ended claude.ai sign-in is a refusal](#an-engines-login-is-read-once-with-a-model-free-whoami-checked-against-autodream_require_login-and-an-ended-claudeai-sign-in-is-a-refusal)
- [The L1 engine is resolved before its model, and an engine that fails its login check is removed before any transcript is sent](#the-l1-engine-is-resolved-before-its-model-and-an-engine-that-fails-its-login-check-is-removed-before-any-transcript-is-sent)
- [The lean-query environment is exported once, and `--bare` is not used](#the-lean-query-environment-is-exported-once-and---bare-is-not-used)
- [which model answered an L1 call is read from the engine result and judged by the adapter, and the verdict is stored with the answer it describes](#which-model-answered-an-l1-call-is-read-from-the-engine-result-and-judged-by-the-adapter-and-the-verdict-is-stored-with-the-answer-it-describes)
- [the L1 engine, model and source of each session come from parent-built environment, never from files under the findings dir](#the-l1-engine-model-and-source-of-each-session-come-from-parent-built-environment-never-from-files-under-the-findings-dir)
- [one triage document serves every harness, and a harness that differs adds an addendum appended for its own sessions only](#one-triage-document-serves-every-harness-and-a-harness-that-differs-adds-an-addendum-appended-for-its-own-sessions-only)
- [L2's skills inventory and per-harness facts come from the adapters, and facts are taken only for sources that had sessions, from the pre-model source map](#l2s-skills-inventory-and-per-harness-facts-come-from-the-adapters-and-facts-are-taken-only-for-sources-that-had-sessions-from-the-pre-model-source-map)
- [a built-in claude L2 invocation remains for installs whose adapters tree predates `l2-argv`](#a-built-in-claude-l2-invocation-remains-for-installs-whose-adapters-tree-predates-l2-argv)
- [an empty L2 argv is replaced with `false`, never run](#an-empty-l2-argv-is-replaced-with-false-never-run)
- [Every L2 engine requirement is checked before L1 is paid for](#every-l2-engine-requirement-is-checked-before-l1-is-paid-for)
- [the L2 engine is an adapter and `run.sh` names no binary for it](#the-l2-engine-is-an-adapter-and-runsh-names-no-binary-for-it)
- [the L2 engine is started through a one-line sh that records its pid and then execs](#the-l2-engine-is-started-through-a-one-line-sh-that-records-its-pid-and-then-execs)
- [no L2 model is pinned by default; a pin must be an exact string](#no-l2-model-is-pinned-by-default-a-pin-must-be-an-exact-string)
- [L2 holds Glob and Read only, so the runner is the only writer of the report and pins](#l2-holds-glob-and-read-only-so-the-runner-is-the-only-writer-of-the-report-and-pins)
- [one `review_engine` function names both the L2 summary engine and the default L1 engine](#one-review_engine-function-names-both-the-l2-summary-engine-and-the-default-l1-engine)

## Background: How claude is invoked — the lean-query pattern (do not use `--bare`)

This section was moved here from the former CLAUDE.md. Its original title: "How claude is invoked — the lean-query pattern (do not use `--bare`)".

Both layers call `claude --print` with a composed set of minimal-footprint flags borrowed from claude-cells `internal/claude/query.go`. The point: strip per-call bloat (hooks, skills, MCP, CLAUDE.md auto-load) while KEEPING subscription/OAuth auth.

```
--no-session-persistence            # see self-pollution below
--tools Read Write                  # L1; L2 uses: Glob Read Write Edit
--disable-slash-commands            # no skills
--strict-mcp-config                 # no MCP servers
--settings '{"disableAllHooks":true}'   # no hooks (incl. the big SessionStart injection)
```
plus env `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1`, and `--permission-mode bypassPermissions` so workers can write.

**Do NOT switch to `--bare` or `CLAUDE_CODE_SIMPLE=1`.** Verified (2026-05) with a control on this host: plain `claude --print` authenticates, but both `--bare` and `CLAUDE_CODE_SIMPLE=1` return "Not logged in". They disable OAuth/keychain auth and require `ANTHROPIC_API_KEY` (or an apiKeyHelper), and `--bare`'s toolset is only Bash+Edit (no Read/Write/Glob). The composed flags above give the same minimal footprint without breaking auth or the file tools. (claude-cells uses simple mode only inside containers, where creds are a mounted `.credentials.json` file, not the macOS keychain.)

## Background: Who starts the L1 worker (decision 2 of the consolidation)

This section was moved here from the former CLAUDE.md. Its original title: "Who starts the L1 worker (decision 2 of the consolidation)".

`dispatch_l1` no longer names an engine. For each session it takes the adapter from the source map, the adapter's argv from `adapter.sh l1-argv <model>`, and its environment from `l1-env`, and runs `env <env> <argv>` with the prompt on stdin. The claude adapter's argv is the invocation listed above, byte for byte (`tests/adapter-claude.sh` pins it against the old literal text).

- **The source map is held in the environment, not read from the findings dir.** `AUTODREAM_SOURCE_MAP` (hash and adapter per session) and `AUTODREAM_L1_MODELS` (model per adapter) are built before the first model call. An L1 worker holds the Write tool and could rewrite `sessions-source.txt`, and the source decides which binary the next worker executes. `test_l1_engine_cannot_be_redirected_by_a_worker` has a worker do exactly that and checks the next session still runs on the real engine; reading the file instead fails it.
- **Haiku 5.5, effort and a replaced system prompt (2026-10-07).** The claude manifest's `l1_model` is `claude-haiku-5-5` (verified: `--model claude-haiku-5-5` and the `haiku` alias both answer as it; an id the CLI does not know falls back silently, so re-check `modelUsage` in `--output-format json` when changing it). `l1-argv` and `warmup-argv` add `--effort` from `AUTODREAM_L1_EFFORT_CLAUDE`, then `AUTODREAM_L1_EFFORT`, then `high`; `off` omits it and an unknown level exits 2. They also pass `--system-prompt` instead of `--append-system-prompt`, which drops Claude Code's default prompt: one-word call 6.9k -> 5.0k input tokens, and a real triage run on a 250 KB slice cost $0.159 against $0.215 with the same number of findings. L2 is untouched.
- **The engine, then the model.** A source's L1 engine is `AUTODREAM_L1_ENGINE_<SOURCE>`, then `AUTODREAM_L1_ENGINE`, then the run's reviewer (the L2 engine) (`adapter_l1_engine`). The model is keyed by that engine, not by the source: `AUTODREAM_L1_MODEL_<ENGINE>`, then `AUTODREAM_L1_MODEL`, then the engine's manifest `l1_model` (`adapter_l1_model`). A model id belongs to one engine, so a source-keyed pin sent omp sessions to the claude CLI with `--model deepseek/...` once a claude reviewer read them (PR #165 review). The engine choice is per source and the model pin per engine, the same as `AUTODREAM_L2_MODEL_<NAME>`.
- **What answered, and whether it counts.** Every L1 call's stdout goes through the engine adapter's `served` verb with the requested model: it returns the models that answered, the cost estimate and a verdict, `match` or `mismatch`, judged by the adapter because only it knows its CLI's naming (claude: `haiku` answers as `claude-haiku-5-5`). An engine with no `served` verb (omp) is `unmeasured`. The verdict is the sixth column of `l1-served.tsv` (run-stats `l1_served_mismatch`, `l1_served_unmeasured`) and is stored beside every accepted answer, findings JSON or chunk answer, as `<answer>.served`. With `AUTODREAM_L1_REQUIRE_SERVED=1` a call whose verdict is not `match` loses its answer, and before L1 `drop_unacceptable_l1_cache` holds the cache to the same rule: a findings JSON or chunk answer from an earlier run with no verdict or a non-`match` one is dropped and triaged again (`l1_cache_dropped`). A record the runner wrote with no model behind it (noise-gate skip, unreadable session, normalize failure, no-engine record, final-round stub) is kept, and the only thing that says so is its `.served` reading `runner`, which the dispatcher writes beside each one. Keys and shape prove nothing: a worker can write `error`, `skipped` or `no_engine` with `findings: []` as easily as the runner can, and that record would have skipped the verdict and left the session untriaged (#167). The empty findings array is kept as a second guard. A runner record from before the marker is triaged once more and comes back marked.
- **No engine is an error for this run's config, not forever.** A session whose engine is not executable, resolves no model, names no accepted adapter or fails `AUTODREAM_REQUIRE_LOGIN` gets a findings record with `no_engine: true` and `error: no L1 engine for this session`, counted by `l1_findings_with_error` and skipped by the retry rounds, since retrying in the same run cannot change the answer, and the run still reports. Every one of those causes is config, which can change between runs, so `drop_unacceptable_l1_cache` drops the record in a later run (a catch-up or `AUTODREAM_FORCE=1`) once that run resolves an engine and a model for the session's source, read from `AUTODREAM_SOURCE_MAP` and never from the record. Records written before the marker are recognised by their error text. Either way the record must have `findings: []`. Its shape is enough to drop it, since a forged one only buys a retriage; keeping it under `AUTODREAM_L1_REQUIRE_SERVED=1` takes the runner marker above.

## Background: Several harnesses in one run: enabled is a host decision, and every session goes through its own adapter

This section was moved here from the former CLAUDE.md. Its original title: "Several harnesses in one run: enabled is a host decision, and every session goes through its own adapter".

`AUTODREAM_ADAPTERS` (names, space or comma separated, or `all`; default `claude`) names the harnesses a run scans. An adapter that sits under `adapters/` is accepted, not enabled, so merging a harness never changes what a live nightly reads. For an enabled adapter the session's own adapter does the work:

- `stats` comes from the adapter (omp records are not claude records). `AUTODREAM_STATS_BIN` still overrides, and a session with no recorded source keeps the claude script.
- A manifest with `"normalize": true` (omp: an append-only tree) is linearized first and the worker reads `<hash>.norm.jsonl`, the live branch only. A tree the linearizer refuses (duplicate id, dangling parent, cycle) becomes a structured error record ("could not be normalized by the <adapter> adapter") and no worker is started. `findings.session_path` is rewritten back to the real session, and the copy is removed.
- The substantive-session filter accepts both shapes: a claude user record, or an omp `message` record with role user and a text item.
- The L1 engine, model and warmup come from the adapter (see "Who starts the L1 worker").

## Background: What L2 is told about each harness (`skills-inventory.txt`, `adapter-facts.md`)

This section was moved here from the former CLAUDE.md. Its original title: "What L2 is told about each harness (`skills-inventory.txt`, `adapter-facts.md`)".

Both files are written by `write_adapter_inputs` just before L2, from the adapters. `skills-inventory.txt` unions every enabled adapter's `skills-inventory` output (name, optionally a TAB and a description), deduplicated by name; if every adapter fails it says `# skills-inventory.txt unavailable` and PROMPT.md tells L2 not to file coverage gaps from it, because an empty list would claim no skills are installed. `adapter-facts.md` holds one `## Source: <name>` section per harness that had sessions tonight, taken from the source map captured before any model ran: a remedy for a finding has to be a surface that exists for the harness the evidence came from. A new harness adds an `adapters/<name>/facts.md` and a `skills-inventory` subcommand, not code in `run.sh`.

## Background: One triage document, one addendum per harness that differs

This section was moved here from the former CLAUDE.md. Its original title: "One triage document, one addendum per harness that differs".

`prompts/SESSION_TRIAGE.md` is the single L1 prompt. A harness whose transcripts differ from the claude shape it describes adds `adapters/<name>/triage.md`; the worker appends it for that adapter's sessions only (it says it wins where it disagrees), so a claude worker receives exactly SESSION_TRIAGE.md plus the stats block. `adapters/omp/triage.md` carries omp's record shapes, the harness-tool rule, the retired `compliance_markers`, `is_advisor` and `skills_authored`, and the restricted schema for advisor sidecars (no `sandbox_friction`, `tool_loop` or `missed_skill`). PROMPT.md excludes advisor turns from the session-turn total and files any advisor tool-behavior finding under Triage failures.

## Background: Which engine runs L2

This section was moved here from the former CLAUDE.md. Its original title: "Which engine runs L2".

L2 is an adapter too. `AUTODREAM_L2_ENGINE=<adapter name>` picks it (default: the first enabled adapter, so `claude` on an untouched install); a name that is not an accepted adapter stops the run before L1, not after. The adapter prints the command (`adapter.sh l2-argv [model]`, NUL-delimited, prompt on stdin, tools Glob and Read only) and `l1-env` supplies its environment. The model resolves `AUTODREAM_L2_MODEL_<NAME>`, then `AUTODREAM_L2_MODEL`, then the manifest's `l2_model`; none at all is valid and means the engine's own default (claude). `run-stats.txt` records `l2_engine`, `l2_model` (`default` when none was named) and one `l1_model_<adapter>` per source that had sessions, so a report that reads differently can be traced to the engine that wrote it. An install whose `adapters/` tree predates `l2-argv` keeps the built-in claude invocation, for claude only. Every engine gets the same system prompt, `prompts/L2_SYSTEM.txt`, through `bin/l2-prompt.sh`; it names the stdout grammar `bin/report-format.sh` parses, so change them together. A missing prompt file makes `l2-argv` exit 2 rather than start an engine without it.

## adapter subcommands write through a unique temp in the destination directory, refuse a directory destination, and verify a regular file afterwards

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`normalize`, `stats|slim`), `adapters/_fixture/adapter.sh` (`normalize`, `stats`, `slim`)

### Context

The adapter contract (`docs/design/unify-harness-adapters-2026-08-23.md`, "Every subcommand has a named skip path and atomic output") says a failed subcommand leaves no output. A half-written file that a later step reads as a whole session is worse than no session. For `stats` and `slim` the delegates write the destination directly (`slim-transcript.sh` in two steps, a `>` for the body and a `>>` for the footer), so an interruption leaves a non-empty file with no footer, which the caller's `-s` check accepts as a whole session. The atomicity lives in the adapter and not in those scripts because both have callers outside this seam.

### Decision

- Write to `mktemp "$2.tmp.XXXXXX"` in the destination directory, `mv -f` it onto `$2` on success, and remove it on failure. A fixed `"$2.tmp"` is a shared name: two invocations writing the same output would clobber or remove each other's temp file and leave the result from the wrong one, or none.
- Refuse a directory at the destination before any work. `mv -f "$t" "$2"` would move the temp inside it and return success, so the adapter would report a write it never performed and leave a randomly named file in the caller's directory. The delegates used to reject this themselves, because a `>` redirection to a directory fails; wrapping them removed that.
- After the `mv`, verify `$2` is a regular file and remove the stray otherwise, because the guard is a check-then-act: something can create a directory at `$2` between the two, and `mv` then moves the temp inside it and returns 0. macOS has no `mv -T`. Verified by deleting the guard: the post-condition alone still satisfies the directory-destination contract test, so it is a real backstop. The guard stays because it fails before any work and stops a file appearing inside the caller's directory even briefly.
- The fixture adapter carries the same shape so the contract test exercises it against a second implementation.

### Consequences

This narrows the race and does not close it. A sequence that creates a directory at `$2` after the guard, lets `mv` move the temp inside, then replaces `$2` with a regular file before the check, still reports success with the output elsewhere. Closing that needs an atomic rename-if-not-a-directory, which is `renameat2` on Linux and does not exist on macOS, where this runs. Winning any of these needs write access to the findings dir, at which point the dir is already the attacker's; the checks exist because silent wrong success is the failure this repo keeps getting caught by, not because there is a threat model. A fourth layer would not close it either. Keep both checks: the guard fails early, the post-condition backstops the race.

## the claude adapter delegates to the existing bin/ scripts and never reimplements their predicates

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`BIN`, `is-self`, `stats|slim`)

### Context

The adapter exists so that `run.sh` stops knowing which harness it is talking to. Nothing about Claude ingest was meant to change when it was introduced. `bin/prune-self-sessions.sh` is the single source of truth for "is this one of autodream's own transcripts", and `session-stats.sh` and `slim-transcript.sh` have callers outside this seam.

### Decision

- Every subcommand that has an existing implementation calls that script (`is-self` execs `prune-self-sessions.sh --is-self`; `stats` and `slim` call `session-stats.sh` and `slim-transcript.sh`). A marker added to the self-session predicate must not have to be remembered in the adapter too.
- `BIN` is resolved with `cd -P`. Logical resolution could succeed against a coincidental `$TARGET/bin` in the installed layout and land in the wrong directory; `-P` follows the `adapters` symlink physically first, so it resolves to the real `bin/`.

### Consequences

A behavior change belongs in the delegate. The atomic-write wrapper around `stats` and `slim` is the one thing the adapter adds, because the contract is the adapter's (see `docs/adr/0003-adapters-and-engines.md#adapter-subcommands-write-through-a-unique-temp-in-the-destination-directory-refuse-a-directory-destination-and-verify-a-regular-file-afterwards`).

## enumerate is an mtime window only and keeps find's stderr

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`enumerate`)

### Context

The runner places a session in a report day by the timestamps inside the transcript (`bin/session-window.sh`), not by file mtime, and passes `enumerate` a far-future `$3` for that reason. `find` exits 1 for any unreadable directory in the walk, and the runner has to decide between a partial corpus and a failed root on that status alone. Swallowing the reason left it reporting a bare `(exit 1)` with nothing to act on.

### Decision

`$2` and `$3` are an mtime window and nothing more; with a far `$3` it is a lower bound only, which keeps the adapter contract free of any knowledge of the report-day window (docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to"). stderr is not discarded. Only stdout is the contract.

### Consequences

Do not add `2>/dev/null` to the `find` here. The fixture adapter does discard it, because its fixtures are not time-filtered and have no partial-corpus case.

## the L1 worker runs with a replaced system prompt, JSON output and an explicit effort, and the warmup shares its permission, model, effort and isolation flags

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`l1-argv`, `warmup-argv`, `l1_effort`)

### Context

docs/adr/0003-adapters-and-engines.md#background-how-claude-is-invoked--the-lean-query-pattern-do-not-use---bare, "How claude is invoked" and "Who starts the L1 worker", has the lean-query rationale. The points a future editor would get wrong:

- `--system-prompt` replaces Claude Code's default prompt, about 1.9k tokens a call. Measured 2026-10-07: 6.9k to 5.0k input tokens on a one-word call, and 26% cheaper on a real triage run with the same findings count. The worker prompt is self-contained, so nothing is lost. Tools are already Read and Write only, with hooks, skills, MCP and CLAUDE.md off.
- `--output-format json` makes stdout one small result object that names the models that answered, read back by `served`. Not `stream-json`: `--verbose` would echo every Read result, the whole transcript, onto stdout, and a failed worker copies its stdout into the `.err`.
- The text of the system prompt must not be shell-expanded: it names the output path literally, hence the escaped dollar sign in the text.
- Haiku 5.5 trades cost for quality on the effort dial, and triage yield was the weak point of the old Haiku, so the default leans to quality (`high`); the pricing makes that cheap.

### Decision

- `l1-argv` is the invocation `run.sh` hard-coded before the engine moved behind the adapter. `tests/adapter-claude.sh` pins it against that literal text, so a change here that alters what the nightly runs has to say so.
- Effort resolves `AUTODREAM_L1_EFFORT_CLAUDE`, then `AUTODREAM_L1_EFFORT`, then `high`. `off` omits the flag, leaving the model's own default. An unknown level is an error (exit 2 from both argv subcommands), never a silent fallback.
- `warmup-argv` keeps the worker's permission mode, model, effort and isolation flags (no session persistence, no slash commands, MCP strict, hooks off). It differs in three places: no `--output-format json` (its stdout must be the word `ok`), `--tools Read` only, and a system prompt that asks for one word instead of a findings file. A warmup on a different login path would refresh a token the workers never use.

### Consequences

Changing the permission, model, effort or isolation flags in one argv without the other makes the warmup stop proving what the workers need.

## l2-argv exposes only Glob and Read, and produces no argv when the system prompt file is missing

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`l2-argv`)

### Context

L2 returns the report and the pins on stdout and the runner is the only writer, so an injected L2 cannot rewrite `sessions-source.txt` or forge a pin (docs/adr/0009-l2-aggregation.md#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15, "L2 is read-only"). The system prompt, `prompts/L2_SYSTEM.txt`, is what tells the engine where the report goes.

### Decision

Tools are `Glob Read`. The model is optional, and absent means the CLI's own default, so an upgrade of the account upgrades the nightly report with nothing edited here. The system prompt is read through the loader (`bin/l2-prompt.sh`). No file means exit 2 and no argv: an engine started without it would run L2 with no word on where the report goes.

### Consequences

Giving L2 a write tool breaks the read-only guarantee the runner's pin and report handling depends on.

## the stats and slim wrappers install no signal trap, and a killed run's temp file is swept by the runner

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`stats|slim`), `bin/run.sh` (`sweep_killed_leftovers`)

### Context

A run killed mid-flight leaves its `$2.tmp.XXXXXX` behind. That is real but cosmetic: nothing reads `*.tmp.*` (the findings glob is `*.json` and slim output is read by exact path). Adding `trap 'rm -f "$t"' ... TERM` was measured, not assumed: bash defers a trapped signal until the foreground child returns, and the delegate is that child, so the trap turns a prompt death into an adapter that ignores SIGTERM for as long as the delegate runs. The test hung for 120 seconds and left orphaned `slim-transcript.sh` processes holding their input open.

### Decision

No trap. Being killed mid-flight is this pipeline's normal failure, so a stale temp is accepted over a hung process. The runner sweeps `*.tmp.??????` and `*.pre.jsonl` out of the findings dir at the start of each run (`sweep_killed_leftovers`, #57). Backgrounding the delegate and killing it from a trap would work, at the cost of five lines of signal plumbing in a file whose claim is that nothing is invented here.

### Consequences

A trap is safe in the test suite and not in the adapter: the deferral is bounded there (every foreground child is a `sleep 0.05` or faster) and unbounded here. `docs/adr/0029-tests-adapters-claude-suite-process-control.md` records the suite side. Do not add a trap to the adapter without reading it.

## the claude adapter reads a session's cwd with jq, never grep

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`project`)

### Context

A cwd containing a quote or a backslash is JSON-escaped in the transcript. A regex over the raw line either truncates at the escaped quote or hands `realpath` a doubled backslash.

### Decision

`project` extracts `.cwd` with `jq -re` and resolves it with `realpath`. A session with no cwd or an unresolvable one exits 1, which the runner counts as an unusable cwd for pin authorization.

### Consequences

`bin/apply-pins.sh` authorizes a pin only for a project whose cwd resolves here, so a parsing shortcut in this subcommand would silently change which projects can receive pins.

## the claude adapter judges whether the requested model answered

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`served`)

### Context

Only this adapter knows the CLI's naming: `modelUsage` in the result object carries canonical ids (`claude-haiku-5-5`) while a host may ask for a model by alias (`haiku`). The runner's `AUTODREAM_L1_REQUIRE_SERVED` needs a verdict it can trust (docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "What answered, and whether it counts").

### Decision

`served` prints `<models, comma-joined><TAB><estimated cost USD><TAB>match|mismatch` from the result object, or exits 1 without a result. The models come from `modelUsage`, which lists every model that answered any part of the call. The cost is the CLI's estimate at API prices, not what a subscription bills; it is kept because it compares models on real numbers. The verdict is `match` when every model that answered is the one asked for. A bare family name matches any id of that family (`claude-<name>-...`), a full id only itself, and a context suffix such as `[1m]` is ignored on both sides. An alias the family rule cannot read (`default`, `opusplan`) is a `mismatch`: the runner then cannot vouch for the model, which is what `AUTODREAM_L1_REQUIRE_SERVED` asks.

### Consequences

An engine whose adapter has no `served` verb (omp) is `unmeasured`. A new model-family naming scheme that does not start with `claude-` would read as a mismatch.

## a usage error exits 2 and an unreadable input exits 3, so neither reads as a skip or as "not ours"

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`stats|slim`, `is-self`), `adapters/_fixture/adapter.sh` (`is-self`)

### Context

Exit 1 from `project`, `stats`, `slim` and `normalize` means "skip this session". Exit 2 is the unknown-subcommand code. Under `set -u` a one-argument `stats` or `slim` call died with `$2: unbound variable` and status 1, indistinguishable from a legitimate skip when the caller had made a usage error. `is-self` delegates to `prune-self-sessions.sh`, which greps with `2>/dev/null` and returns 1 for both "not ours" and "file not there", so a vanished or unreadable transcript looked like a real user session, and the contract has no channel to say "I could not read it".

### Decision

- `stats`, `slim` and `normalize` check arity (`$# -ge 2`, exit 2) before dereferencing `$2`.
- `is-self` checks readability first and exits 3, a nonzero that is not 1 and is not the unknown-subcommand code. The fixture adapter answers the same way: it always says "not ours", but only for a readable session, because the fixture exists to make a contract gap fail there rather than in production.

### Consequences

Callers that treat any nonzero as a skip still work; a caller that wants to tell usage or unreadable input apart can. `tests/adapter-contract.sh` runs the same checks against every adapter.

## `whoami` reads the login with `claude auth status --json` and makes no model call

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`whoami`)

### Context

The run reports which account and plan its calls bill to. Asking a model would cost a call, and it would fail exactly when the login is broken. `claude auth status --json` reports the API provider (`firstParty` is Anthropic's own API), the sign-in method, the subscription plan, the account email and, for a stored claude.ai sign-in, when that sign-in ends. The expiry field, `loginExpiresAt`, exists only in Claude Code 2.1.318 and later.

### Decision

`whoami` runs `claude auth status --json` with stdin closed and stderr dropped, and prints one JSON object: `{provider, auth, plan, account, expires}`. A field the login does not report reads `unknown`. A failed call or unparseable output makes all five fields `unknown`.

### Consequences

`expires` reads `unknown` on Claude Code older than 2.1.318 and with an API-key login. That is the expected output there, so `unknown` alone does not mean the adapter is broken. Check the readers of this object before renaming a field.

## the fixture adapter uses a session format that resembles neither real harness

Status: accepted · Date: 2026-11-21 · Code: `adapters/_fixture/adapter.sh`

### Context

The fixture exists to prove the adapter contract is a contract and not a description of what the claude adapter happens to do. A fixture shaped like a Claude transcript would pass by accident and keep passing if the contract quietly grew a Claude-specific assumption.

### Decision

A session is one JSON object per file (`*.fixture`) with `cwd` and `turns`. The leading underscore keeps it out of the default adapter set (`bin/adapters.sh` skips names starting with `_`), so a nightly run never sees it. It is small on purpose: `slim` is a copy, `engine-bin` is `true`, and the argv subcommands print `true` plus the model. Its write subcommands carry the same atomic-destination shape as the claude adapter (`docs/adr/0003-adapters-and-engines.md#adapter-subcommands-write-through-a-unique-temp-in-the-destination-directory-refuse-a-directory-destination-and-verify-a-regular-file-afterwards`).

### Consequences

Keep the format unlike the real harnesses. `enumerate` ignores the date bounds because fixtures are not time-filtered.

## L1 resolves the engine first and keys the model by the engine, not by the session's source

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`adapter_l1_engine`, `adapter_l1_model`, `adapter_l2_model`)

### Context

Which harness holds a transcript and which engine reads it are separate choices: the run has one reviewer, the engine that writes the summary, unless the host picks another. A model id belongs to one engine: `neuralwatt/glm-5.3-flash` means nothing to claude. A source-keyed pin sent omp sessions to the claude CLI with an omp model id (see docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "Who starts the L1 worker").

### Decision

`adapter_l1_engine <source> <reviewer>` resolves, first match wins:

1. `AUTODREAM_L1_ENGINE_<NAME>`: that source only (name upper-cased, dashes to underscores).
2. `AUTODREAM_L1_ENGINE`: every source.
3. The run's reviewer, the L2 engine (`AUTODREAM_L2_ENGINE`, else the first enabled adapter), passed by the runner.
4. The source itself, only when no reviewer is passed.

Only the model call moves. The source's own adapter still enumerates, normalizes, describes and adds its triage notes. A choice that names no accepted adapter resolves nothing (exit 1), so the caller leaves those sessions untriaged instead of falling back to some other engine.

`adapter_l1_model` resolves the engine first, then, keyed by the engine and never by the source:

1. `AUTODREAM_L1_MODEL_<ENGINE>`: that engine only, whichever source's sessions it reads, like `AUTODREAM_L2_MODEL_<NAME>`.
2. `AUTODREAM_L1_MODEL`: every engine, an override for hosts with one engine.
3. The manifest's `l1_model`: that engine's default.

With the reviewer on claude, `AUTODREAM_L1_MODEL_OMP` therefore does not reach omp sessions, and an omp model id never reaches the claude CLI.

`adapter_l2_model` resolves `AUTODREAM_L2_MODEL_<NAME>`, `AUTODREAM_L2_MODEL`, then the manifest's `l2_model`. The manifest's `l2_model` may be absent, which for claude means "let the CLI pick", so the function exits 1 with no output and the caller passes no model at all.

### Consequences

A host can pin one engine without touching another. Do not key the L1 model by source. docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "Who starts the L1 worker" and "Which engine runs L2", state the same rules from the runner's side.

## an adapter's manifest is data read with jq, its identity is its directory basename, and containment is resolved, not assumed

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`_adapter_ok`, `adapter_manifest_get`, `adapter_run`)

### Context

Dispatch builds a command path from an adapter name (`$root/$name/adapter.sh`). Three ways to get that wrong are easy to write:

- A manifest in a format whose parser is bash would execute arbitrary code as the user when sourced, and becomes an injection surface the moment a third-party adapter is a reasonable idea.
- If a manifest field could name its own directory, it would reintroduce the path construction that JSON parsing was adopted to remove. Two disagreeing identities (field and basename) are the state where a later reader picks the wrong one.
- A basename check is not containment: `adapters/evil` may be a symlink pointing anywhere on the filesystem.

### Decision

- The manifest is JSON, read with `jq`, never sourced. `$HOME` is the only interpolation, done by substitution (`${v//\$HOME/$HOME}`) rather than evaluation, so a manifest holding backticks yields literal backticks.
- Identity is the directory basename, never a manifest field. The manifest's `name` must agree with the basename; a mismatch is a load-time refusal, not a silently preferred value.
- `_adapter_ok` resolves both the adapter directory and the adapters root with `realpath` and refuses the adapter unless the real directory is still under the real root. Every check ahead of it passes for a symlinked directory.
- `jq -e` fails on unparseable JSON, so a malformed manifest is refused whole rather than partially trusted.
- The dispatchers (`adapter_manifest_get`, `adapter_run`) re-check the name with `_adapter_name_safe`, because the identity argument is only true if the functions that build the path enforce it. Every caller today passes a name that came through `adapters_list`, so this guards the third-party adapter that arrives later, not a live hole.

### Consequences

A manifest field can never become a path, and a plugin format whose parser is bash is not on offer. Do not switch the manifest to a sourced file, and do not let `name` choose a directory. See `docs/adr/0003-adapters-and-engines.md#the-adapter-name-check-lists-its-characters-instead-of-using-ranges` for the character rule the check uses and docs/adr/0003-adapters-and-engines.md#background-several-harnesses-in-one-run-enabled-is-a-host-decision-and-every-session-goes-through-its-own-adapter, "Several harnesses in one run", for how an accepted adapter becomes an enabled one.

## the adapter name check lists its characters instead of using ranges

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`_adapter_name_safe`)

### Context

A safe adapter name starts with a lowercase letter and then holds only lowercase letters, digits, underscore and dash. It has no separators, so the name cannot walk out of the adapters root on its own. `[a-z]` is collation-dependent: under a UTF-8 locale the order is aAbBcC..., so the range matches uppercase too. The check therefore passed on macOS (C collation) and silently accepted an uppercase basename on Linux, which made a containment check weaker on the platform CI runs.

### Decision

`_adapter_name_safe` spells out `abcdefghijklmnopqrstuvwxyz` and `0123456789_-` in its patterns. Enumeration has no collation ambiguity. It is a function of its own, separate from `_adapter_ok`, because the dispatchers need it too (see `docs/adr/0003-adapters-and-engines.md#an-adapters-manifest-is-data-read-with-jq-its-identity-is-its-directory-basename-and-containment-is-resolved-not-assumed`).

### Consequences

Do not "simplify" the patterns to `[a-z]` or `[0-9]`-style ranges, which depend on the locale. The behavior only differs under a UTF-8 locale on Linux, so a macOS-only run will not show a regression.

## the network probe URL is derived from the model each layer calls, and an unknown provider means "cannot answer"

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`provider_probe_url`)

### Context

`net_up` probes one URL per engine layer. L1 on the omp adapter runs `deepseek/...` and L2 on omp runs `anthropic/...`, so a probe pinned to `api.anthropic.com` read a dead deepseek route as healthy and a dead anthropic one as a deepseek outage.

### Decision

The provider is the part of the model id before the slash. The claude adapter has no provider prefix: it always talks to Anthropic, even with no model named (the CLI's own default). `AUTODREAM_NETUP_URL_<PROVIDER>` (upper-cased, non-alphanumerics to `_`) pins one provider's probe URL. Otherwise a fixed table maps `anthropic`, `deepseek`, `neuralwatt`, `zai`/`z-ai` and `runinfra` to their API hosts. A model with no slash, or a provider not in the table, exits 1 with no output, which the caller reads as "cannot answer", not "down".

### Consequences

A new provider needs a row in the `case` and a test. Do not make an unknown provider fall back to the Anthropic URL: that is the false reading this function replaced.

## refusals are recorded in a file, and an unreadable record reports `unknown`, never `none`

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`adapters_reject_log`, `adapters_rejected`, `_adapter_reject`, `_adapter_reject_broken_marker`, `adapters_list`, `_adapter_ok`)

### Context

`adapters_list` is almost always called as `$(adapters_list)`, and a variable assigned inside a command substitution never comes back to the caller. This is the same trap that cost the repo the cookie-expiry remediation text in `vault-notes.sh`, where `FAIL_REASON` was set inside nested `$(...)` and died with the subshell. The loader's first reject-flag was a shell variable set from `_adapter_reject`, from `_adapter_ok`, from `adapters_list`: the assignment died with the subshell and the flag was always 0 in the parent. It was the third time this trap was laid in this repo.

The count of refusals goes to `run-stats.txt`. A false `none` is worst on the total-outage path: the loader refuses every adapter, `run.sh` fatals with "accepted no adapters (rejected: none)", and the operator is told nothing was refused when everything was.

### Decision

- Refusals go to a log file (`ADAPTERS_REJECT_LOG`, so callers can point it at a findings dir). A file crosses the subshell boundary; a variable does not.
- The default log is `${TMPDIR:-/tmp}/autodream-adapters-rejected.$$`, not a path in the adapters root. `_adapter_reject` only appends and only `run.sh` truncates, so a repo-tree default made any other caller (an interactive `. bin/adapters.sh; adapters_list`, a future tool) accumulate refusals across invocations, and `adapters_rejected` then reported stale names as this run's. It also left untracked cruft in a checkout that `.gitignore` does not cover. The PID in the name keeps two callers from cross-contaminating.
- `adapters_rejected` prints `none`, never an empty string. `run.sh` writes it straight into `run-stats.txt`, and `adapters_rejected: ` with nothing after it cannot be told apart from a key that was never measured, the ambiguity `overlap_measured` and `stats_sidecars_unparseable` exist to refuse. A caller-side `|| printf none` cannot save it because returning 0 with no output is success.
- When the log could not be written, `_adapter_reject` drops a marker file and `adapters_rejected` prints `unknown (the reject log could not be written)` instead of a confident `none`. The refusals happened; the loader just cannot name them. The marker is a file for the reason above, and it lives in `TMPDIR`, because the case being reported is precisely the log's directory being unwritable.
- The append is `{ printf '%s\n' "$1" >> "$log"; } 2>/dev/null`. The braces matter: `printf ... >> "$log" 2>/dev/null` sets up the append before the suppression, so bash reports a failure to open `$log` on the original stderr and the line only reads as silenced. It showed in `tests/adapters.sh` as a raw `bin/adapters.sh: line NN: ...: Is a directory`. `run.sh` captures this call under `adapters_list 2>/dev/null`, so the nightly never saw it; any other caller does.
- `adapters_list` globs both `"$root"/*/` and `"$root"/.*/`. The first never matches a dot-prefixed directory, so a hostile or malformed `.evil` was silently invisible instead of recorded as a refusal, and `adapters_rejected` then reported `none` when something was refused. `.` and `..` are skipped.
- A leading underscore marks a test-only adapter. `_adapter_ok` excludes it without recording it, because it is a deliberate exclusion rather than a refusal worth counting.

### Consequences

Do not turn the log or the marker into shell variables, and do not move the log default back under the adapters root. `run.sh` and `tests/adapters.sh` rely on `none` and `unknown (...)` being distinct from a measured zero.

## the L2 system prompt has one copy, found through the install symlink, and a missing or blank copy is an error

Status: accepted · Date: 2026-11-21 · Code: `bin/l2-prompt.sh` (`l2_system_prompt`)

### Context

Every L2 engine runs under the same system prompt, kept in `prompts/L2_SYSTEM.txt`, so the claude adapter, the omp adapter and `run.sh`'s built-in claude fallback all say the same thing. It states the stdout grammar that `bin/report-format.sh` parses: the report, `AUTODREAM_REPORT_END`, the optional pin block and the summary. This file is sourced, never executed. docs/adr/0003-adapters-and-engines.md#background-which-engine-runs-l2, "Which engine runs L2", names the same rules.

### Decision

- A change to the grammar is one edit in `prompts/L2_SYSTEM.txt` and one in `report-format.sh`.
- An installed copy of this script is a symlink into the checkout, and the prompt sits beside `bin/` there. The function resolves its own symlink, then looks at `../prompts/L2_SYSTEM.txt`, then at `$AUTODREAM_DIR/L2_SYSTEM.txt`.
- A candidate must hold a non-whitespace character. A file of blank lines would start an engine with an empty instruction.
- When no copy can be read, the function prints the reason on stderr and returns 2. It prints the text with no trailing newline added.

### Consequences

An engine started without this prompt would run L2 with no instruction about where the report goes, and the output would look like a night's work. That is why a missing prompt fails the run and is never defaulted to an empty string.

## the built-in `claude` adapter fallback fires only when the adapter machinery is absent, never when the loader accepted nothing

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`_enabled_adapters_uncached`)

### Context
An install symlinked at a tree predating `adapters/` has no loader, and a partial upgrade should degrade instead of losing a night. But a tree that is present from which the loader accepted nothing is a REFUSAL (a claude directory rejected for failing containment or carrying a mismatched manifest): manufacturing `claude` back into the list would execute a rejected adapter anyway, which turns every check in `adapters.sh` into decoration.

### Decision
"Genuinely absent" means the loader is not sourced (`declare -F adapters_list` fails) OR the adapters tree does not exist (a tarball or partial install): return `claude`. A present tree with nothing accepted returns the empty list, which `scan_roots` turns into a fatal. Conflating the two broke a non-git install test in the first version and would have let a rejected adapter run.

### Consequences
Do not widen the fallback condition. See docs/adr/0003-adapters-and-engines.md#background-several-harnesses-in-one-run-enabled-is-a-host-decision-and-every-session-goes-through-its-own-adapter, "Several harnesses in one run".

## the claude adapter scans root-probe's roots; every other adapter uses its own configured or manifest roots; roots are newline-terminated

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`adapter_roots`)

### Context
root-probe decides which `$HOME/.claude*/projects` dirs are indexed and the user's per-folder choices live there, but it knows nothing about a second harness's store. Separately, `while read` drops a final unterminated line, so an earlier `printf '%s'` here silently skipped the only root on a single-root host: enumeration found nothing and reported a quiet zero.

### Decision
For `claude`, `adapter_roots` prints `SESSION_ROOTS` split on `:`. For any other adapter it prints `AUTODREAM_SESSION_ROOTS_<NAME>` if set (name upper-cased, `-` to `_`), else the manifest's `session_roots_default[]`. EVERY output line is newline-terminated (`printf '%s\n'`).

### Consequences
Keep the `\n` in each `printf`; the single-root case is the default install. A new harness's roots belong in its manifest, not in root-probe. See docs/adr/0003-adapters-and-engines.md#background-several-harnesses-in-one-run-enabled-is-a-host-decision-and-every-session-goes-through-its-own-adapter, "Several harnesses in one run".

## a directory under adapters/ makes an adapter accepted, not enabled; the host enables it with AUTODREAM_ADAPTERS

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`_enabled_adapters_uncached`, `AUTODREAM_ADAPTERS`)

### Context
Which harnesses a run scans is a host decision. Merging a new harness must not change what a live nightly reads.

### Decision
`AUTODREAM_ADAPTERS` is a space- or comma-separated list of names, or `all`, default `claude`. Accepted adapters not in it are logged as "accepted but not enabled" and not enumerated. Hosts that want omp say so in their config. See docs/adr/0003-adapters-and-engines.md#background-several-harnesses-in-one-run-enabled-is-a-host-decision-and-every-session-goes-through-its-own-adapter, "Several harnesses in one run: enabled is a host decision".

### Consequences
A new adapter ships dormant; enabling it also needs a re-install if the engine binary has to reach the launchd PATH.

## Adapter refusals are logged under this run's findings dir, not in the installed source tree

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `ADAPTERS_REJECT_LOG` export before `scan_roots`)

### Context
Adapter refusals used to be written back into the installed source tree, where they persist across runs and vanish entirely on a read-only install.

### Decision
`run` exports `ADAPTERS_REJECT_LOG="$FINDINGS_DIR/.adapters-rejected"` and truncates it (`: > ... || true`) before `scan_roots`, so refusals belong with this run's artifacts. `adapters_rejected` (the `adapters_rejected:` run-stats line) reads from there.

### Consequences
- The file is per findings dir, so a rebuild of a date starts it empty again.
- A failure to truncate is ignored on purpose: a read-only findings dir must not stop the run here.
- Pointing the log back into the adapters tree reintroduces cross-run persistence and the read-only-install failure.

## an engine's login is read once with a model-free whoami, checked against AUTODREAM_REQUIRE_LOGIN, and an ended claude.ai sign-in is a refusal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`engine_login_ok`, `login_expiry_warn`, `ENGINE_LOGINS`, `LOGIN_REFUSAL`)

### Context
A run on the wrong account bills or authenticates the wrong login, and a claude.ai sign-in past its end date fails every model call. The answer must be known before the engine is handed anything, without spending a model call.

### Decision
- Each engine is asked once through the adapter's `whoami` verb (claude: `claude auth status`, no model call); an engine without the verb reports `unknown`. The answer is logged once and kept in `ENGINE_LOGINS` (engine, provider, auth, plan, account, expires; tab-separated) for run-stats.
- `AUTODREAM_REQUIRE_LOGIN` lists `key=value` pairs (provider, auth, plan, account) that must all match; a claude.ai sign-in past its end date fails too, since every model call on it would. Either way `engine_login_ok` returns 1 with the reason in `LOGIN_REFUSAL`.
- A claude.ai sign-in that ends within `AUTODREAM_LOGIN_WARN_DAYS` (default 10, the lead time Claude Code's own `claude -p` warning uses) posts one warning banner per engine per run, in a notification group of its own (`login-<engine>`) so a later warning on the same date cannot replace it. One that has already ended posts nothing here: `engine_login_ok` refuses it, and the caller's failure says so.

### Consequences
Keep the warning group per engine; a shared group lets the changelog or remote-sync warnings replace it. A malformed or non-claude.ai expiry never refuses a run (`login_seconds_left` fails closed to "unknown").

## The L1 engine is resolved before its model, and an engine that fails its login check is removed before any transcript is sent

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the per-source engine/model loop and the `engine_login_ok` loop)

### Context
A source's engine choice that names no accepted adapter must not fall through to some other engine. Every L1 engine must meet `AUTODREAM_REQUIRE_LOGIN` before a transcript goes to it. See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, 'Who starts the L1 worker' ("The engine, then the model", "No engine is an error for this run's config, not forever").

### Decision
- For each source, `adapter_l1_engine` is resolved first. A choice that names no accepted adapter leaves that source with no model (and a WARNING), so its sessions get error records instead of a call on some other engine.
- `AUTODREAM_L1_MODELS`, `AUTODREAM_L1_ENGINES` and `AUTODREAM_L1_PROBE_URLS` are built from that resolution.
- Each engine in use is checked with `engine_login_ok`. One that fails has its column blanked in `AUTODREAM_L1_ENGINES`, so its sessions take the same path as a choice naming no accepted adapter (error records, no model call).

### Consequences
- Do not resolve the model first, and do not let a pinned engine that is not an accepted adapter fall through to another engine. An unset engine does default (`AUTODREAM_L1_ENGINE_<SOURCE>`, then `AUTODREAM_L1_ENGINE`, then the run's reviewer, passed as `_reviewer`), but the model is keyed by the resolved engine: a source-keyed model pin once sent omp sessions to the claude CLI with a model id from another engine (PR #165 review, per docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation).
- The login failure is a config problem for this run, so those records are dropped and retried on a later run that resolves an engine.

## The lean-query environment is exported once, and `--bare` is not used

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `export CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 ...` line before L1)

### Context
L1 and L2 need a token-minimal footprint without losing subscription OAuth auth. `--bare` disables OAuth/keychain auth and requires an API key. The pattern is borrowed from claude-cells `internal/claude/query.go`. See docs/adr/0003-adapters-and-engines.md#background-how-claude-is-invoked--the-lean-query-pattern-do-not-use---bare, 'How claude is invoked — the lean-query pattern (do not use `--bare`)'.

### Decision
`CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1` are exported once, so both the L1 xargs subshells and the L2 call inherit them. They combine with the per-call flags (`--no-session-persistence`, `--tools`, `--disable-slash-commands`, `--strict-mcp-config`, `--settings disableAllHooks`), which now come from the adapter's argv.

### Consequences
- Do not switch to `--bare` or `CLAUDE_CODE_SIMPLE=1`: both return "Not logged in" on this host.
- A new env stripping belongs in this one export so both layers inherit it.

## which model answered an L1 call is read from the engine result and judged by the adapter, and the verdict is stored with the answer it describes

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`; `l1-served.tsv`, `<answer>.served`)

### Context
The CLI answers with a canonical id (`claude-haiku-5-5`) for a model requested by alias (`haiku`), and only the adapter knows its CLI's naming, so a string compare in run.sh would be wrong. An engine that reports nothing must not be counted as a match or a mismatch.

### Decision
- After every call, whatever it produced, `adapter.sh served <stdout> <model>` returns the models that answered, a cost estimate and a verdict, `match` or `mismatch`. Any verdict other than those two, or a failure of the verb, is recorded as `unmeasured` (models `unknown` when the verb gave none). The row goes to `l1-served.tsv`.
- With `AUTODREAM_L1_REQUIRE_SERVED=1` a call that wrote findings but whose verdict is not `match` loses them (and its `.served`) and fails with a line in the `.err` that says which, so nothing a substituted or unverifiable model wrote reaches L2.
- The runner writes `<answer>.served` (engine, requested model, models that answered, verdict) after the engine has exited, replacing anything the worker wrote there. A later run reads it before reusing the answer: with `REQUIRE_SERVED=1` a cached findings JSON or chunk answer is reused only when it says `match` (`drop_unacceptable_l1_cache` in the parent).

### Consequences
See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "What answered, and whether it counts". `docs/adr/0003-adapters-and-engines.md#the-claude-adapter-judges-whether-the-requested-model-answered` covers the claude adapter's `served` verb.

## the L1 engine, model and source of each session come from parent-built environment, never from files under the findings dir

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, `AUTODREAM_SOURCE_MAP`, `AUTODREAM_L1_MODELS`, `AUTODREAM_L1_ENGINES`)

### Context
An L1 worker holds the Write tool and could rewrite `sessions-source.txt`. The source decides which binary the next worker executes.

### Decision
The worker looks the source up in `AUTODREAM_SOURCE_MAP`, the model by source in `AUTODREAM_L1_MODELS`, and the engine in `AUTODREAM_L1_ENGINES` (usually the same name as the source). All three are built before the first model call. A source or engine that is empty or has a character outside `[a-z0-9_-]` is cleared, and a session left without a source, engine, model or runnable adapter gets a `no_engine: true` findings record instead of a worker. An empty engine means the engine override named no accepted adapter. The adapter prints its own argv (`l1-argv`) and environment (`l1-env`), so nothing in the worker names claude or omp.

### Consequences
Reading the findings dir instead fails `test_l1_engine_cannot_be_redirected_by_a_worker`. See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "Who starts the L1 worker".

## one triage document serves every harness, and a harness that differs adds an addendum appended for its own sessions only

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`, prompt assembly)

### Decision
`l1_attempt` always appends `SESSION_TRIAGE.md`. When the session's source adapter (`$src`, which can differ from the L1 engine) ships `adapters/<name>/triage.md`, it is appended after a blank line for that adapter's sessions only, so a claude worker receives exactly the text it always did.

### Consequences
A new harness adds `adapters/<name>/triage.md` and no code here. The chunk cache name (`ccfg`) hashes the addendum, so editing it invalidates cached chunk answers. See docs/adr/0003-adapters-and-engines.md#background-one-triage-document-one-addendum-per-harness-that-differs, "One triage document, one addendum per harness that differs".

## L2's skills inventory and per-harness facts come from the adapters, and facts are taken only for sources that had sessions, from the pre-model source map

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`write_adapter_inputs`)

### Context
L2 needs to know which skills are installed and what each contributing harness offers, so its remedies exist for the harness the evidence came from (a `permissions.allow` entry means nothing to omp). An empty inventory would claim no skills are installed. A worker could rewrite a file under the findings dir.

### Decision
- `skills-inventory.txt` is the union of every enabled adapter's `skills-inventory` output (a name, optionally a TAB and a description), deduplicated by name with the first winning. If every adapter fails, the file says `# skills-inventory.txt unavailable` and PROMPT.md tells L2 not to file coverage gaps from it.
- `adapter-facts.md` holds one `## Source: <name>` section with that adapter's `facts.md`, only for sources that actually had sessions tonight, taken from `AUTODREAM_SOURCE_MAP` captured before any model ran, never from a file a worker could have rewritten. A source whose adapter has no `facts.md` gets no section.
- A new harness adds `adapters/<name>/facts.md` and a `skills-inventory` verb, not code here.

### Consequences
See docs/adr/0003-adapters-and-engines.md#background-what-l2-is-told-about-each-harness-skills-inventorytxt-adapter-factsmd, "What L2 is told about each harness".

## a built-in claude L2 invocation remains for installs whose adapters tree predates `l2-argv`

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `L2_ENGINE = claude` fallback block; `l2-prompt.sh`, `prompts/L2_SYSTEM.txt`)

### Context
An install whose `adapters/` tree predates `l2-argv` (the per-file symlink installs this script supports, see `enumerate_for`) still has to deliver the night. The fallback is claude-only, for the same reason `enumerate_for`'s is: it hardcodes one engine's invocation. The system prompt is `prompts/L2_SYSTEM.txt`, the same text the adapters read. Without it no argv is built at all (a WARNING fires), because an L2 run with no word on where the report goes only looks like a night's work.

### Decision
When `L2_ARGV` is empty and the engine is `claude`, the runner loads the prompt via `find_lib l2-prompt.sh` / `l2_system_prompt` and builds `claude --print ... --tools Glob Read ... --append-system-prompt`. Otherwise it warns. See docs/adr/0003-adapters-and-engines.md#background-which-engine-runs-l2, "Which engine runs L2".

### Consequences
`tests/l2-prompt.sh` greps `run.sh` for the string `l2-prompt.sh`; keep the loader call. Do not extend the fallback to other engines.

## an empty L2 argv is replaced with `false`, never run

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_ARGV=(false)`)

### Context
The original comment says an empty argv would run a bare `env`, which prints the environment into the report capture. That described the older `env <envs> <argv>` form. Through today's wrapper, `env <envs> /bin/sh -c '... exec "$@"' <pidfile>` with no argv runs `exec` with no command, which does nothing and exits 0, so the attempt would capture nothing and look like a clean exit instead of failing (checked by running the wrapper with no argv).

### Decision
When no L2 command could be built, `run.sh` logs a WARNING and sets `L2_ARGV=(false)`, so every attempt fails visibly and nothing is captured.

### Consequences
Do not "simplify" by dropping the placeholder: the pipeline is `env <envs> /bin/sh -c '... exec "$@"' <pidfile> <argv>`, and with no argv the attempt exits 0 with an empty capture, not the visible failure `false` gives.

## Every L2 engine requirement is checked before L1 is paid for

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the gates after `build_source_sidecar`)

### Context
L2 runs after L1. A requirement of the L2 engine found missing after L1 means a night of paid triage and an aggregator with nothing to run: every L2 attempt fails after the spend. See docs/adr/0003-adapters-and-engines.md#background-which-engine-runs-l2, 'Which engine runs L2'.

### Decision
After the roots are scanned (`scan_roots`, `build_source_sidecar`) and before any L1 worker runs, `run` refuses to start (`log_fatal`, `fatal_exit`, return 1) when:
- `AUTODREAM_L2_ENGINE` is set and is not an accepted adapter (`adapters_list`).
- `prompts/L2_SYSTEM.txt` cannot be read through `bin/l2-prompt.sh` (`find_lib l2-prompt.sh`, `l2_system_prompt`). This is checked for every engine, claude included: its built-in fallback reads the same file, and an engine started without it runs L2 with no word on where the report goes.
- The review engine is not `claude` and its adapter cannot print an L2 command (`adapter_run <engine> l2-argv [model]` prints nothing, for example omp with no model resolved or an adapter without `l2-argv`). The probe skips claude, whose built-in fallback builds the command itself.
- The review engine fails `engine_login_ok` (`AUTODREAM_REQUIRE_LOGIN`). The engine that writes the summary (and runs dream triage) receives every finding, so its login is held to the requirement before anything is read.

### Consequences
- A new L2 engine requirement belongs in this block, not in the L2 attempt loop, or its failure costs a full L1 spend.
- The claude exemption exists only because of the built-in fallback; removing the fallback removes the exemption.

## the L2 engine is an adapter and `run.sh` names no binary for it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `review_engine`, `adapter_run "$L2_ENGINE" l2-argv`, `l1-env`)

### Context
The engine that runs L2 is chosen by `AUTODREAM_L2_ENGINE` and by default is the first enabled adapter. It prints its own argv (`adapters/<name>/adapter.sh l2-argv`). The model resolves per adapter (`AUTODREAM_L2_MODEL_<NAME>`, then `AUTODREAM_L2_MODEL`, then the manifest). None at all is legitimate and means the engine's own default. A model id belongs to one engine, which is why the per-adapter form exists.

### Decision
The runner reads NUL-delimited argv and the adapter's env lines into `L2_ARGV` and `L2_ENVS`, and records `l2_engine` and `l2_model` in run-stats, because neither is fixed by `run.sh` and when a report's character changes the first question is what produced it; the answer has to survive in the artifact, not only in a log. `default` is the honest `l2_model` value when no model was named, since the engine picks and this script is not told what it picked. The keys are absent on a zero-session night, which returns before L2 runs. See docs/adr/0003-adapters-and-engines.md#background-which-engine-runs-l2, "Which engine runs L2".

### Consequences
A new engine is a new adapter, not a branch in this file. The only engine-specific code left is the claude-only fallback (`l2-builtin-claude-fallback-for-old-adapters-tree`).

## the L2 engine is started through a one-line sh that records its pid and then execs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_PIDFILE`, `/bin/sh -c 'printf %s "$$" > "$0"; exec "$@"'`; `l2_diag_start`, `l2_diag_end`)

### Context
Issue 42: L2 attempt 1 died with exit 143 on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02 with no record of who sent the signal (see the `L2 attempt diagnostics (issue 42)` comment above `l2_diag_start`). `run.sh` applies no timeout of its own to L2, so the TERM comes from outside. When an attempt exits 143, 137 or 124, `l2_diag_end` writes `findings/<date>/l2-attempt-N.diag` (see `l2-attempt-diagnostics-are-evidence-only`). The diagnostics need the engine's own pid, not a wrapper's.

### Decision
The engine starts through `/bin/sh -c 'printf %s "$$" > "$0" ...; exec "$@"'`, so the pid in the diagnostics is the engine's. `exec` keeps the pid, stdin and argv. If the pid file cannot be made (`mktemp` fails), `L2_PIDFILE` is `/dev/null` and the diagnostics have no pid to read.

### Consequences
Do not insert a wrapper process between the sh and the engine; the diag file would name the wrong pid.

## no L2 model is pinned by default; a pin must be an exact string

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, L2 engine and model resolution; `adapter_l2_model`)

### Context
A pin is a decision to re-make every time the roster moves, and a date-gated branch (since removed) hid that and left an unreachable default. With no `--model` the aggregator runs on whatever the CLI's default is, so upgrading the account upgrades the nightly report and nothing here has to be edited.

`AUTODREAM_L2_MODEL` overrides, for pinning deliberately. If it is set, pin an EXACT string: the CLI silently falls back on an unrecognized `--model` rather than failing (verified 2026-06-09 on 2.1.170; bare `claude-fable-5` was one of those, where `fable` and the `[1m]`-suffixed form both worked). A silent fallback is why the resolved value is recorded in run-stats (`l2_model`, with `default` when no model was named: the engine picks and `run.sh` is not told what it picked).

### Decision
`L2_MODEL=$(adapter_l2_model "$L2_ENGINE")`; empty means the engine's own default and no `--model` is passed (`${L2_MODEL:+--model ...}`). See docs/adr/0003-adapters-and-engines.md#background-which-engine-runs-l2, "Which engine runs L2".

### Consequences
Do not add a default model here. When someone pins one, check `modelUsage` of a real run, not the flag.

## L2 holds Glob and Read only, so the runner is the only writer of the report and pins

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the L2 call; `report_body`, `report_pin_lines`)

### Context
L2 cannot write the report, `pins.jsonl`, or anything else under the findings directory. The one hostile-input surface that used to need a quarantine (an L2 that rewrote `sessions-source.txt` or forged a pin) is closed at the tool grant.

### Decision
`$REPORT_PATH` and `pins.jsonl` are written by the runner from L2's stdout. See docs/adr/0009-l2-aggregation.md#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15, "L2 is read-only: the report and the pins arrive on stdout".

### Consequences
Never give L2 a Write tool to simplify delivery. Any new file L2 needs is read by exact path and written by the runner.

## one `review_engine` function names both the L2 summary engine and the default L1 engine

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`review_engine`)

### Context
The run's reviewer is the engine that writes the summary (`AUTODREAM_L2_ENGINE`, else the first enabled adapter), and by default it also reviews every source in L1.

### Decision
Both read the same function, so the per-session pass and the summary cannot drift onto different engines unless the host asks (`AUTODREAM_L1_ENGINE`, `AUTODREAM_L1_ENGINE_<NAME>`). See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "The engine, then the model" and "Which engine runs L2".

### Consequences
A new place that needs "the engine" calls `review_engine` instead of re-deriving it.
