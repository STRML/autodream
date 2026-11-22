# bin-b: rollup takes each session's source, project and cwd from the runner's environment, not from files a worker can write

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`join_source_parent`, awk `sandbox()`)

## Context

An L1 worker holds the Write tool and can rewrite `sessions-source.txt`, and a findings JSON's `project` field is model output. The `source` column and the sandbox flag must not depend on either. Trigger evals from the skill-creator run `claude -p` from `/private/var/folders/<x>/<y>/T/trig-<id>/repo`; 32 of 45 projects on 2026-11-17 were such runs, and they must not rank like real work.

## Decision

- The source comes from `AUTODREAM_SOURCE_MAP` (hash, adapter) when the runner passes it, since the runner built that map before any model ran. `sessions-source.txt` is the fallback for a standalone run.
- `AUTODREAM_SESSION_ROWS` holds hash, project and cwd rows the runner built from the session paths. `?` means the cwd is unknown. A hash in these rows is trusted: its cwd decides `sandbox`, matched against `^/private/var/folders/.+/T/trig-[^/]+(/repo)?$`.
- Only an unknown cwd falls back to the project key: the runner's key for the session, else the row's own (blank when the findings JSON does not parse). The key is matched against `^-private-var-folders-.+-T-trig-[A-Za-z0-9_-]+$`. The trial dirs are deleted after a run, so the cwd is often unresolvable and the key decides.
- Both patterns are anchored at both ends. An ordinary checkout at `/Users/x/T/trig-parser` encodes to a key that contains `-T-trig-` and is not a sandbox.
- The first row for a hash wins, in both the source map and the session rows.

## Consequences

CLAUDE.md, "Where state lives" (the `sandbox` column), records the same rule. A harness whose sessions have no row falls through to the row's own project key. `tests/rollup.sh` covers the cwd, the key fallback and the anchoring.
