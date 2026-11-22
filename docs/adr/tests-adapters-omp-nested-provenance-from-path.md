# tests-adapters: omp nested-session flags come from the path, and the test goes through normalize

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-omp.sh` (the nested, advisor and `isSidechain` groups)

## Context

An omp child (`<stamp>_<id>/__advisor.jsonl`, `<stamp>_<id>/<Name>.jsonl`) has no user turns and no `session_init`; its provenance is its path (CLAUDE.md "The OMP adapter"). The old `isSidechain` rule keyed off `custom/agent` and `custom/subagent` records. omp writes neither, so the flag read false for every file and the noise gate's sidechain exemption never applied to a child (#114).

## Decision

- A child whose parent file is gone is still nested: the stamped directory name says so.
- The tests cover the path through `normalize` as well as raw `stats`, because that is the path the runner takes. The linearizer and `stats` are two files holding one rule, and a recorded `false` must not fall back to the filename, which on a normalized copy is a temp name. `autodream_meta` carries `nested` and `is_advisor` for that reason.
- `isSidechain` is asserted from provenance (advisor child, named child), never from a custom record.

## Consequences

A test that runs `stats` only on the raw file would pass with the normalize path broken. Keep both.
