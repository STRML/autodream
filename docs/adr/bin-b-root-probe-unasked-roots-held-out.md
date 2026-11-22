# bin-b: an unasked Claude folder is held out of the scan until the user decides

Status: accepted · Date: 2026-11-21 · Code: `bin/root-probe.sh` (`choice`, `--consolidated`, `--unindexed`, the `WRITE` block)

## Context

autodream used to scan only `$HOME/.claude/projects`. Sessions recorded under another profile's bucket (`~/.claude-nous`, `~/.claude-ds4`, ...) were invisible to the nightly report, and the triage count fell from 132 to 1 sessions a night over 2026-08-03..06 with no error. CLAUDE.md, "Session roots: one dir is not the corpus", records the fix and its semantics.

## Decision

- Each folder is `index`, `ignore` or `unasked`. The primary `$HOME/.claude/projects` is always `index` and always scanned. Everything else takes its state from `root-choices.conf`, and a folder with no line is `unasked`.
- Only `--ask` and `--default-index` write choices. The nightly run passes neither, so it never writes. An `unasked` folder stays out of `--consolidated` and shows in `--unindexed`, which feeds the "found a folder we're not indexing" line in the report. Scanning it would make that flag a lie.
- `--ask` on a TTY prompts per folder. Without a TTY, and under `--default-index`, every unasked folder becomes `index` (logged to stderr), so a fresh install covers everything silently.
- `--consolidated` lists the primary first, then the other `index` folders.

## Consequences

Editing or deleting a line in `root-choices.conf` is how a user changes a choice. Writing choices from the nightly path would silence the flag it exists to raise.
