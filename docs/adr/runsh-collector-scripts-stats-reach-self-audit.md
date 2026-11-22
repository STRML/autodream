# runsh: report-script health is copied into run-stats so a failing entry reaches the self-audit

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_scripts_stats`)

## Context
PROMPT.md tells L2 to read `report-index.txt` only when an operator note asks for a command, so an entry that fails every night would never be seen.

## Decision
After collection, `report_scripts_stats` reads the index the collector or `report_scripts_unavailable` just wrote and appends `report_scripts: off|unavailable|<entry count>` and `report_scripts_not_ok: <comma-separated names>|none` to `run-stats.txt`. An index it cannot read, or whose first line it does not recognise, is `unavailable`, never `off`.

## Consequences
PROMPT.md's self-audit names every entry that is not `ok`. See CLAUDE.md, "A failing entry reaches the self-audit".
