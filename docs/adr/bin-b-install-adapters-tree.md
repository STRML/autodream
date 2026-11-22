# bin-b: install.sh links the adapters tree whole and restores each adapter's exec bit

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the `adapters` link and the `chmod +x`)

## Context

`run.sh` resolves `adapters/<name>/adapter.sh` relative to its own directory, so the whole tree has to be reachable from the install target. Without the link the installed runner silently takes the legacy inline enumeration path, gets no preflight, and still reports `adapters_enabled`.

`_adapter_ok` requires `-x` on `adapter.sh`, and the loader treats a non-executable adapter as a refusal, not as "adapters absent". A distribution path that loses the exec bit (a zip, a restrictive umask) therefore becomes a hard FATAL nightly with no report.

## Decision

The installer links the directory `adapters/`, not individual files, and runs `chmod +x adapters/*/adapter.sh` next to the `bin/*.sh` chmod.

## Consequences

A new per-adapter file needs no installer change. A new adapter entry point that must be executable needs its own chmod here.
