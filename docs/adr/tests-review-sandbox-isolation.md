# tests-review: review.sh tests run in a sandbox that cannot reach the host's cmux, config, install dir or PATH tools

Status: accepted · Date: 2026-11-22 · Code: `tests/review-cmux.sh` (`setup_env`, `run_review`, `cmux_calls`, `test_interactive_missing_cmux_falls_back_inline`, `test_missing_shasum_fails_closed`), `tests/review-skip.sh` (`run_review`)

## Context

`bin/review.sh` reads the host's `$AUTODREAM_DIR/config`, which on this host sets `AUTODREAM_TRIAGE_SURFACE=cmux`. A leaked config makes a skip test spawn a real cmux workspace. With `AUTODREAM_DIR` unset, the script derives it from `$0` and falls to the real `~/.claude/autodream`, so the cmux dedup claim lands in the host's install dir.

## Decision

- Both suites set `AUTODREAM_CONFIG` to a nonexistent path. `review-cmux.sh` also sets `AUTODREAM_DIR` to the sandbox and sets the surface explicitly.
- The cmux suite fakes both cmux and claude. The preflight requires `CLAUDE_BIN` to exist before it launches a workspace, and in cmux mode the script never executes it. A CI runner has no `~/.local/bin/claude`, so the suite makes its own.
- `cmux_calls` counts only `^workspace create ` lines. The detached rename loop (three `sleep 3` rounds of `tab-action`) can write to the log long after the create returns, so a raw `wc -l` is flaky. The count ends in `|| true`: `grep -c` on an empty log prints 0 and exits 1, so `|| echo 0` would print two zeros.
- The interactive-fallback test runs under `tests/with-pty.py`, not BSD `script`. `script` calls `tcgetattr` on its own stdin and fails with "Operation not supported on socket" when the suite starts from something that hands it a socket, which made the test fail only through `run-all.sh`.
- The missing-shasum test puts a stub `shasum` that exits 127 first on PATH. On Linux `/bin` is `/usr/bin`, so a PATH that leaves `/usr/bin` out cannot hide the real one.

## Consequences

A new review.sh test that builds its own environment must repeat the config pin. `with-pty.py` needs `python3`.
