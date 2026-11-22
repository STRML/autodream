# tests-run-all: the harness pins every piece of host state out of a run

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (top-level exports, `setup_env`, `mk_session`, `run_dream`, `remove_path`)

## Context

`run.sh` reads the developer's real environment: `~/.local/bin` on PATH (where the real `shared-memory` CLI lives), `~/.claude/autodream/config`, a real `curl`, a real remote-root list, the changelog remotes. Each has reached, or could reach, something real. A developer whose config points `AUTODREAM_VAULT_DIR` at a live Obsidian vault would have the suite writing notes and reports into it. A test whose L2 emits pins would store them in the real Mnemopi. A failing worker probes the network with `curl` at 5 seconds a call.

## Decision

- `SHARED_MEMORY_BIN` points at a path that does not exist. Pin tests override it with `tests/mock-shared-memory.sh`.
- `AUTODREAM_L1_CONFINE=0`: the mock engines write capture files anywhere, so the suite runs L1 unconfined (#169). The confinement tests turn it on.
- `AUTODREAM_REMOTE_ROOTS` is unset. The remote_sync tests set it themselves.
- `run_dream` defaults the changelog check off (the changelog test exports `AUTODREAM_CHANGELOG=1` with a local remote), forces the retry and network knobs fast and offline, and pins `AUTODREAM_CONFIG` into the sandbox. It also puts a `curl` shim that reports a reachable host first on PATH. Tests that care about an outage set `TEST_CURL_SHIMMED=1` and bring their own shim.
- `THREADS_TEST_TIMEOUT_BIN` falls back from `timeout` to `gtimeout`. GitHub's macOS image has no `/usr/bin/timeout`, and only Homebrew coreutils provides one (#221).
- `remove_path` deletes through python3, because `/usr/bin/trash` exists only on macOS and CI runs Linux.
- `mk_session` writes two real user turns with no timestamps. `duration_minutes` 0 is uncomputable and exempt from the duration rule, so the fixture clears the noise gate's default `AUTODREAM_MIN_USER_TURNS=2` floor and every test that expects real L1 triage keeps getting it.
- An unattended run logs to its file and stdout carries only a pointer, so `run_dream` appends the run log to `run.out`. Assertions then read what a nightly run recorded, not what a tty run echoes.

## Consequences

A new run-time knob that reaches outside the sandbox needs a pin here. Raising the noise-gate floor means `mk_session` must grow a turn.
