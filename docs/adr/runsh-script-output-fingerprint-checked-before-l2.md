# runsh: report-script output is re-hashed before L2 and replaced with an `unavailable` index if it changed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `fingerprint_unchanged report_output_fingerprint`, `report_scripts_unavailable`, `report_scripts_stats`)

## Context
L1 workers that are not confined can write anywhere the user can, the findings dir included. What L2 reads for an operator note is `report-index.txt` and the `report-<name>.md` files it names, which were collected before L1.

## Decision
The fingerprint is `report-index.txt` plus every `report-*.md` (name and sha256), taken by `report_output_fingerprint` straight after collection and held in memory (`REPORT_OUT_FP`); it is compared by `fingerprint_unchanged` after L1 and before L2. Any difference from the hashes the runner took right after collection (a file changed, added or deleted, or a failure to hash them then, which leaves `REPORT_OUT_FP` empty and so never matches) replaces the report files with an `unavailable` index. The earlier run's files are removed by the same call, and the run stops (`log_fatal`, `fatal_exit`) only if that cannot be done. `report_scripts_stats` then writes `report_scripts` and `report_scripts_not_ok` to run-stats from the index as it now stands. See CLAUDE.md, "Report scripts: one collector so a note can ask for a command" (the snapshot, collection-before-L1, and output fingerprint paragraphs).

## Consequences
Confined workers (#241) cannot write the findings dir, so on a confined host this never fires. Do not move collection after L1: that reopens the window the fingerprint exists to close.
