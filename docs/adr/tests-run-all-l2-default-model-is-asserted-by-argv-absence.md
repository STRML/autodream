# tests-run-all: the L2 default-model test asserts the absence of `--model` in the captured argv

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_l2_uses_the_default_model`, `test_l2_model_pin_is_honoured`)

## Context

L2 was pinned to `claude-opus-4-7` by a date cutoff whose other branch had been unreachable since 2026-06-21. The nightly quietly aggregated on a model two generations old and nothing said so. A comment or a doc line claiming "no `--model`" is not a check; only the argv the mock records is.

The `claude` CLI also falls back silently on an unrecognised model id, so a run that asked for a bad model reads the same as one that asked for a good one.

## Decision

- `test_l2_uses_the_default_model` captures the real L2 argv (`MOCK_CAPTURE_DIR/l2-args.txt`) and fails if a `--model` line is present.
- It also asserts `--print` is in that argv. Absence of `--model` is satisfied by a run that never reached claude, so the call must be shown well-formed.
- `test_l2_model_pin_is_honoured` asserts the pin puts `--model` and its value back, and that `run-stats.txt` records `l2_model`, because the artifact is the only place that says what was asked for.

## Consequences

Do not weaken the negative assertion to a grep on a log line, and do not drop the `--print` check. A new L2 engine that adds its own default flag set must keep the same capture-based form. CLAUDE.md ("Which engine runs L2") records `l2_model: default` when none is named.
