# 0039: review.sh suites: isolation, skip fixtures, cmux marker and the questions-only prompt

Status: accepted · Date: 2026-11-22 · Code: `tests/review-cmux.sh` (`test_force_bypasses_marker`, `test_confirmed_marker_survives_grace`, `test_missing_claude_preflights`, `test_missing_shasum_fails_closed`, `test_empty_ref_still_confirms`), `bin/review.sh`, `tests/review-prompt.sh` (`mk_report`, `test_block_content_is_inlined_findings_not`, `test_markdown_inside_the_block_is_text`), `tests/review-cmux.sh` (`setup_env`, `run_review`, `cmux_calls`, `test_interactive_missing_cmux_falls_back_inline`, `test_missing_shasum_fails_closed`), `tests/review-skip.sh` (`run_review`), `tests/review-skip.sh` (`REPORT_STUB_TRIAGED`, `REPORT_TRIAGED_NUMBERED`, `test_latest_report_default`)

## the dedup token is written when cmux exits 0, and nothing else can override it

### Context

The scheduled review job fires several times a day, and a second workspace for the same report is the failure to prevent. `review.sh` keeps two markers under `$LOGS_DIR`:

- the claim dir `review-launched-$DATE-$DIGEST`, made with an atomic `mkdir`;
- the sibling token `review-launched-$DATE-$DIGEST.confirmed`, written only after cmux returns success.

Dedup keys on the token. An unconfirmed claim older than the 900 second grace is an abandoned launch and gets reclaimed. A review round found that gating the token write on having claimed the dir left a first `--force` run without a token, so the next scheduled trigger opened a duplicate.

### Decision

- `--force` stamps its own token on a first-ever run, and that token dedups the next routine trigger.
- cmux exit 0 is the creation contract. The token is written even when the stdout ref does not parse. A kill between create and confirm, or a change in cmux's output format, must never let the age-based reclaim open a duplicate. An empty ref costs only the cosmetic tab rename.
- A workspace whose embedded claude cannot start is a dead end that the token would then dedup forever. The script preflights the exact `CLAUDE_BIN` path it passes into the workspace and writes no token when it is missing.
- The digest comes from `shasum`. If `shasum` is missing the script exits non-zero instead of falling back to a seconds-resolution mtime, which reintroduces same-second collision dedup bugs.
- `test_confirmed_marker_survives_grace` ages the pair by two days: past the 900 second grace, under the 14 day prune. A naive reclaim would misfire there, and the unconditional 14 day reap does not delete the fixture. Aging past 14 days would pass the test for the wrong reason.

### Consequences

Keep the fixture ages between 900 seconds and 14 days. The abandoned-claim test uses the same window.

## the triage session gets the questions block only, and the fixtures prove the body stays out

### Context

`review.sh` used to pass the whole report through `--append-system-prompt`. On 2026-10-27 that refused every launch. The 2026-10-26 report narrated a night of Samsung TV work (`sdb`, root status, `dlopen`), and the Opus 5.5 classifiers answered "safeguards flagged this session ... [cyber]" before the first reply, on the literal prompt `go`. The questions section (about 2 KB of decision text) passes and the findings body does not. docs/adr/0022-review-and-triage.md#background-the-triage-prompt-is-questions-only-and-that-is-load-bearing, "The triage prompt is questions-only", records the rules that followed.

### Decision

- `mk_report` puts the string `FINDINGS-SENTINEL` only in the report body. `assert_nogrep` on it proves the body was not inlined. A sentinel that also appeared in the questions block would make that assertion meaningless.
- `test_markdown_inside_the_block_is_text` puts a fenced block and a plain `## ` heading inside the questions block, with `AFTER-EXAMPLES` text after them. Under the old heading-to-next-heading read these ended the section. Under the sentinel contract they cannot, so the test fails if a markdown parse returns.

### Consequences

Keep the sentinel out of the block and the headings inside it. The mock claude records argv positions (`arg4` is the system prompt, `arg5` the launch prompt, `arg7` the model), so adding a flag to the launch shifts them.

## review.sh tests run in a sandbox that cannot reach the host's cmux, config, install dir or PATH tools

### Context

`bin/review.sh` reads the host's `$AUTODREAM_DIR/config`, which on this host sets `AUTODREAM_TRIAGE_SURFACE=cmux`. A leaked config makes a skip test spawn a real cmux workspace. With `AUTODREAM_DIR` unset, the script derives it from `$0` and falls to the real `~/.claude/autodream`, so the cmux dedup claim lands in the host's install dir.

### Decision

- Both suites set `AUTODREAM_CONFIG` to a nonexistent path. `review-cmux.sh` also sets `AUTODREAM_DIR` to the sandbox and sets the surface explicitly.
- The cmux suite fakes both cmux and claude. The preflight requires `CLAUDE_BIN` to exist before it launches a workspace, and in cmux mode the script never executes it. A CI runner has no `~/.local/bin/claude`, so the suite makes its own.
- `cmux_calls` counts only `^workspace create ` lines. The detached rename loop (three `sleep 3` rounds of `tab-action`) can write to the log long after the create returns, so a raw `wc -l` is flaky. The count ends in `|| true`: `grep -c` on an empty log prints 0 and exits 1, so `|| echo 0` would print two zeros.
- The interactive-fallback test runs under `tests/with-pty.py`, not BSD `script`. `script` calls `tcgetattr` on its own stdin and fails with "Operation not supported on socket" when the suite starts from something that hands it a socket, which made the test fail only through `run-all.sh`.
- The missing-shasum test puts a stub `shasum` that exits 127 first on PATH. On Linux `/bin` is `/usr/bin`, so a PATH that leaves `/usr/bin` out cannot hide the real one.

### Consequences

A new review.sh test that builds its own environment must repeat the config pin. `with-pty.py` needs `python3`.

## fixtures copy real report shapes, and the latest-report test sets both mtimes

### Context

`review.sh` decides skip or launch from the report text. Two fixtures exist because real reports took shapes the first version did not handle:

- the 2026-06-27 report was an empty day that someone had already closed out, so two skip reasons applied;
- the 2026-07-09 report used a dated heading (`## Triage decisions (2020-01-03)` in the fixture) and a numbered decision list.

`review.sh` picks the newest report with `ls -t`. Two files written in the same instant tie, and BSD `ls` then breaks the tie by name.

### Decision

- `REPORT_STUB_TRIAGED` matches both the empty-day stub and the triaged rules. The test asserts that "already triaged" is the reason printed, with "decision" in the singular for one entry.
- `REPORT_TRIAGED_NUMBERED` keeps the dated heading and the numbered list. The notice must count 3 decisions.
- `test_latest_report_default` stamps both report files with `touch -t`. Writing them in order is not enough, because the tie would pick the wrong report on BSD `ls`.

### Consequences

Do not simplify these fixtures to the plain `## Triage decisions` shape, and do not drop the `touch -t` calls.
