# bin-a: autodream-now.sh derives its defaults and its date exactly as run.sh does

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`DREAMS_DIR`, `TARGET`)

## Context

`--watch` and the generated plist have to point where `run.sh` writes, and the one-shot has to process the same day `run.sh` would pick for "yesterday". Two scripts with separate defaults can silently disagree, as the install-dir copies did (#112).

## Decision

`DREAMS_DIR` defaults to `$HOME/.claude/dreams`, the default `run.sh` uses, and the same env overrides are honored so a customized install (different `AUTODREAM_DIR` or `DREAMS_DIR`) still works. With no date argument, `TARGET` comes from `pdate_yesterday`: plain system-local BSD date, no `TZ` override, so it cannot disagree with `run.sh` about which day yesterday is.

## Consequences

A new default or a changed date rule in `run.sh` needs the same change here. Adding a `TZ` override on either side would shift "yesterday" for one of them.
