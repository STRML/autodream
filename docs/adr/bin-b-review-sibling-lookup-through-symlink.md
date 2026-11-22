# bin-b: review.sh looks for a sibling helper beside itself, then beside its symlink target, and defaults reports to the install dir's sibling

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (`source_sibling`, `DREAMS_DIR` default)

## Context

`install.sh` symlinks each script into `$AUTODREAM_DIR`. A merge updates the repo checkout, and so every installed script, before `install.sh` links a newly added helper. Looking only beside the symlink would then fail with a missing file.

An install under another prefix (the omp one lived in `~/.omp/agent/{autodream,dreams}`) made the legacy `~/.claude/dreams` default fail every manual `review.sh <date>` with "could not locate" the report.

## Decision

- `source_sibling` tries the symlink's own directory first, then the directory of `readlink`'s target.
- `DREAMS_DIR` defaults to `dreams` beside the install dir, not to `~/.claude/dreams`. Install-dir resolution itself is `bin/lib-install-dir.sh`.

## Consequences

A new helper that `review.sh` sources is found straight after a merge. `bin/triage-dream.sh` has the same lookup in `find_file` (see `bin-b-triage-dream-sibling-lookup.md`).
