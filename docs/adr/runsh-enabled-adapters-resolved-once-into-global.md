# runsh: the enabled-adapter list is resolved once into a global by a function that prints nothing

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`resolve_enabled_adapters`, `ENABLED_ADAPTERS`, `ENABLED_ADAPTERS_RESOLVED`, `_enabled_adapters_uncached`)

## Context
The first version was a memoised `enabled_adapters` that every caller invoked as `$(enabled_adapters)`, so the cache assignment happened inside a command substitution and died with the subshell, leaving `ENABLED_ADAPTERS_RESOLVED` at 0 in the parent on every call. The loader re-ran all three times and the duplicate warning the memo was written to stop came straight back (reproduced: the uncached body ran 3/3 times and the cache stayed empty). It is the trap `adapters.sh`'s own header documents for `adapters_rejected`: a file crosses the subshell boundary, a variable does not.

## Decision
`resolve_enabled_adapters` assigns the global and returns, printing nothing; callers read `ENABLED_ADAPTERS`. The boundary is crossed by not creating one. Inside the uncached resolver, the "accepted but not enabled" diagnostic goes to stderr, NOT stdout: the function's stdout is its return channel and `log()` is a bare echo, so a diagnostic on stdout was word-split into bogus adapter names.

## Consequences
Never call `resolve_enabled_adapters` inside `$(...)`, and never log to stdout from a function whose stdout is captured. CLAUDE.md's "Bash traps this feature hit" has the same class ("A variable set inside `$(...)` never comes back").
