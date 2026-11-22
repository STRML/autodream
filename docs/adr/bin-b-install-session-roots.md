# bin-b: install decides which session roots are indexed once, and the nightly never asks

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the session-roots block)

## Context

autodream scans every `$HOME/.claude*/projects` that has a session store. The nightly run is unattended, so it cannot ask which folders to index. CLAUDE.md, "Session roots: one dir is not the corpus", records the blackout this prevents and the semantics of an unasked folder.

## Decision

- At install time `root-probe.sh` records each folder's decision in `root-choices.conf`: `--ask` on a TTY, `--default-index` otherwise (CI, an automated shell), so a non-interactive install silently covers everything and the log line says what was chosen.
- The `SESSION_ROOTS` line is a managed section of `config` that `run.sh` sources. The install removes the old section (the marker line and any `SESSION_ROOTS=` lines under it) before writing the new one, so a re-install converges instead of stacking definitions.

## Consequences

See the CLAUDE.md section for why an unasked folder is held out of the report. Changing the marker text means changing the awk that strips it.
