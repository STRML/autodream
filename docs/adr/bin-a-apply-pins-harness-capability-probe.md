# bin-a: a pin tagged with a harness is stored only when the installed shared-memory proves it filters on the tag

Status: accepted · Date: 2026-11-21 · Code: `bin/apply-pins.sh` (`GATE_OK` probe, `apply_line`)

## Context

A pin may carry `harness` (`claude`, `omp` or `codex`), stored as `metadata.harness`. The tag is safe only when the installed `shared-memory` filters on it at startup. Without that filter the pin would load into every harness.

A bare `--host` fails closed in a `shared-memory` built with the harness gate (agent-mnemopi PR 12) and is ignored by an older one, so the error text tells the two apart without storing anything.

## Decision

Before the pin loop, the script runs `shared-memory startup --host` with stdin from `/dev/null` and sets `GATE_OK=1` only when the output contains `--host needs a harness name`. When `GATE_OK` is not 1, a pin with a `harness` field is held, counted as `unsupported_harness`, and not stored. Pins without a harness are unaffected.

## Consequences

If agent-mnemopi changes that error text, the probe reads every installation as the old build and holds every tagged pin. The `pins_unsupported_harness` counter in `pins-result.txt` is where that shows. Change the probe and the CLI together.
