# bin-b: triage-dream.sh finds its libraries and prompt beside itself, beside its symlink target, in the install dir, then in prompts/

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (`find_file`)

## Context

The install symlinks each script into `$AUTODREAM_DIR`, so the directory a script runs from may not hold its libraries or `TRIAGE_DREAM.md`. See `bin-b-review-sibling-lookup-through-symlink.md` for the same reason in `review.sh`.

## Decision

`find_file` returns the first readable copy from the script's directory, the symlink target's directory, `$AUTODREAM_DIR`, then `<target dir>/../prompts`.

## Consequences

A new helper or prompt is found whichever way the script was started, including a checkout run before `install.sh` re-links.
