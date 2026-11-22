# tests: run-all-harness-and-engine-isolation: run-all: harness, env and engine isolation, and how the suite counts failures

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (top-level exports, `setup_env`, `mk_session`, `run_dream`, `remove_path`), `tests/run-all.sh` (`run_dream_autodetect`, `test_multiroot_heldout_and_dedup`), `tests/run-all.sh` (`test_config_env_wins_over_config`, `test_notes_header_only_file_does_not_abort`, `test_notes_icloud_placeholder_is_counted`, `test_notes_expiry_uses_report_date`, `test_config_unbound_var_does_not_kill_run`); see CLAUDE.md "Bash traps this feature hit", `tests/run-all.sh` (`run_chunked`, `test_a_failed_chunker_never_hands_a_worker_the_whole_slim`, `test_a_cached_chunk_answer_is_not_reused_on_another_engine`), `tests/run-all.sh` (`run_dream_omp`, `test_omp_sessions_run_on_another_adapters_engine`), `tests/run-all.sh` (`l1_confine_real`, `fake_sandbox`, `test_l1_forged_writes_are_refused_when_confined`, `test_l1_worker_setup_failure_defers_the_date_and_follows_no_planted_link`, `test_l1_confine_setup_stops_when_a_protected_directory_cannot_be_listed`), `tests/run-all.sh` (`test_oversized_gate_script_args`), `tests/run-all.sh` (the `for _suite in $_suites` loop), `tests/run-all.sh` (`_owns`, `_run`, `_timed`, `RUNALL_SHARD`), `tests/shard.sh`

## the harness pins every piece of host state out of a run

### Context

`run.sh` reads the developer's real environment: `~/.local/bin` on PATH (where the real `shared-memory` CLI lives), `~/.claude/autodream/config`, a real `curl`, a real remote-root list, the changelog remotes. Each has reached, or could reach, something real. A developer whose config points `AUTODREAM_VAULT_DIR` at a live Obsidian vault would have the suite writing notes and reports into it. A test whose L2 emits pins would store them in the real Mnemopi. A failing worker probes the network with `curl` at 5 seconds a call.

### Decision

