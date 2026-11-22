# tests-run-all: the multi-root fixtures autodetect roots from a sandbox HOME and dedupe through a symlink

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`run_dream_autodetect`, `test_multiroot_heldout_and_dedup`)

## Context

Multi-root scanning is only exercised when `run.sh` autodetects `$HOME/.claude*/projects` through `bin/root-probe.sh`. If the fixture exported `PROJECTS_DIR` or `SESSION_ROOTS`, autodetection would be bypassed and the test would pass over code it never ran. Autodetecting against the real `$HOME` would instead scan the host's own claude dirs.

Dedup across roots needs two roots that reach the same file. `find -type f` follows a symlink and reports the target path, so a symlink in the alt root pointing at the primary's transcript yields the same path from both roots, and only the final `sort -u` can collapse it.

## Decision

- `run_dream_autodetect` leaves `PROJECTS_DIR` unset and points `HOME` into the sandbox (`$root/home`), so root-probe discovers the sandbox's `.claude*` dirs and nothing from the host.
- The dedup test builds the second reference as a symlink into the primary root, not a copy. A copy is a different path and would never exercise `sort -u`.

## Consequences

Do not export `PROJECTS_DIR` or `SESSION_ROOTS` from these helpers, and do not replace the symlink with a copy: both changes keep the assertions green while testing nothing. CLAUDE.md, "Session roots: one dir is not the corpus", records the scanning rules.
