# bin-a: preflight stops hard on missing `jq`, `shasum`, `realpath` and the L2 engine, and only warns about `python3`

Status: accepted · Date: 2026-11-21 · Code: `bin/preflight.sh` (`need`, `_forced_missing`)

## Context

Preflight runs before anything is enumerated. `run.sh` already depended on all four tools; `realpath` is the new one, for adapter containment and cwd canonicalisation.

| Tool | What its absence costs |
|---|---|
| `jq` | every findings record, sidecar and manifest is parsed with it |
| `shasum` | the artifact key is sha1 of the session path; with no `shasum` every session collides on one filename, silently (see `bin-a-lib-project-session-hash.md`) |
| `realpath` | adapter directory containment and cwd canonicalisation; a host that reached adapter loading without it would fall back to weaker containment, which is the failure the check exists to prevent |
| `python3` | the project-field normalisation step is skipped and L2 grouping may show duplicate projects |

`python3` was once fatal here, and that contradicted the normalisation step, which already degrades gracefully without it. On a host where `python3` is only a pyenv shim absent from the launchd PATH, the nightly would have gone from a slightly worse report to no report at all, every night.

Emptying `PATH` to hide one dependency also hides bash's own helpers, so the suite could not otherwise exercise a single missing tool.

## Decision

- `need` prints `MISSING: <tool>` and counts it. Any missing tool makes the script print `preflight_missing: <keys>` and exit 1. `realpath` is security-critical, so it is never a degraded path.
- `python3` prints `DEGRADED:` and does not change the exit status.
- A configured L2 engine binary that is not found is `MISSING` too (key `l2_engine`).
- `AUTODREAM_PREFLIGHT_FORCE_MISSING` takes a comma-separated list of names to treat as absent. It exists for tests only and is unset in every real run.
- `--l2-bin` with no value exits 2. `shift 2` with one argument left fails and shifts nothing, so `$#` never decreases and the loop would spin forever. Preflight runs before the idempotency guard, so a wedged one would also block every launchd catch-up trigger behind the "label already running" rule. `oversized-gate.sh` validates `--days` for the same reason, where the bug had been observed: `--days` with nothing after it left `$#` at 1 and spun.

## Consequences

Adding a dependency means choosing hard stop or degraded on purpose: a hard stop for anything whose silent absence corrupts results, a warning only where the code already has a working fallback. `tests/preflight.sh` pins both paths.
