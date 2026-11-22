# rest: the omp project verb reads the cwd from the session header or autodream_meta with jq

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`project`)

## Context

The runner needs a session's real working directory. An omp raw session carries it in its `session` header record. A linearized copy carries it in `autodream_meta`. The runner can hand the verb either shape. A cwd with a quote or a backslash is JSON-escaped on the line, so a regex over the raw line truncates it. The claude adapter made the same choice (`bin-a-adapter-claude-project-cwd-by-jq.md`).

## Decision

`jq -re` selects the first record whose `.type` is `session` or `autodream_meta` and whose `.cwd` is a string, takes the first result, and the verb prints its `realpath`. An unreadable file, no such record or an unresolvable path exits 1 with nothing printed.

## Consequences

A grep-based reader would pass a plain path and fail on exactly the paths that need escaping. Dropping `autodream_meta` from the selection breaks `project` on every normalized copy.
