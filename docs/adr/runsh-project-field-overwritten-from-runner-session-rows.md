# runsh: The findings `project` field is overwritten deterministically from the runner's own session rows

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the python3 block after the oversized loop)

## Context
SESSION_TRIAGE.md asks the L1 worker to emit `project` by hand, and haiku does it nondeterministically: one run surfaced the SAME `-Users-sean` dir as `-Users-sean`, `Users-sean` (dash stripped), and even the bare session UUID (filename, not dir). That splinters L2's per-project grouping.

## Decision
The project is the bucket the runner already computed for each session in `SESSION_ROWS` (see `session_rows`) before L1 ran. Each findings file is looked up by its own name, the session hash, never by the `session_path` the model wrote, and its `project` field is overwritten, atomically (temp file plus `os.replace`). Malformed JSON and non-object JSON are left for the triage-failures report section. It is idempotent on re-runs. Without `python3` the step is skipped with a log line (L2 grouping may show dupes).

## Consequences
- Do not key the lookup off anything in the findings JSON, which the model wrote.
