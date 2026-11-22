# runsh: Adapter refusals are logged under this run's findings dir, not in the installed source tree

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `ADAPTERS_REJECT_LOG` export before `scan_roots`)

## Context
Adapter refusals used to be written back into the installed source tree, where they persist across runs and vanish entirely on a read-only install.

## Decision
`run` exports `ADAPTERS_REJECT_LOG="$FINDINGS_DIR/.adapters-rejected"` and truncates it (`: > ... || true`) before `scan_roots`, so refusals belong with this run's artifacts. `adapters_rejected` (the `adapters_rejected:` run-stats line) reads from there.

## Consequences
- The file is per findings dir, so a rebuild of a date starts it empty again.
- A failure to truncate is ignored on purpose: a read-only findings dir must not stop the run here.
- Pointing the log back into the adapters tree reintroduces cross-run persistence and the read-only-install failure.
