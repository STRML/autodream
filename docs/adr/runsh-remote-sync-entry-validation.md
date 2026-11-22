# runsh: Remote entries are validated before any ssh, and reserved labels are refused

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`remote_sync_refuse`, pass 1 of `sync_remote_roots`)

## Context
Run-stats builds `remote_sync_<label>`, `remote_sync_<label>_cause`, `remote_sync_<label>_last_ok` and the refusal key `remote_sync_invalid` by concatenation. A host called `invalid`, or one ending in `_cause` or `_last_ok`, would print like another run-stats line, and no reader could tell the two apart (four review rounds on the short-dates scan, 2026-11-21).

The mirrors are claude roots. With the claude adapter not enabled nothing would scan them, and a sync reported `ok` would hide a whole host's missing sessions.

## Decision
Pass 1 refuses, before any ssh: an entry with no `label=target`, a label outside `[A-Za-z0-9._-]+` (including `.` and `..`), a reserved label (`invalid`, `*_cause`, `*_last_ok`), a repeated label, and, when the claude adapter is not in `ENABLED_ADAPTERS`, every entry. The reserved check sits ahead of the adapter check so a reserved label never gets a key of its own. A refusal takes the synthetic key `invalid` (so it never joins the short list), except an entry refused only because the adapter is off, which has a real label and is passed `real` so `remote_sync_refuse` adds it to `REMOTE_SHORT_LABELS`. Each refusal counts toward `REMOTE_SYNC_BAD` and `REMOTE_SYNC_SHORT` and logs a WARNING.

See CLAUDE.md, "Remote hosts" (Validation before ssh).

## Consequences
A new run-stats suffix per label must be added to the reserved-name test. `tests/run-all.sh` has `test_remote_sync_refused_when_the_claude_adapter_is_off`.
