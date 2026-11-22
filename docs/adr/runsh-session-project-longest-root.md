# runsh: A session's project is the directory under the longest root that holds it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`session_project`)

## Context
Claude nests transcripts at several depths under one bucket (`<bucket>/<session>.jsonl`, `<bucket>/<session>/subagents/agent-*.jsonl`, `<bucket>/<session>/subagents/workflows/wf_*/agent-*.jsonl`), and a bucket can itself be named `subagents`, so no rule based on directory names finds the bucket at every depth. Roots can also nest (`/c` and `/c/projects`).

## Decision
Of the adapter's roots (`adapter_roots`), the longest one that holds the session as `root/<bucket>/<something>` (a trailing `/` on a root is ignored) wins, and the project is the first path component below it. A session under none of the adapter's roots falls back to its parent directory's name.

## Consequences
Do not replace this with a directory-name heuristic. A session under a nested root names `<bucket>`, not `projects`.
