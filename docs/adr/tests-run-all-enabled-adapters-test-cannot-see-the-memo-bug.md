# tests-run-all: the enabled-adapters test pins the warning, not the subshell-memo bug it was written for

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_enabled_adapters_resolves_once`)

## Context

The first attempt at resolving the adapter set once was a memoised `enabled_adapters` that every caller invoked as `$(enabled_adapters)`. The cache assignment died with the subshell, so the loader re-ran on every call. This is the trap the `adapters.sh` header documents.

The test asserts the "is accepted but not enabled" warning appears exactly once. That does not discriminate against the subshell bug. Checked by restoring the broken memo and re-running: the test still passed. The bug is a repeated invocation, and the second invocation happens on a path whose warning does not reach the log again, so no assertion over log content can see it. A test cannot instrument a script it invokes rather than sources.

## Decision

- The test stays because a multiplying warning is worth pinning on its own.
- The subshell bug was measured by hand with the function instrumented: 2 invocations before the fix, 1 after.

## Consequences

Passing this test is not evidence that the adapter set is resolved once. A regression to the `$(...)` memo needs an instrumented check (source `adapters.sh` and count loader runs), not another log assertion.
