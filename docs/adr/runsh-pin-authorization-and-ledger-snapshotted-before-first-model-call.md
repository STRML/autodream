# runsh: The pin authorization list and the pins ledger are held in the runner's memory before any model runs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `PIN_PROJECTS_*`, `SESSION_ROWS`, `PINS_LEDGER_*`)

## Context
L1 workers run with the Write tool and `bypassPermissions`, so any file they can reach they can rewrite: `sessions.txt`, `sessions-source.txt`, findings JSON. (The original code comment says L2 holds Write too; that is stale, L2 is read-only (`Glob Read`) now, which is why only L1 is the writer here.) A worker could also empty `pins-applied.tsv`, after which the apply step would store every pin again. See CLAUDE.md, 'findings/YYYY-MM-DD/pin-projects.tsv' and '`pins-applied.tsv`'.

## Decision
- Before the first model call, `session_rows` builds `SESSION_ROWS`, and `PIN_PROJECTS_TSV` and `SESSION_CWDS_TSV` are derived from it; they stay in this shell's memory until the pins are applied after the report. If any step fails, `PIN_PROJECTS_BUILT` stays 0 and the run stores no memory pins.
- The ledger's content is read into `PINS_LEDGER_SNAPSHOT_X` and put back before the pins are applied. A ledger that exists but cannot be read leaves nothing to restore from, so `PINS_LEDGER_OK=0` and this run stores no pins.
- The ledger is read with `cat ... && printf x`: the trailing `x` keeps `$(...)` from stripping the ledger's final newline.

## Consequences
- Do not rebuild the project list or re-read the ledger after L1 or L2 from disk.
- The trailing `x` must be stripped when the snapshot is restored; removing it silently drops the last newline of the ledger.
