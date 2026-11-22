# bin-b: threads.sh hands the status filter its state as a file, never on a pipe

Status: accepted · Date: 2026-11-21 · Code: `bin/threads.sh` (`threads_render_unlocked`), `bin/portable.sh` (`tmo`)

## Context

With no `timeout` binary, `tmo` backgrounds the command, and a background job's stdin is `/dev/null`. Piped state vanishes and jq exits 0 with no output. The same constraint is recorded for the Python renderer in `docs/adr/web-threads-render-state-file.md`.

## Decision

`threads_render_unlocked` writes the state to a `mktemp` file, passes its path to `threads_status_jq`, and removes it afterward.

## Consequences

Do not switch to a pipe or here-string to save the temp file. An empty result is an error here, not an empty thread list.
