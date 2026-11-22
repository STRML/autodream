# bin-a: the adapter name check lists its characters instead of using ranges

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`_adapter_name_safe`)

## Context

A safe adapter name starts with a lowercase letter and then holds only lowercase letters, digits, underscore and dash. It has no separators, so the name cannot walk out of the adapters root on its own. `[a-z]` is collation-dependent: under a UTF-8 locale the order is aAbBcC..., so the range matches uppercase too. The check therefore passed on macOS (C collation) and silently accepted an uppercase basename on Linux, which made a containment check weaker on the platform CI runs.

## Decision

`_adapter_name_safe` spells out `abcdefghijklmnopqrstuvwxyz` and `0123456789_-` in its patterns. Enumeration has no collation ambiguity. It is a function of its own, separate from `_adapter_ok`, because the dispatchers need it too (see `docs/adr/bin-a-adapters-manifest-data-basename-identity.md`).

## Consequences

Do not "simplify" the patterns to `[a-z]` or `[0-9]`-style ranges, which depend on the locale. The behavior only differs under a UTF-8 locale on Linux, so a macOS-only run will not show a regression.
