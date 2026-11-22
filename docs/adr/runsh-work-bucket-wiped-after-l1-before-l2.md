# runsh: The isolated work bucket is wiped after L1 as well as after L2

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `clean_work_bucket` after the round loop)

## Context
The work bucket is writable by a confined L1 worker and is also L2's launch directory, so whatever a worker left there must not be there for L2 to read. See CLAUDE.md, 'The AI-title stub vector' (wipe before L1, after L1 and after L2) and 'What the sandbox allows'.

## Decision
`clean_work_bucket` runs here, right after the retry rounds and the stage-root removal, and not only after L2.

## Consequences
- Removing this call lets a worker plant files for L2 in its launch directory.
