# bin-b: the plist PATH carries every CLI the nightly runs, resolved config first

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`adapter_bin_dirs`, `adapter_bin_dirs_one`, `x_browser_bin_dirs`, `config_bin_dir`, `install_schedule`)

## Context

launchd has no login shell, so a CLI outside the usual directories is unreachable unless its directory is in the plist PATH (omp under `~/.bun/bin` is the real case; without it the omp worker cannot start and the night's omp sessions vanish with only a FATAL in the run log). `agent-browser` is a node script (`#!/usr/bin/env node`), so launchd needs the directory of `node` too. CLAUDE.md, "What goes in the plist PATH", has the history.

## Decision

- The PATH is seeded with the directories of `claude`, `git`, `bash` and `rsync`, then the engine of every enabled adapter and of the L2 engine, then (with `AUTODREAM_X_FETCH=browser`) `agent-browser` and `node`, then the usual system directories.
- `<NAME>_BIN` or `X_BROWSER_BIN` from the config wins when it names an absolute, executable, non-temp file, as the adapters resolve it at run time. The installer's own environment does not count.
- An adapter name reaches an indirect expansion, so it must match the character set `--adapters` enforces; a hand-edited config cannot put anything else there.
- `claude`'s resolved path is remembered as `CLAUDE_BIN_ABS` for the review agent (see `bin-b-install-review-claude-bin`).

## Consequences

The PATH is fixed when the plist is written, so enabling an adapter afterward needs a re-install (or `<NAME>_BIN` in the config).
