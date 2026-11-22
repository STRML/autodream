# bin-b: --adapters and --l2-engine write one managed config section, validated before any write

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`valid_adapter`, the adapters and L2 engine block)

## Context

CLAUDE.md, "Rehearsing an install", describes the flags. Two failure modes shaped them:

- A typo written into the config makes the nightly enable nothing and refuse to scan, so every name is checked against `adapters/` (and a safe character set) before anything is written, exit 64.
- Re-running with one flag must not drop the host's other choice, and `run.sh` sources the config with the caller's exported variables winning, so the section never overrides a caller.

## Decision

The section is replaced in place (strip from the marker through its keys, append anew), so a re-install converges. An absent flag leaves the section alone, and when only one flag is given the other key keeps its present value, read back from the config.

## Consequences

The marker text `# adapters (managed by install.sh)` is matched by the strip awk. A new key in this section must be added to that awk's key list.
