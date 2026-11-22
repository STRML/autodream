# 0035: l1-confine suites: sandbox skips, WAL fixture and the real-engine check

Status: accepted · Date: 2026-11-22 · Code: `tests/l1-confine-real.sh` (config block, `AUTODREAM_WORK_BUCKET`, `protect`), `tests/l1-confine-real.sh` (control shell, `home_writes`, the omp memory-store check), `tests/l1-confine.sh` (the probe-gated real-confinement cases), `tests/l1-confine.sh` (the `omp l1-stage-env` cases)

## the manual check runs under the nightly's own configuration

### Context

The check exists to prove the profile the nightly builds. If it ran with defaults, an `AUTODREAM_L1_WRITES_EXTRA` the operator put in `$AUTODREAM_DIR/config` would be missing, and a PASS would describe a profile no run uses. `docs/adr/0001-runner-lifecycle.md#background-runsh-sources-the-config-now` ("run.sh sources the config now") records the two details of sourcing: `set -a` so keys are exported, and the `export -p` snapshot replayed afterwards so the caller's explicit environment still wins.

### Decision

The script resolves `AUTODREAM_DIR` and `AUTODREAM_CONFIG` as `run.sh` does, sources the config with `set -a`, replays the `export -p` snapshot, and derives the protected paths (`$AUTODREAM_DIR`, findings dir, dreams dir) and the work bucket the same way `run.sh` does. It prints which configuration it used, or that none was found.

### Consequences

A change to how `run.sh` sources the config or builds the protect list needs the same change here, or the check silently verifies a different profile. Removing the snapshot replay would let the file clobber a deliberately exported variable.

## a PASS or FAIL must carry evidence on a shared host

### Context

The check runs against a real engine on a live machine, where other processes write too, and where "the model did not write the forbidden file" may only mean the model did not try.

### Decision

- **Refusal is proven by a control.** The same prefix runs a plain `/bin/sh` that first writes into the stage, then writes beside it. The refusal only counts when the stage write succeeded, so a shell that never started cannot produce a false PASS. A model's second write is reported as "may simply not have tried".
- **Write measurements name only paths the engine owns.** `home_writes` lists the engine's own roots under `$HOME` because other apps write there during the call window; for omp, live sessions also write `agent/sessions` and the shared logs, so the run belongs on a quiet host.
- **A memory-store FAIL needs a rerun before it is read as a leak.** A worker reads untrusted transcripts, and omp retains and consolidates memory at session end into a store every later session recalls from, through a server or daemon that is not the worker. The overlay turns the backend off (`backend: "off"`); the check proves it on the real store, but another live omp session writes the same store, so the FAIL message tells the reader to rerun quietly.

### Consequences

Removing the control shell turns the refusal check into a statement about model behavior. A FAIL on a busy host is a prompt to rerun, not yet a finding.

## the real-confinement cases skip where a sandbox cannot start

### Context

`sandbox-exec` cannot start inside another sandbox (`sandbox_apply: Operation not permitted`), which is how the Claude Code sandbox and some CI runners look to the suite. `docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement` ("A host with no working sandbox says so") records the same constraint for the suite as a whole: `AUTODREAM_L1_CONFINE=0` is exported because the mock engines write anywhere, and the confinement tests turn it back on.

### Decision

The shim cases (no tool on PATH, a tool that rejects the profile, a tool that confines nothing, profile text, refused paths) always run. The cases that need a working sandbox run only when `bin/l1-confine.sh probe` answers `yes`; otherwise they print a skip line instead of failing.

### Consequences

A red result here means the helper is wrong, never that the host cannot sandbox. The cost is that on a host nested in another sandbox the real-confinement assertions never run, so `tests/l1-confine-real.sh` (outside any sandbox) remains the only check of the real engine under the profile.

## the omp `l1-stage-env` fixture is a live WAL database with a log-only row

### Context

`adapters/omp/adapter.sh l1-stage-env` seeds each confined omp worker with a copy of `agent.db` that leaves the OAuth credential rows out (`docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement`, "A host with no working sandbox says so"). A running omp keeps `agent.db` open in WAL mode, so a plain file copy of the main file misses whatever is committed only to the log and can capture a torn state.

### Decision

The fixture builds `agent.db` the way a live omp holds it: `journal_mode=WAL`, `wal_autocheckpoint=0`, an API-key row and an OAuth row, then one more committed row (`deepseek`) that exists only in the log. A python process keeps that connection open for the whole verb. The assertion lists the providers in the copy and expects `neuralwatt,deepseek`, so only a SQLite backup-API snapshot passes; a file copy returns `neuralwatt` alone.

### Consequences

Simplifying the fixture to a closed, checkpointed database makes the assertion pass for a plain `cp` and removes the guard. Keep the holder process alive until the verb returns. The OAuth assertions pair with it: the worker copy holds zero OAuth rows and the real database still holds one.
