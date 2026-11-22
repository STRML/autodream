# tests-l1-confine-real: a PASS or FAIL must carry evidence on a shared host

Status: accepted · Date: 2026-11-22 · Code: `tests/l1-confine-real.sh` (control shell, `home_writes`, the omp memory-store check)

## Context

The check runs against a real engine on a live machine, where other processes write too, and where "the model did not write the forbidden file" may only mean the model did not try.

## Decision

- **Refusal is proven by a control.** The same prefix runs a plain `/bin/sh` that first writes into the stage, then writes beside it. The refusal only counts when the stage write succeeded, so a shell that never started cannot produce a false PASS. A model's second write is reported as "may simply not have tried".
- **Write measurements name only paths the engine owns.** `home_writes` lists the engine's own roots under `$HOME` because other apps write there during the call window; for omp, live sessions also write `agent/sessions` and the shared logs, so the run belongs on a quiet host.
- **A memory-store FAIL needs a rerun before it is read as a leak.** A worker reads untrusted transcripts, and omp retains and consolidates memory at session end into a store every later session recalls from, through a server or daemon that is not the worker. The overlay turns the backend off (`backend: "off"`); the check proves it on the real store, but another live omp session writes the same store, so the FAIL message tells the reader to rerun quietly.

## Consequences

Removing the control shell turns the refusal check into a statement about model behavior. A FAIL on a busy host is a prompt to rerun, not yet a finding.
