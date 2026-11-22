# tests-run-all: the install test proves the adapter runtime is linked and runs through the symlink

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_install_deploys_the_adapter_runtime`)

## Context

`install.sh` has an explicit link list. The first version of the adapter change added four runtime files and none of them to that list, so every documented nightly install silently took the legacy enumeration path with no preflight, while still printing `adapters_enabled: claude`. It shipped broken to the only place that matters and reported success.

The installed tree is flat: `adapters/` sits beside `adapters.sh` rather than one level up. An adapter finds its helper scripts through a relative path (the omp adapter keeps `linearize.sh` and `stats.sh` beside itself), so resolving an adapter proves nothing about running it.

## Decision

- The test runs `install.sh --no-schedule` into a scratch HOME and asserts each runtime file exists there.
- It then goes beyond discovery: the installed runner resolves the adapters through the flat layout, and a subcommand that shells out to a helper (`stats`, `normalize`, `project`) runs through the installed symlink, for both claude and omp.
- `install.sh` runs `chmod +x "$REPO_DIR/bin/"*.sh`, so the test makes every bin script executable in the working tree. That is the repo's convention and is kept. A `git stash` taken across a suite run can refuse to pop on the bare mode change; `git checkout -- bin/` restores it.

## Consequences

A new runtime file must be added to the link list and to this test's assertions. Do not trim the test to file-exists checks: the failure it exists for passes those and fails at run time. CLAUDE.md, "Where state lives" and the plist PATH section, describe the install layout.
