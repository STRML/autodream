# bin-a: the adapters root is found for both the repo layout and the flat install layout, flat first

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`adapters_root`)

## Context

Two layouts have to work. In the repo, `bin/` and `adapters/` are siblings. Under the install, `install.sh` symlinks everything flat into `~/.claude/autodream`, so `adapters/` sits beside `adapters.sh` rather than one level up. Assuming only one of them is how the first version of this change shipped a silently broken install.

## Decision

`ADAPTERS_ROOT` wins when set. Otherwise `adapters_root` checks `<dir of adapters.sh>/adapters` first and falls back to `<dir of adapters.sh>/../adapters`. The flat layout is checked first because the nightly runs from the installed copy, which is the expensive one to get wrong.

## Consequences

A change to where `install.sh` links the adapters tree has to keep one of these two shapes (see `docs/adr/bin-b-install-adapters-tree.md`). Check the installed copy after touching `adapters_root`, since the nightly runs from it.
