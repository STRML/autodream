# bin-a: a usage error exits 2 and an unreadable input exits 3, so neither reads as a skip or as "not ours"

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`stats|slim`, `is-self`), `adapters/_fixture/adapter.sh` (`is-self`)

## Context

Exit 1 from `project`, `stats`, `slim` and `normalize` means "skip this session". Exit 2 is the unknown-subcommand code. Under `set -u` a one-argument `stats` or `slim` call died with `$2: unbound variable` and status 1, indistinguishable from a legitimate skip when the caller had made a usage error. `is-self` delegates to `prune-self-sessions.sh`, which greps with `2>/dev/null` and returns 1 for both "not ours" and "file not there", so a vanished or unreadable transcript looked like a real user session, and the contract has no channel to say "I could not read it".

## Decision

- `stats`, `slim` and `normalize` check arity (`$# -ge 2`, exit 2) before dereferencing `$2`.
- `is-self` checks readability first and exits 3, a nonzero that is not 1 and is not the unknown-subcommand code. The fixture adapter answers the same way: it always says "not ours", but only for a readable session, because the fixture exists to make a contract gap fail there rather than in production.

## Consequences

Callers that treat any nonzero as a skip still work; a caller that wants to tell usage or unreadable input apart can. `tests/adapter-contract.sh` runs the same checks against every adapter.
