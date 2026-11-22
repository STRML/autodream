# bin-b: `day-file` renames a unique temp into place, copies the mtime, and treats an empty slice as an error

Status: accepted · Date: 2026-11-21 · Code: `bin/session-window.sh` (`day-file`)

## Context

`day-file` is the one call the runner makes: write the day slice of a transcript to a path when it spills outside the day.

## Decision

- Exit 1 leaves OUT alone, so a transcript wholly inside the day is read exactly as before.
- The slice goes to a unique temp beside OUT and is renamed, so a killed run never leaves a half slice that a later step reads as whole.
- The temp takes the original's mtime (`touch -r`), so `transcript_mtime` in the stats sidecar still describes the session and not the moment of slicing.
- An empty slice is exit 2. It means the file changed since enumeration, or no record survived the cut and there was no `autodream_meta` header to keep. That is no verdict on the session, so the caller reads the whole transcript instead of nothing.

## Consequences

An OMP session whose only in-day entries are on an abandoned branch gets a meta-only slice from the normalized copy and is noise-gated by the runner, not read whole. See `bin-b-session-window-slice-keeps-raw-lines.md`.
