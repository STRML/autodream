# tests: run-all-install-and-adapter-fixtures: run-all: install, upgrade and adapter-enablement fixtures

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_install_deploys_the_adapter_runtime`), `tests/run-all.sh` (`test_upgrade_lag_install_still_produces_a_report`), `tests/run-all.sh` (`test_enabled_adapters_resolves_once`), `tests/run-all.sh` (`test_normalize_project_survives_non_object_findings`), `bin/run.sh` (the `SESSION_ROWS=... python3 -` heredoc)

## the install test proves the adapter runtime is linked and runs through the symlink

### Context

`install.sh` has an explicit link list. The first version of the adapter change added four runtime files and none of them to that list, so every documented nightly install silently took the legacy enumeration path with no preflight, while still printing `adapters_enabled: claude`. It shipped broken to the only place that matters and reported success.

The installed tree is flat: `adapters/` sits beside `adapters.sh` rather than one level up. An adapter finds its helper scripts through a relative path (the omp adapter keeps `linearize.sh` and `stats.sh` beside itself), so resolving an adapter proves nothing about running it.

### Decision

- The test runs `install.sh --no-schedule` into a scratch HOME and asserts each runtime file exists there.
- It then goes beyond discovery: the installed runner resolves the adapters through the flat layout, and a subcommand that shells out to a helper (`stats`, `normalize`, `project`) runs through the installed symlink, for both claude and omp.
- `install.sh` runs `chmod +x "$REPO_DIR/bin/"*.sh`, so the test makes every bin script executable in the working tree. That is the repo's convention and is kept. A `git stash` taken across a suite run can refuse to pop on the bare mode change; `git checkout -- bin/` restores it.

### Consequences

A new runtime file must be added to the link list and to this test's assertions. Do not trim the test to file-exists checks: the failure it exists for passes those and fails at run time. CLAUDE.md, "Where state lives" and the plist PATH section, describe the install layout.

## the upgrade-lag test builds the install the nightly really has, with run.sh symlinked and no libraries

### Context

The live install symlinks each script into `~/.claude/autodream` one by one. Merging a branch changes `run.sh` the moment it lands, but `lib-project.sh`, `adapters.sh`, `preflight.sh` and `adapters/` only appear when `install.sh` runs again. Every other test calls `$REPO/bin/run.sh` directly, where the libraries sit beside it. When this test was written, 358 green assertions had all run with the libraries present, and none exercised the shape the nightly has.

### Decision

The fixture installs what a pre-adapter install left behind: the helper scripts that existed then (`prune-self-sessions.sh`, `root-probe.sh`, `slim-transcript.sh`, `session-stats.sh`, `overlap-stats.sh`, `vault-notes.sh`, `x-bookmarks.sh`, `notify.sh`), `run.sh` as a symlink into the repo, and the prompts. It leaves out `lib-project.sh`, `adapters.sh`, `preflight.sh` and `adapters/` on purpose, and `session-window.sh` has no link either. The run must still exit 0 and report `session_window: on` and `l1_chunk_bytes: 300000`, because the runner finds those helpers in the checkout its symlink points into (`find_lib`).

### Consequences

Adding a helper to the fixture's link list, or copying a library into `$T/autodream`, turns this into another direct-invocation test and removes the only coverage of the upgrade window. A new library that `run.sh` needs must be findable through the symlink target, and this test is where that fails first.

## the enabled-adapters test pins the warning, not the subshell-memo bug it was written for

### Context

The first attempt at resolving the adapter set once was a memoised `enabled_adapters` that every caller invoked as `$(enabled_adapters)`. The cache assignment died with the subshell, so the loader re-ran on every call. This is the trap the `adapters.sh` header documents.

The test asserts the "is accepted but not enabled" warning appears exactly once. That does not discriminate against the subshell bug. Checked by restoring the broken memo and re-running: the test still passed. The bug is a repeated invocation, and the second invocation happens on a path whose warning does not reach the log again, so no assertion over log content can see it. A test cannot instrument a script it invokes rather than sources.

### Decision

- The test stays because a multiplying warning is worth pinning on its own.
- The subshell bug was measured by hand with the function instrumented: 2 invocations before the fix, 1 after.

### Consequences

Passing this test is not evidence that the adapter set is resolved once. A regression to the `$(...)` memo needs an instrumented check (source `adapters.sh` and count loader runs), not another log assertion.

## the project-normalization pass is cut out of run.sh and run alone

### Context

`run.sh` validates findings JSONs before the normalization pass, so a full run never hands the pass a non-object. A full-run test would pass even if the pass crashed on `[]` or `null`.

### Decision

The test extracts the pass's Python body from `run.sh` with an `awk` range (from the `SESSION_ROWS="$SESSION_ROWS" python3 -` line to the closing `PY`), asserts the extract is non-empty, and runs it on four files: an array, `null`, a string and an object with a wrong project. The file names sort `a.json < b.json < c.json < d.json`, and the pass walks them in that order. That puts the object last, so exit 0 and a corrected project on `d.json` show that the non-objects did not stop the rest.

### Consequences

Renaming the heredoc's opening line breaks the extraction, and the non-empty assertion says so. Renaming the fixtures so the object sorts first lets a pass that aborts on the first non-object go unnoticed.
