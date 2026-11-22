# tests-run-all: the upgrade-lag test builds the install the nightly really has, with run.sh symlinked and no libraries

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_upgrade_lag_install_still_produces_a_report`)

## Context

The live install symlinks each script into `~/.claude/autodream` one by one. Merging a branch changes `run.sh` the moment it lands, but `lib-project.sh`, `adapters.sh`, `preflight.sh` and `adapters/` only appear when `install.sh` runs again. Every other test calls `$REPO/bin/run.sh` directly, where the libraries sit beside it. When this test was written, 358 green assertions had all run with the libraries present, and none exercised the shape the nightly has.

## Decision

The fixture installs what a pre-adapter install left behind: the helper scripts that existed then (`prune-self-sessions.sh`, `root-probe.sh`, `slim-transcript.sh`, `session-stats.sh`, `overlap-stats.sh`, `vault-notes.sh`, `x-bookmarks.sh`, `notify.sh`), `run.sh` as a symlink into the repo, and the prompts. It leaves out `lib-project.sh`, `adapters.sh`, `preflight.sh` and `adapters/` on purpose, and `session-window.sh` has no link either. The run must still exit 0 and report `session_window: on` and `l1_chunk_bytes: 300000`, because the runner finds those helpers in the checkout its symlink points into (`find_lib`).

## Consequences

Adding a helper to the fixture's link list, or copying a library into `$T/autodream`, turns this into another direct-invocation test and removes the only coverage of the upgrade window. A new library that `run.sh` needs must be findable through the symlink target, and this test is where that fails first.
