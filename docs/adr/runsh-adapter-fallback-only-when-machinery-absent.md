# runsh: the built-in `claude` adapter fallback fires only when the adapter machinery is absent, never when the loader accepted nothing

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`_enabled_adapters_uncached`)

## Context
An install symlinked at a tree predating `adapters/` has no loader, and a partial upgrade should degrade instead of losing a night. But a tree that is present from which the loader accepted nothing is a REFUSAL (a claude directory rejected for failing containment or carrying a mismatched manifest): manufacturing `claude` back into the list would execute a rejected adapter anyway, which turns every check in `adapters.sh` into decoration.

## Decision
"Genuinely absent" means the loader is not sourced (`declare -F adapters_list` fails) OR the adapters tree does not exist (a tarball or partial install): return `claude`. A present tree with nothing accepted returns the empty list, which `scan_roots` turns into a fatal. Conflating the two broke a non-git install test in the first version and would have let a rejected adapter run.

## Consequences
Do not widen the fallback condition. See CLAUDE.md, "Several harnesses in one run".
