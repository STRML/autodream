# tests-run-all: the suite runs L1 unconfined, and the confinement fixtures use a fake sandbox-exec and patched adapter copies

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`l1_confine_real`, `fake_sandbox`, `test_l1_forged_writes_are_refused_when_confined`, `test_l1_worker_setup_failure_defers_the_date_and_follows_no_planted_link`, `test_l1_confine_setup_stops_when_a_protected_directory_cannot_be_listed`)

## Context

The mock engines write capture files wherever they like, so the suite exports `AUTODREAM_L1_CONFINE=0` (CLAUDE.md, "What the sandbox allows"). The answer still goes through a staging directory and the runner's copy (#169), which the confinement tests pin. A real `sandbox-exec` cannot start inside another sandbox, which is where the suite often runs.

## Decision

- Tests that need a real sandbox run only when `l1_confine_real` says the probe passes, and print a skip line otherwise.
- `fake_sandbox` is a `sandbox-exec` stand-in that passes the probe by making the probe's outside directory (its last argument) read-only, then runs the command. Run-level tests use it so they work inside another sandbox.
- The forged-writes test first runs the same hostile worker unconfined and asserts every write lands. The later refusals mean something only because the unconfined run showed the writes were possible.
- The setup-failure test patches a copy of the claude adapter with `sed`. The added `l1-stage-env` verb passes the setup dry run (a stage named `.setup-*`) and fails every attempt after it, planting a symlink at the old stderr path inside the stage first.
- The colon test moves only `AUTODREAM_DIR` to a path with a colon. A colon in the session root would read as two roots and fail for a different reason.

## Consequences

Removing the unconfined control makes the refusal assertions unfalsifiable. A fake that confines nothing proves only the runner's plumbing, not the profile; `tests/l1-confine-real.sh` is the manual check for the real call.
