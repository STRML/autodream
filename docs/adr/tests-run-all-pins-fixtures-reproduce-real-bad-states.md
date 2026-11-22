# tests-run-all: pin fixtures leave exactly one guard standing and build the bad state the way L1 or L2 could

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_pins_tab_in_cwd_never_splits_the_row`, `test_pins_forged_session_path_authorizes_nothing`, `pins_tamper_case`, `test_pins_ledger_wiped_by_a_worker_stores_nothing_twice`, `test_pins_failed_move_aside_leaves_no_temp_file`)

## Context

Pin authorization has several layers. A fixture that trips an earlier layer passes without reaching the one it names. Several bad states also arrive through the model's Write tool, so the fixture has to build them the same way.

## Decision

- **Tab in a cwd.** The tab encodes to a dash, so the bucket really is the tab cwd's own and the bucket check passes. Only the tab guard stands between that row and a split `pin-projects.tsv` line.
- **Forged session path and tampered worklist.** The other project's session exists and is readable, but its mtime is outside the target date, so the run never enumerates or triages it. Only a forged `session_path`, or a line appended to `sessions.txt` by L1 or L2, can point at it. A fixture that touches it to the report day would make it a legitimate session.
- **Ledger wipe.** The test deletes the first run's findings JSONs before the forced rebuild. Otherwise L1 sees every session as done and never starts a worker, so the mock never empties the ledger and the runner's snapshot is never exercised.
- **Directory at the pins path.** `mkdir -p pins.jsonl/sub` is what L2's Write tool produces by writing any path under `pins.jsonl/`. `mv` cannot put that over the `mktemp` file, which is the case the move-aside guard exists for.

## Consequences

Giving the "other project" session an in-window mtime, or leaving the first run's findings in place, keeps the tests green and removes what they prove.
