# bin-b: the installer reads config values by sourcing the file, as run.sh does

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`cfg_get`)

## Context

The plist and the review agent depend on values like `CMUX_BIN`, `CLAUDE_BIN`, `AUTODREAM_REVIEW_AGENT` and `<NAME>_BIN`. `review.sh` and `run.sh` read them by sourcing the config as Bash. A sed or raw read would take literal quote characters from `CMUX_BIN="$HOME/bin/cmux"`, fail the `-x` test, and wrongly skip (and unload) the review agent for a perfectly valid config.

## Decision

`cfg_get VAR` sources the config in a throwaway `bash -c` with `AUTODREAM_DIR` set to the target and the variable unset first, so `export KEY=value`, quotes, `$HOME`, `~` and later assignments all resolve as at run time. A caller strips any stray double quotes that survive.

## Consequences

Cost: one subshell per read. A value only in the installer's environment is not read here on purpose (launchd will not carry it).
