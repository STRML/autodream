# 0047: run-all: retry, network, timeout and L2 tests prove effects, not exit codes

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_l1_hang_is_bounded`, `test_intrinsic_124_is_not_a_timeout`, `test_l1_timeout_must_be_positive`, `test_l1_warmup_timeout_must_be_positive`), `tests/run-all.sh` (`test_warmup_empty_stdout_is_a_failure_not_ok`, `test_warmup_works_for_an_adapter_with_no_environment`, `test_breaker_needs_two_barren_rounds_not_one`, `test_a_deterministic_failure_trips_the_breaker`), `tests/run-all.sh` (`test_wait_for_network_cap_bounds_the_probe`, `test_route_lost_after_the_precheck_still_defers`, `test_provider_refusal_defers_without_a_stub`, `test_provider_402_and_missing_curl_still_defer`, `test_missing_curl_is_not_read_as_an_outage`, `test_no_curl_does_not_defer_a_healthy_run`, `test_unexecutable_curl_is_not_read_as_an_outage`, `test_a_transient_outage_is_ridden_out_not_deferred`), `tests/run-all.sh` (`test_l2_uses_the_default_model`, `test_l2_model_pin_is_honoured`), `tests/run-all.sh` (`test_facet_fields_plumbed`), `tests/run-all.sh` (`test_l2_diag_written_on_exit_143`, `test_l2_diag_probes_never_fail_or_stall_the_run`, `test_l2_diag_long_command_lines_keep_the_sections_intact`), `tests/run-all.sh` (`test_rollup_written_for_l2`, `test_sandbox_shape_denies_reach_the_rollup`)

## the L1 timeout tests prove the effect (group reaped, elapsed time, zero refused), not an exit code

### Context

The 2026-08-19 and 2026-08-22 runs each sat for days with every `xargs -P` slot held by a worker that never exited. No error, no report, and launchd would not start a replacement while the label was still running, so the catch-up triggers were suppressed too.

- A kill aimed at the worker alone leaves its children alive and reparented to init; 57 `node_repl` and `mnemopi_embed` orphans accumulated on the real host that way. `kill -0` also succeeds on a zombie, and a child whose parent just died is one until init reaps it, so one immediate check fails a correct kill on timing alone.
- GNU `timeout` propagates the child's exit status, so a worker that exits 124 by itself, or is SIGKILLed by the OOM killer, looks identical to a fired deadline. Only elapsed time separates them, and it must be measured from the launch of `timeout`, not the top of the worker, or preprocessing time closes the gap on a short bound.
- GNU `timeout` reads 0 as "no timeout", so an unvalidated 0 restores the wedge while the startup log still claims a bound.

### Decision

- The hang test records the mock child's pid, then gives each pid a bounded grace (10 x 0.5 s) before counting it leaked.
- The intrinsic-124 test uses a 900 s bound and asserts `l1_timed_out: 0` and no timeout line in the `.err`.
- Zero and non-numeric values for `AUTODREAM_L1_TIMEOUT` and `AUTODREAM_L1_WARMUP_TIMEOUT` are refused at startup and no report is written.

### Consequences

Replacing the grace loop with a single `kill -0` makes the hang test flaky. Asserting only the exit status cannot tell a real deadline from an intrinsic 124. See docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09 "A hung worker, a cold token and a deterministic failure".

## the warmup and breaker tests drive the exact shapes the first versions got wrong

### Context

- A warmup that captured `2>&1` saw omp's `Working...` stderr chatter as a non-empty reply and recorded `l1_warmup: ok` for exactly the exit-0, empty-stdout failure it exists to expose. `MOCK_MODE=l1_incomplete` writes nothing to stdout, which is why it is the fixture.
- run.sh runs under `/bin/bash` 3.2 with `set -u`, where expanding an empty array is an unbound-variable error. An adapter whose `l1-env` prints nothing (omp's) aborted the warmup pipeline before `timeout` started, recorded `l1_warmup: failed` and blamed the provider. The test copies the claude adapter and rewrites its `l1-env` to print nothing.
- The first breaker compared each round's ending missing count with the previous round's, so round 2 alone (2 == 2) tripped it and logged that rounds 1 and 2 both recovered nothing, although round 1 recovered one session. The breaker is a streak of two barren rounds, so the earliest honest trip is round 3.
- The 2026-09-05 through 2026-09-10 shape: every round failed identically, five rounds bought sixteen empty stubs, and the stats read as a healthy retry loop.

### Decision

`MOCK_MODE=l1_partial_then_stall` recovers exactly one of three sessions in round 1 and none after; the test asserts round 3 still runs. `l1_incomplete` with five rounds asserts the breaker fires, rounds 3 and 4 do not dispatch, and the stub round still writes the stub: without it the slot stays empty and the deferral logic reads a dead worker as a dead network.

### Consequences

Do not substitute a fixture that recovers zero or all sessions in round 1: the false-trip case disappears. Do not run the empty-env test under a newer bash, where an empty array expands to nothing. See docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09 "A hung worker, a cold token and a deterministic failure".

## the network deferral tests pin when a failure must defer without a stub and when it must not defer at all

### Context

A deferral is only correct if the slot stays empty. A findings stub carries `.findings`, and `jq -e` counts an empty array as present, so writing one marks the session done: the missing count hits zero, the run stops deferring, L2 publishes an empty report, and every later run skips the session because its slot is filled. That applies to a route lost after the pre-dispatch check (the round-5 shape from 2026-09-04, hence `AUTODREAM_NETCHECK=0` in the fixture: the pre-check only proves the route was up when the round started) and to a provider refusal on a reachable network (the provider carve-out).

The opposite failures also happened. A curl that cannot run (127 missing, 126 not executable) answers nothing, so reading it as an outage would defer every date forever on a host without curl; `net_up` ran curl unconditionally and looped to the full cap until it grew the `command -v` guard the worker-failure path already had. The first version of the outage fix broke out of the retry loop on any network-flavoured failure, so one transient DNS timeout deferred the date for three hours instead of succeeding in round 2. Some shells skip a non-executable PATH entry and run the next curl, so the 126 shim is an executable script that returns 126 directly.

### Decision

Fixtures use a tiny `AUTODREAM_NETCHECK_CAP` (a missing guard then defers fast) and `TEST_CURL_SHIMMED=1` shims on PATH. The cap test clamps probes to the cap: with six dead hosts against a 2 s cap, a loop that keeps probing after the cap runs about 2 s plus 5 x 1 s, one that stops runs about 2 s, and the 4 s ceiling sits between them by more than the 1 s granularity of `date +%s`.

### Consequences

Do not move the ceiling to the single-host bound or tighten it to 2 s. Do not replace the 126 shim with a `chmod -x` file. See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37 "A dead network or a refusing provider defers the date".

## the L2 default-model test asserts the absence of `--model` in the captured argv

### Context

L2 was pinned to `claude-opus-4-7` by a date cutoff whose other branch had been unreachable since 2026-06-21. The nightly quietly aggregated on a model two generations old and nothing said so. A comment or a doc line claiming "no `--model`" is not a check; only the argv the mock records is.

The `claude` CLI also falls back silently on an unrecognised model id, so a run that asked for a bad model reads the same as one that asked for a good one.

### Decision

- `test_l2_uses_the_default_model` captures the real L2 argv (`MOCK_CAPTURE_DIR/l2-args.txt`) and fails if a `--model` line is present.
- It also asserts `--print` is in that argv. Absence of `--model` is satisfied by a run that never reached claude, so the call must be shown well-formed.
- `test_l2_model_pin_is_honoured` asserts the pin puts `--model` and its value back, and that `run-stats.txt` records `l2_model`, because the artifact is the only place that says what was asked for.

### Consequences

Do not weaken the negative assertion to a grep on a log line, and do not drop the `--print` check. A new L2 engine that adds its own default flag set must keep the same capture-based form. docs/adr/0003-adapters-and-engines.md#background-which-engine-runs-l2 ("Which engine runs L2") records `l2_model: default` when none is named.

## findings-plumbing tests stop at the findings JSON because the L2 mock ignores its content

### Context

`tests/mock-claude.sh` plays L2 without reading the findings it is given. A report landing therefore says nothing about whether L2 understood the facet fields.

### Decision

`test_facet_fields_plumbed` asserts on the findings JSON that L2 reads (outcome, satisfaction signals, `underlying_goal`, `instructions_given`) and on the report existing. It makes no claim about what L2 did with them. Behavioral quality is judged on real runs.

### Consequences

Do not add assertions about report content here; the mock cannot satisfy them. Read "L2 run completed" as plumbing only.

## the L2 diag tests come from a recurring exit-143 incident and use probe shims shaped to the real hazards

### Context

Exit 143 on the L2 aggregator was seen on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02, with nothing in the log to say who sent the TERM (issue 42). A 143, 137 or 124 now writes `findings/<date>/l2-attempt-N.diag`. The probes behind it must never fail or stall the run.

- `AUTODREAM_LAUNCHD_LABEL` is set in the probe test because macOS resets `XPC_SERVICE_NAME` to `0` in a child process. Without it the label is empty and the per-label `launchctl` probe, the one the test makes hang, never runs. `run.sh` reads `${AUTODREAM_LAUNCHD_LABEL:-${XPC_SERVICE_NAME:-}}`.
- A real claude launch carries a very long argv. The `ps` shim answers with one 9000-byte line and no trailing newline, which is what lets a long line swallow the next section's heading.

### Decision

The probe test shims `launchctl` to hang and `ps`, `uptime`, `vm_stat`, `sysctl` and `pmset` to fail, and sets the label override so the hanging probe runs. The long-line test shims `ps` with the 9000-byte line without a newline.

### Consequences

If the label override is removed, the hung-probe assertion passes without exercising the hang. Adding a newline to the `ps` shim removes the case the test exists for.

## the roll-up and sandbox-shape tests pin counts the runner computes, because L2 cannot count

### Context

- On 2026-10-31 L2's Glob and directory reads stopped at 200 entries. The findings dir held 2683 entries and the report counted a sample (docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives", `rollup.tsv`).
- #175 stopped L1 scoring sandbox-shape denies as `sandbox_friction`. A session that hit the deny 124 times then became invisible (2026-11-03).

### Decision

- `rollup.sh` writes `rollup.tsv`, `categories.tsv` and `findings.tsv` before L2, and L2 counts from them. `test_rollup_written_for_l2` uses the fanout fixture: 2 ungated top-level sessions, 1 gated and 5 ungated workers, so 8 rows and 7 ungated.
- The runner counts `sandbox_shape_denies` from the transcript and puts the threshold in `run-stats.txt`. The test builds a session with 12 denies and one with none, and asserts the second reads a measured 0, not blank.

### Consequences

The expected row counts are tied to the fanout fixture; change one with the other. Moving a count back into the prompt returns to the sample-based tally this change replaced.
