# runsh: Session rows come from the runner's own worklist and are held in memory before any model runs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`session_rows`)

## Context
L1 and L2 both run with the Write tool and `bypassPermissions`, so every file `session_rows` reads (`sessions.txt`, `sessions-source.txt` included) is one they could rewrite before the pins are applied. Outside the slim case a findings `session_path` is whatever the L1 model wrote, so reading it would let a transcript name another project's session and authorize memory there.

## Decision
`session_rows` emits one `hash<TAB>project<TAB>cwd` row per session in `sessions.txt`, the runner's own worklist, and never reads a findings JSON. `run.sh` calls it before the first model call and holds the result in memory. The rows feed `pin_projects_from_rows` (the pin authorization list) and the findings project normalization, which looks each findings file up by hash. A missing worklist returns failure, because it would otherwise read as "no projects" and refuse every pin silently.

A cwd is unusable, recorded as `?`, when the adapter cannot resolve it (usually a removed worktree), when it holds a tab or newline, or when its bucket is an encoded path (starts with `-`) that the cwd does not encode to. Slug buckets from `CLAUDE_CODE_PROJECT_DIR_NAME` (`owner-repo`) skip that encoding check, because no cwd ever encodes to a slug. An adapter cwd is always absolute, so it can never be `?` itself.

See CLAUDE.md, "Where state lives" (`pin-projects.tsv`, `session-cwds.tsv`).

## Consequences
Never source project or cwd from a findings JSON. A new consumer of project or cwd reads these in-memory rows.
