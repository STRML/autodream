# runsh: the claude adapter scans root-probe's roots; every other adapter uses its own configured or manifest roots; roots are newline-terminated

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`adapter_roots`)

## Context
root-probe decides which `$HOME/.claude*/projects` dirs are indexed and the user's per-folder choices live there, but it knows nothing about a second harness's store. Separately, `while read` drops a final unterminated line, so an earlier `printf '%s'` here silently skipped the only root on a single-root host: enumeration found nothing and reported a quiet zero.

## Decision
For `claude`, `adapter_roots` prints `SESSION_ROOTS` split on `:`. For any other adapter it prints `AUTODREAM_SESSION_ROOTS_<NAME>` if set (name upper-cased, `-` to `_`), else the manifest's `session_roots_default[]`. EVERY output line is newline-terminated (`printf '%s\n'`).

## Consequences
Keep the `\n` in each `printf`; the single-root case is the default install. A new harness's roots belong in its manifest, not in root-probe. See CLAUDE.md, "Several harnesses in one run".
