# runsh: a helper's `AUTODREAM_*_BIN` override is authoritative, with no existability fallback

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`ROOT_PROBE`, `STATS`, `OVERLAP`, `VAULT_NOTES`, `XBOOKMARKS`, `REPORT_SCRIPTS`, `PRUNE_WORKTREES`, `TRIAGE_CANDIDATES` resolution blocks)

## Context
Tests need to force a stubbed, missing or deliberately broken helper: a nonexistent sidecar generator (#27), a missing or stubbed overlap binary so `compute_overlap_stats` takes its "not measured" paths (#26), a stub root prober so the scan fallbacks run deterministically, a missing vault or bookmark helper. The ordinary `[ -x "$X" ] || X="$AUTODREAM_DIR/..."` chain would rescue a nonexistent override back to the working repo copy and defeat the override.

## Decision
When `AUTODREAM_ROOTPROBE_BIN`, `AUTODREAM_STATS_BIN`, `AUTODREAM_OVERLAP_BIN`, `AUTODREAM_VAULT_BIN`, `AUTODREAM_XBOOKMARKS_BIN`, `AUTODREAM_REPORTS_BIN`, `AUTODREAM_PRUNE_BIN` or `AUTODREAM_TRIAGE_BIN` is set (non-empty), its value is used as is; only the unset case runs the "next to this script, then the install dir" lookup. The helpers are optional context-gatherers (vault-notes degrades to the plain notes.md when no vault is set, x-bookmarks to a "not configured" stub, the pruner is opt-in through `AUTODREAM_PRUNE_ROOTS` and a no-op otherwise, the triage list is on by default because it only reads issues, the report-script collector exists because L2 has Read and Glob only and a missing conf means no reports).

## Consequences
Do not add an existability fallback to an override branch; the tests that exercise missing-helper paths would silently pass against the real script. A new helper with a test-facing override follows the same two-branch shape. See CLAUDE.md, "Report scripts" and "Operator notes".
