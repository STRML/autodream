# web: a night with run-stats but no worklist is damaged, not complete

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream_web_data.py` (`run_enumerated`, `night_sessions`)

## Context

Stats counts a night's sessions from `sessions.txt`. When that file is missing, treating the night as empty makes a damaged run read as complete, and a session that was triaged but never finished looks like it does not exist (#204).

`fatal_exit` in `run.sh` writes `run-stats.txt` with a `fatal:` line before any enumeration, so a fatal run legitimately has no worklist.

## Decision

- `run_enumerated` says whether a run got as far as enumeration. A readable `run-stats.txt` with no `fatal:` line means yes. One that exists but cannot be read also means yes, since an unreadable file proves nothing about a fatal exit. No file means no.
- When the run enumerated and `sessions.txt` is absent, the night is degraded (`sessions.txt` joins the unreadable set) and every `*.stats.json` sidecar counts as a pending session.
- Without a worklist no rebuild left stale sidecars behind, so a sidecar with no findings JSON is a session still pending. Leaving it out would read the night as complete.

## Consequences

The CLAUDE.md "Local web dashboard" section states the damaged-night rule in one sentence. Keep `tests/autodream-web-data.py` cases for fatal, unreadable and missing run-stats in step with this logic when `run.sh` changes what a fatal run writes.
