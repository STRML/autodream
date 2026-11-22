# runsh: the isolated work bucket is exported to workers but is not on the confinement write list, so run.sh keeps wiping it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`, `clean_work_bucket`)

## Context
Workers launch from `$WORK_DIR` so a Claude Code AI-title stub lands in `$WORK_BUCKET` and not in the real session bucket. That bucket is the one directory every worker, the thread linker and a concurrent date's L2 share.

## Decision
`l1_confine_setup` exports `AUTODREAM_WORK_BUCKET="$WORK_BUCKET"` but the bucket is not on the claude write list, so a confined worker cannot write it (a confined call exits 0 with its AI-title write refused). An unconfined worker still can, which is why `run.sh` wipes the bucket before L1, after L1 and after L2.

## Consequences
Do not add the bucket to the write list to "fix" a refused title write: it would hand workers the shared directory. Do not drop the wipes while any engine can run unconfined. See CLAUDE.md, "What the sandbox allows" and "The AI-title stub vector".
