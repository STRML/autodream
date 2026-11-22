# tests-run-all: L1 fixtures reproduce the exact shape the runner left on disk, not a tidier one

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_incomplete`, `test_noise_gate_trivial`, `test_stale_wrongtype_findings_is_redispatched`, `test_failure_class_provider_matrix`)

## Context

Three tests pass or fail on a detail of the data that is easy to normalise away when the fixture is edited.

- The final-round stub is rewritten by the project-field normalization pass through `json.dump`, because it has a real `session_path` and no `project`. That turns `"findings":[]` into `"findings": []`.
- A findings file left by an earlier run can have `.findings` present but a string. The dispatcher guard called that "done" and exited, while `l1_missing_count` called it "missing", so nothing rewrote it and L2 aggregated it anyway. Three sites answer "is this record done?" and all three must agree.
- A worker's `.err` has a fixed layout: the worker's stderr at the top (omp's lands there), then run.sh's own lines (the session path, the exit-code line), then the stdout section, then run.sh's network note. The malformed-output branch dumps up to 2000 bytes of the worker's JSON with no trailing newline, so the session line lands on the same line as the dump. Each classifier case is a fixture of one of those positions.

## Decision

- The stub assertion matches `"findings": *\[\]`. It is about the empty array, not its spacing. `test_noise_gate_trivial` does the same for `"skipped": *"below_noise_gate"`: the normalization pass rewrites a gated stub (real `session_path`, no `project`) through `json.dump`, which reformats `"skipped":"below_noise_gate"` with a space.
- `test_stale_wrongtype_findings_is_redispatched` seeds `{"session_path":"STALE","findings":"oops"}` before the run and asserts the file is replaced by a real array.
- The `.err` fixtures in the provider/size matrix keep each worker-text, runner-text and marker line where run.sh writes it, including the dump fused to the session line.

## Consequences

Tightening the stub regex to the compact form fails on a correct run. Replacing the wrong-type seed with a missing or empty file removes the case where the guard and the counter disagreed. Tidying a `.err` fixture (adding the newline, reordering lines) turns it into a case the classifier already handled and stops it pinning the run.sh-written-text skip rules in `bin/failure-class.sh`. CLAUDE.md ("A failed worker leaves its evidence") has the rules the fixtures exercise.
