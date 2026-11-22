# rest: omp nested and advisor provenance comes from the path, and the meta record carries it forward

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/linearize.sh`, `adapters/omp/stats.sh`

## Context

A child omp session lives in a directory named after its parent file:

```
<bucket>/<stamp>_<id>.jsonl            parent
<bucket>/<stamp>_<id>/__advisor.jsonl  child (advisor)
<bucket>/<stamp>_<id>/<Name>.jsonl     child (task subagent)
```

An advisor child has no user turns and no `session_init`, so the entries cannot say what it is. The filename of a normalized temp copy says nothing either, and a linearized copy lives in the runner's work directory where "my directory plus `.jsonl` is a file" is false.

A child whose parent file is gone (deleted or archived) is still a child. Its directory is named like a session file (`<ISO stamp>_<id>`), and a project bucket never is, because a bucket is a dash-encoded path. The shape of the directory name answers without the parent.

omp reserves two stems, `__advisor.jsonl` and `__advisor-<name>.jsonl`, for a reviewer model that tails a primary session. It is an observability record and not an agent session, with a read-only toolset, so `Tool "bash" not available` is its normal shape. Its calls are `toolCall` content blocks and not `tool_execution_start` records.

## Decision

`linearize.sh` derives `nested`, `parent` and `is_advisor` from the path (parent file exists, or the directory name has the session-file shape, or the basename is one of the two advisor stems) and records them in `autodream_meta`. `stats.sh` ignores that record in every count and reads the flags from it. For a raw file it applies the same path rules itself: advisor from its own name, nested from the parent file or the directory shape.

The same rule is therefore written twice, once in `linearize.sh` and once in `stats.sh`.

## Consequences

A change to one copy must change the other. `tests/adapter-omp.sh` pins both against `__advisor-<name>.jsonl` and the nested cases. Do not derive these flags from entry contents. See also `tests-adapters-omp-stats-and-overlay` and CLAUDE.md, "The OMP adapter" (nested sessions are real sessions).