- `SHARED_MEMORY_BIN` points at a path that does not exist. Pin tests override it with `tests/mock-shared-memory.sh`.
- `AUTODREAM_L1_CONFINE=0`: the mock engines write capture files anywhere, so the suite runs L1 unconfined (#169). The confinement tests turn it on.
- `AUTODREAM_REMOTE_ROOTS` is unset. The remote_sync tests set it themselves.
- `run_dream` defaults the changelog check off (the changelog test exports `AUTODREAM_CHANGELOG=1` with a local remote), forces the retry and network knobs fast and offline, and pins `AUTODREAM_CONFIG` into the sandbox. It also puts a `curl` shim that reports a reachable host first on PATH. Tests that care about an outage set `TEST_CURL_SHIMMED=1` and bring their own shim.
- `THREADS_TEST_TIMEOUT_BIN` falls back from `timeout` to `gtimeout`. GitHub's macOS image has no `/usr/bin/timeout`, and only Homebrew coreutils provides one (#221).
- `remove_path` deletes through python3, because `/usr/bin/trash` exists only on macOS and CI runs Linux.
- `mk_session` writes two real user turns with no timestamps. `duration_minutes` 0 is uncomputable and exempt from the duration rule, so the fixture clears the noise gate's default `AUTODREAM_MIN_USER_TURNS=2` floor and every test that expects real L1 triage keeps getting it.
- An unattended run logs to its file and stdout carries only a pointer, so `run_dream` appends the run log to `run.out`. Assertions then read what a nightly run recorded, not what a tty run echoes.

### Consequences

A new run-time knob that reaches outside the sandbox needs a pin here. Raising the noise-gate floor means `mk_session` must grow a turn.

## the multi-root fixtures autodetect roots from a sandbox HOME

### Context

Multi-root scanning is only exercised when `run.sh` autodetects `$HOME/.claude*/projects` through `bin/root-probe.sh`. If the fixture exported `PROJECTS_DIR` or `SESSION_ROOTS`, autodetection would be bypassed and the test would pass over code it never ran. Autodetecting against the real `$HOME` would instead scan the host's own claude dirs.

### Decision

- `run_dream_autodetect` leaves `PROJECTS_DIR` unset and points `HOME` into the sandbox (`$root/home`), so root-probe discovers the sandbox's `.claude*` dirs and nothing from the host.
- `test_multiroot_heldout_and_dedup` puts a symlink to the primary's `s2.jsonl` in the alt root and asserts the path appears once in `sessions.txt.raw`. The claude adapter's `enumerate` runs `find "$1" -type f` without `-L`, so `find` skips that symlink, the path appears once whether or not the final `sort -u` runs, and the assertion does not exercise deduplication. The test pins the held-out and flagged-root behavior only.

### Consequences

Do not export `PROJECTS_DIR` or `SESSION_ROOTS` from these helpers. Do not read the symlink assertion as proof of dedupe; a fixture that reaches the same file by two paths the enumerator reports would be needed for that. CLAUDE.md, "Session roots: one dir is not the corpus", records the scanning rules.

## operator-notes and config fixtures reproduce the exact shape that failed

### Context

Each fixture below passes against a plausible but wrong implementation unless it has the exact shape.

### Decision

- Config: `run.sh` sources the config with `set -a` and replays the caller's `export -p` snapshot afterwards. The config uses plain `KEY=value`, so a naive `.` lets the file override a caller who deliberately exported something. The test sets different vaults in env and config and asserts the env one is read.
- Header-only `notes.md`: exactly what `autodream-note.sh` leaves after the user deletes the notes a report said were addressed. `grep -c` prints `0` and exits 1, so a `|| echo 0` fallback made the count `"0\n0"` and the arithmetic killed collect under `set -e`.
- iCloud placeholder: an evicted note is not a zero-byte `.md`. The real file is gone and only the dot-prefixed `.<name>.icloud` remains, so a `*.md` walk matches nothing. The fixture must be the placeholder file.
- Expiry: the fixture expires 2020-06-01, long after the reported `$DATE` and long before today, so a wall-clock comparison drops and archives a note that was active for the window.
- Unbound config variable: `$AUTODREAM_HOME` must stay undefined. Under `set -u` it used to abort bash before the log file or `log()` existed, so the night produced nothing and said nothing.

### Consequences

An empty-file fixture, a present `.md`, or a near-future expiry makes these tests pass with the guarded code removed.

## chunking tests scope their environment to a subshell, and export the slim modes on purpose

### Context

The chunking tests change knobs that `run.sh` reads from the environment: `AUTODREAM_L1_CHUNK_BYTES`, `AUTODREAM_SLIM_FULL`, `AUTODREAM_SLIM_RESHAPE`, and `HOME` for the omp adapter, which enumerates `~/.omp`.

- `VAR=x run_chunked` combined with an `export VAR` inside the function leaves `VAR` set after the call on bash 5, while bash 3.2 restores it. The next test then inherited a stale `CHUNK_BYTES` and never chunked. Linux CI runs bash 5 and macOS runs 3.2, so a local macOS pass hid it.
- A caller that has already set `AUTODREAM_SLIM_FULL=1` or `RESHAPE=1` must not leak into the chunker's failure fallback. A leak would turn the capped head/tail slim into the whole transcript.

### Decision

`run_chunked` sets `AUTODREAM_L1_CHUNK_BYTES` inside a `( ... )` subshell, so the knob cannot outlive the call. The engine-change test runs its second run in a subshell for the same reason: the sandbox `HOME` cannot outlive it. The failed-chunker test exports `AUTODREAM_SLIM_FULL=1` and `AUTODREAM_SLIM_RESHAPE=1` deliberately: the assertion that the worker still receives the capped slim only has power while those modes are set.

### Consequences

Do not turn the subshell into a bare `export` to save a fork, and do not drop the two exports from the failed-chunker test. With them removed, the test passes against a fallback that reads the uncapped slim. Run chunking changes under both `/bin/bash` 3.2 and a bash 5 (the Linux CI path); the difference is invisible on one interpreter.

## the omp run helper pins omp sessions to the omp engine

### Context

An L1 engine resolves per source: `AUTODREAM_L1_ENGINE_<SOURCE>`, then `AUTODREAM_L1_ENGINE`, then the run's reviewer, which is the first enabled adapter. With `claude,omp` enabled, claude is first, so without a pin omp sessions would silently run on the claude CLI and the omp tests would exercise the wrong engine.

### Decision

- `run_dream_omp` exports `AUTODREAM_L1_ENGINE_OMP` as `omp` by default, using `${AUTODREAM_L1_ENGINE_OMP-omp}` so a caller who sets it, including to the empty string, wins.
- A test about the reviewer exports `AUTODREAM_L1_ENGINE_OMP=` (empty) to clear the pin.

### Consequences

Use the `-` form, not `:-`: the empty value is the supported way to clear the pin. CLAUDE.md, "Who starts the L1 worker", explains the engine-then-model resolution.

## the suite runs L1 unconfined, and the confinement fixtures use a fake sandbox-exec and patched adapter copies

### Context

The mock engines write capture files wherever they like, so the suite exports `AUTODREAM_L1_CONFINE=0` (CLAUDE.md, "What the sandbox allows"). The answer still goes through a staging directory and the runner's copy (#169), which the confinement tests pin. A real `sandbox-exec` cannot start inside another sandbox, which is where the suite often runs.

### Decision

- Tests that need a real sandbox run only when `l1_confine_real` says the probe passes, and print a skip line otherwise.
- `fake_sandbox` is a `sandbox-exec` stand-in that passes the probe by making the probe's outside directory (its last argument) read-only, then runs the command. Run-level tests use it so they work inside another sandbox.
- The forged-writes test first runs the same hostile worker unconfined and asserts every write lands. The later refusals mean something only because the unconfined run showed the writes were possible.
- The setup-failure test patches a copy of the claude adapter with `sed`. The added `l1-stage-env` verb passes the setup dry run (a stage named `.setup-*`) and fails every attempt after it, planting a symlink at the old stderr path inside the stage first.
- The colon test moves only `AUTODREAM_DIR` to a path with a colon. A colon in the session root would read as two roots and fail for a different reason.

### Consequences

Removing the unconfined control makes the refusal assertions unfalsifiable. A fake that confines nothing proves only the runner's plumbing, not the profile; `tests/l1-confine-real.sh` is the manual check for the real call.

## the oversized-gate argument tests resolve a GNU timeout and fail loudly without one

### Context

`oversized-gate.sh --days` with no value left `$#` at 1 while `shift 2` refused to shift, so the script looped forever (found in review). A hang in a script next to the nightly is worse than a wrong number. The test has to bound each call, and stock macOS has no `timeout`. Homebrew coreutils installs `gtimeout`, and `timeout` too if its gnubin is on `PATH`.

### Decision

The test uses whichever of `timeout` or `gtimeout` exists. When neither does, it records a failure that names the missing tool and returns. These are the only assertions in the suite that need GNU `timeout`.

### Consequences

Without the resolution step, all four assertions return exit 127 and read as regressions in the script. A passing run needs exit 2, and exit 124 means the hang is back.

## a unit suite that dies before printing a total counts as one failure

### Context

`run-all.sh` runs each unit suite as a child and folds its `passed:` and `failed:` totals into its own. A suite that crashes before printing a total prints no `failed:` line, so the parsed failure count is empty. A plain sum reads that crash as zero failures, which is green.

### Decision

When a suite exits non-zero or reports failures, the loop prints the first `FAIL` lines. If the parsed failure count is empty or zero (the crash case), it adds one to `fail` itself: `[ -n "$_f" ] && [ "$_f" -ne 0 ] || fail=$((fail + 1))`. A suite that reported its own nonzero count keeps that count.

### Consequences

Do not simplify the line to `fail=$((fail + ${_f:-0}))`. A crashing suite would then pass the whole run. A new suite needs only a name in `_suites`; it inherits the rule.

## the suite shards round-robin by position in the file

### Context

The suite is slow because it runs `run.sh` hundreds of times, not because any one test is slow. The slow tests are spread across the file. Measured when the scheme was chosen (four shards): the longest shard held 26% of the run time against an ideal 25%. CI has since moved to eight shards; CLAUDE.md "Sharding (2026-10-20)" has the later numbers.

### Decision

`RUNALL_SHARD=i/n` runs every n-th test and unit suite, counted in the order they appear in the file, so n jobs run the whole suite exactly once between them (`tests/shard.sh` proves it). `RUNALL_LIST=1` prints what a shard would run and runs nothing. Unset, the whole suite runs. `RUNALL_TIMES=<file>` appends `<seconds> <name>` per entry, which is the data a duration-weighted split would need. The shard value is validated strictly (digits, one slash, digits; `10#` so `08` is eight). Anything else exits 2 instead of reading as the whole suite.

### Consequences

Add a new test as a `_run test_name` line, never a direct call, or it runs in every shard. Weight shards by measured duration only if the slow tests stop being spread through the file.
