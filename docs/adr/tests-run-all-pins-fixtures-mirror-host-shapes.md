# tests-run-all: pin and rollup fixtures reproduce the bucket and cwd shapes the host really has

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`mk_session_with_cwd`, `test_rollup_marks_trig_sandbox_sessions`, `test_pins_custom_slug_bucket_keeps_its_cwd`, `test_pins_unresolvable_cwd_still_counts_toward_a_collision`, `test_pins_bucket_named_subagents_is_a_project`)

## Context

The pin tests cover rows R1-R11 of the failure matrix in `docs/plans/2026-09-15-mnemopi-pins.md`; `tests/apply-pins.sh` holds the rows of `apply-pins.sh` itself. `run.sh` refuses a session whose cwd does not encode to the bucket it is stored in, and a fixture that breaks that rule tests the refusal instead of the case it names. Several real shapes decide the outcome, and each has a measured size.

## Decision

- Sessions go in the bucket Claude would use for their cwd. `lib-project.sh` (`encode_project`) is the one encoder, so fixtures call it and carry no second copy of the rule.
- A skill-creator trigger eval runs `claude -p` from `/private/var/folders/<x>/<y>/T/trig-<id>/repo` and deletes the directory afterwards. The runner cannot resolve that cwd, so the bucket key decides the `sandbox` column (CLAUDE.md, "Session roots" and the rollup notes). The look-alike `/Users/x/T/trig-parser` checkout must stay `no`.
- Slug buckets (`owner-repo`, set through `CLAUDE_CODE_PROJECT_DIR_NAME`) override cwd encoding, so no cwd ever encodes to them. On this host they are the main Rush and STRML repos: 68 of 359 buckets in `~/.claude`.
- A removed worktree gives a session whose cwd the adapter can no longer resolve (`rmdir` in the fixture). That was true of 8 of the 48 sessions on 2026-09-14.
- Claude Code writes workflow agents one level deeper than plain subagents: `<bucket>/<session>/subagents/workflows/wf_<id>/agent-*.jsonl` (65 such files on this host). A bucket may also be named `subagents`. The project is the directory directly under the session root, whatever it is called.

## Consequences

Replacing a fixture's cwd or bucket with a convenient literal can make the bucket check pass or fail for the wrong reason. Check that the fixture still encodes the way the row says before editing it.
