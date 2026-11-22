# web: threads-render hands jq its state as a file, never on stdin

Status: accepted · Date: 2026-11-21 · Code: `bin/threads-render.py` (the status calculation call), `bin/portable.sh` (`tmo`)

## Context

The status filter runs `tmo 10 jq ...` through `portable.sh`. With no `timeout` binary on the host, `tmo` runs the command as a background job, and a background job's stdin is `/dev/null`. `tmo` now saves the caller's stdin on fd 3 and hands that to the job, but the renderer's own subprocess runs with `stdin=subprocess.DEVNULL`, so state piped on stdin would still reach jq empty.

## Decision

`threads-render.py` writes the state to a `NamedTemporaryFile` and passes its path as jq's input argument. Reading a named file does not depend on how `tmo` wires stdin.

## Consequences

Do not switch back to `input=` or a pipe to save the temp file. An empty jq result fails loudly (the renderer raises an invalid-JSON error), so a regression here shows up as an error, not an empty thread list.
