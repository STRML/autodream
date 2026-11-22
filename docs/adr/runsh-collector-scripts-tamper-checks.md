# runsh: the report-script collector and its output are fingerprinted, and a fingerprint that cannot be taken counts as changed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_collector_fingerprint`, `fingerprint_unchanged`, `report_output_fingerprint`, `report_scripts_unavailable`)

## Context
The collector and the `portable.sh` it sources are code the run executes with the operator's privileges, and an L1 worker that is not confined holds Write. Comparing `"$(fn)"` directly discards `fn`'s exit status, so a fingerprint that printed the matching rows and then failed on the next file would read as unchanged. A forced rerun keeps the findings directory, so any earlier run's `report-*.md` files would be read by L2 as tonight's output unless something clears them. A worker that is not confined can plant a directory with such a name, and `rm -f` would leave it standing and stop the night over a file the runner is entitled to clear.

## Decision
- `report_collector_fingerprint` prints the sha256 of `$REPORT_SCRIPTS` and of its sibling `portable.sh` (resolving the symlink if needed), one per line, and fails when either cannot be read or hashed. It is taken before the snapshot and the first model call, and checked again right before `collect`.
- `fingerprint_unchanged FN BEFORE` is true only when the function succeeds and prints exactly the earlier output; an empty earlier value is never "unchanged".
- `report_output_fingerprint` prints `name sha256` for `report-index.txt` and every `report-*.md`, in name order, and fails when the directory cannot be entered or any file cannot be hashed. The runner holds the first result in memory and compares before L2.
- `report_scripts_unavailable WHY` runs whenever the collector does not finish or the output changed: it removes the earlier `report-*.md` and `report-index.txt` with `rm -rf` and writes an `unavailable` index. It returns 1 when it cannot, and the caller stops the run instead of letting L2 read last night's rows.

## Consequences
The original comment says the collector runs "after L1 workers have run"; that is out of date. Collection now runs before the first model call, and the first fingerprint is checked right before collect and the output fingerprint again before L2. Never make a failed hash read as "unchanged". See CLAUDE.md, "Report scripts: one collector so a note can ask for a command" (snapshot, collection before the first model call, the residual for unconfined workers).
