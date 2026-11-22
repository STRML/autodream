# rest: one global EXIT cleanup for the scratch files, naming globals and never a function's locals

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`cleanup`, `TMP`, `LIVE`, `cmd_last`)

## Context

An EXIT trap that names a function's `local` runs after the function has returned. Under `set -u` the reference is then a fatal error that aborts the trap before the rest of it runs. It also exits before the lock is released, which wedges every later tag. The first version hit this (CLAUDE.md, "The focus mod").

`last --harness omp` makes a 0600 copy of the linearized transcript, which is the person's conversation, and it has to go whichever later step ends the script.

## Decision

`TMP` (the take-back temp file) and `LIVE` (the linearized transcript copy) are globals, empty until set, and `cleanup` removes whichever is non-empty. It is registered once with `trap cleanup EXIT`.

## Consequences

A new scratch file gets a global and a line in `cleanup`. Never register an EXIT trap that names a local.
