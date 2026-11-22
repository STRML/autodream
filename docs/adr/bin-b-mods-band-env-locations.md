# bin-b: the mod resolves autodream locations from review.sh's own environment variables

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/lib.ts` (`locations`), `mods/autodream-band/hooks/register.tsx` (`autodreamPaths`)

## Context

The mod must find the reports, `review.sh` and cmux the way `bin/review.sh` does, or it would open a different install's files. CLAUDE.md ("The Claude Code mod") already says: it reads `AUTODREAM_DIR`, `DREAMS_DIR` and `CMUX_BIN` with review.sh's defaults and cannot see a value that lives only in `$AUTODREAM_DIR/config`.

## Decision

`locations` takes `HOME`, `AUTODREAM_DIR`, `DREAMS_DIR` and `CMUX_BIN` from the mod's environment (`$.env.get` takes literal names, so the list is spelled out). An exported value wins, an empty one counts as unset, and the defaults are those of `install.sh` and `review.sh`. A value set only in the config file is invisible, so export it or set it in Claude Code's environment to move the mod too.

## Consequences

A new location knob in `review.sh` needs a matching line in `locations` and `autodreamPaths`.
