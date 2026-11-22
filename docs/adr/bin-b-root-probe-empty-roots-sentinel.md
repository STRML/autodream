# bin-b: root-probe keeps a one-element empty-string sentinel when no root exists

Status: accepted · Date: 2026-11-21 · Code: `bin/root-probe.sh` (`roots=("")`, the `[ -n "$r" ] || continue` guards)

## Context

macOS ships bash 3.2. Under `set -u` there, `"${roots[@]}"` on an empty array is an unbound-variable error, and a host with no `$HOME/.claude*/projects` at all has an empty `roots`.

## Decision

After discovery, an empty `roots` becomes `("")`. Every loop over `roots` skips the empty entry with `[ -n "$r" ] || continue`, so every expansion is safe and the empty entry never reaches output.

## Consequences

A new loop over `roots` needs the same `-n` guard. Replacing the sentinel with an `${roots[@]+...}` expansion at each loop is possible but touches every site, and a missed one only fails on bash 3.2 with no roots.
