# runsh: run-stats records the counters that make a silent corpus shortfall visible

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the full-run `run-stats.txt` block: `session_roots`, `sessions_rejected_path`, `sessions_out_of_window`, `session_window`, `sessions_windowed`, `roots_*`, `adapters_enabled`)

## Context
Each of these was a way for a night to look quiet while the corpus was short. See CLAUDE.md, 'Session roots: one dir is not the corpus', 'Which day a session belongs to (the report-day window, #113)' and 'Self-audit'.
- `session_roots` (colon-count + 1) is its own stat so a regression to single-root scanning is visible from the artifact.
- Paths dropped at enumeration because a line-based `sessions.txt` cannot hold them: a nonzero value means a real transcript exists that no report will ever mention.
- Files modified since the day began that hold no record inside it (a session still being written on a later day, or one touched after its own day) belong to another day's report. A count here keeps a night whose files all fell outside the window from reading as a quiet one. `session_window` says whether the timestamp window was in force at all: a stats file with it off, or without the key, was placed by file mtime alone. `sessions_windowed` is how many triaged sessions spill outside the day, whose stats and L1 read are cut to the day.
- Roots whose enumerator errored yet still returned paths: the night's corpus may be short by an unknown amount, not a failure but not a clean read either, and the aggregator should not treat the totals as complete.
- Adapter refusals that still left claude accepted (a third-party adapter failing containment, a mismatched manifest name, a lost exec bit) are otherwise completely silent: same silent-shortfall class as `overlap_measured` and `stats_sidecars_unparseable`, recorded as `adapters_rejected`.
- A source that drops to zero on a day the user worked in it is the signal that its ingest broke, invisible without a per-source count.

## Decision
`run-stats.txt` carries `session_roots`/`session_roots_list`, `sessions_rejected_path`, `sessions_out_of_window`, `session_window`, `sessions_windowed`, `roots_partially_enumerated`/`roots_unavailable`/`roots_failed`, `adapters_enabled` with `sessions_by_source` (the per-source count) and `adapters_rejected` on every full run, written even when zero so that a zero means something.

## Consequences
- A new way for a night to be short needs its own counter here, and the same key on the zero-session path (see `zero-session-night-writes-full-run-stats-and-still-cleans-up`).
- Do not fold these into one combined number.
