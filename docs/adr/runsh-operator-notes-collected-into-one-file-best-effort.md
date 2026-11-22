# runsh: operator notes reach L2 through one merged file, collected best-effort

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `VAULT_NOTES collect` step)

## Context
Every capture surface (the terminal-written `notes.md`, the vault inbox) is merged by `vault-notes.sh collect` into `operator-notes.md`, so PROMPT.md reads a single path. Adding a surface is a change to `vault-notes.sh`, never to the prompt. A broken vault must not cost the report.

## Decision
`collect` runs when `$VAULT_NOTES` is executable; failure logs `operator-note collection failed (continuing)` and the run goes on; a missing script logs and skips. See CLAUDE.md, "Operator notes: one file for the prompt, many surfaces for the human".

## Consequences
Do not make a capture failure fatal, and do not add a second notes path to PROMPT.md. Consuming (archive) is a separate, gated step; see `consume-gated-on-complete-dream-and-normal-date`.
