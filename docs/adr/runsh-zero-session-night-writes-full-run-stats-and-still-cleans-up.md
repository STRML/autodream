# runsh: A night with nothing to triage still cleans up, reconciles, and writes the full run-stats key set

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `COUNT -eq 0` early path)

## Context
- A zero-session night is not always an empty night. Every session can be rejected for an unrepresentable path or dropped by collision handling. Without run-stats on this path the report said "no sessions were modified" while the counters that would have contradicted it were never recorded.
- PROMPT.md tells L2 that keys missing from `run-stats.txt` mean the runner predated the stat. A zero-session night on CURRENT code therefore produced a morning report blaming a stale checkout for the gap. A night with nothing to triage genuinely did zero L1 rounds and measured no overlap; saying so differs from not saying it.
- The first draft of the key set emitted `l1_missing`, `oversized_slimmed`, `overlap_pairs` and `elapsed`, none of which the full-run block writes. That would have left the real keys missing while adding four L2 has never seen.
- An empty worklist owns nothing, so every `.err` with no findings JSON is orphaned and every findings JSON is outside it. A night that found no session must not report zero over a directory that holds stale failures.
- PROMPT.md defines an empty `unassembled_dates` as "none" and tells L2 to name the dates for any non-empty value, so writing `none` handed L2 a date list to report.

## Decision
- `sweep_killed_leftovers` runs before the exit: a night with no sessions still owes the cleanup.
- No L2 runs on this path, so no model reads a report file tonight: report scripts are not collected here, as operator notes and bookmarks are not. See CLAUDE.md, 'Report scripts' ("A zero-session day collects nothing, on purpose").
- `reconcile_findings_with_worklist` and `scan_worklist_leftovers` run here and `l1_err_files` is counted from disk.
- `run-stats.txt` is written with the full-run key set as real zeroes (or the real values), with the key names copied from the full-run block. Keys the full run appends after that block (`x_queryid_source`, `x_fetch_path`, `l2_engine`, `l2_model`, `citations_*`) are not written on this path, and neither is `legacy_marker_reports`, which only the full-run block writes. `self_sessions_excluded` and `sessions_skipped_empty` are emitted so a night of worker transcripts or empty shells does not look like a night with no files. The shortfall counters (`roots_partially_enumerated`, `roots_unavailable`, `roots_failed`, `session_roots`) belong here most of all, because a partial walk or a single-root regression is exactly what would explain the empty night. `overlap_measured: no` is emitted with zero events and zero sessions, which is not the same as the overlap pass having failed. `unassembled_dates` is written empty, never `none`.

- The stub body does not state an empty night as fact when it cannot support it. A failed or unavailable session root (counted against `ROOTS_CONFIGURED`, not `ROOTS_SCANNED`, because a root that was never a directory is missing from `ROOTS_SCANNED` entirely) or a remote host that did not fully sync says "whether this was an empty night is unknown". Files modified since the day began but with no record inside it are said with their count, not as "no files were modified". Refused paths never reach `sessions.txt.raw`, so they are counted beside `RAW` and not folded into it. This is what made removing the fatal for a single failed root defensible: on a single-root host that shape is a quiet date plus a transient find error, and losing the night is the wrong trade.

## Consequences
- A key added to the full-run block needs the same line here, with a real value or an honest zero.
- Do not invent key names here; copy them from the full-run block.
