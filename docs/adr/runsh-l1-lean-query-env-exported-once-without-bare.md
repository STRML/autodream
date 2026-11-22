# runsh: The lean-query environment is exported once, and `--bare` is not used

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `export CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 ...` line before L1)

## Context
L1 and L2 need a token-minimal footprint without losing subscription OAuth auth. `--bare` disables OAuth/keychain auth and requires an API key. The pattern is borrowed from claude-cells `internal/claude/query.go`. See CLAUDE.md, 'How claude is invoked — the lean-query pattern (do not use `--bare`)'.

## Decision
`CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1` are exported once, so both the L1 xargs subshells and the L2 call inherit them. They combine with the per-call flags (`--no-session-persistence`, `--tools`, `--disable-slash-commands`, `--strict-mcp-config`, `--settings disableAllHooks`), which now come from the adapter's argv.

## Consequences
- Do not switch to `--bare` or `CLAUDE_CODE_SIMPLE=1`: both return "Not logged in" on this host.
- A new env stripping belongs in this one export so both layers inherit it.
