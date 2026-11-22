# web: threads-render hands jq its state as a file, never on stdin

Status: accepted · Date: 2026-11-21 · Code: `bin/threads-render.py` (the status calculation call)

## Context

The status filter runs `tmo 10 jq ...` through `portable.sh`. With no `timeout` binary on the host, `tmo` runs jq as a background job, and a background job's stdin is `/dev/null`. State piped on stdin vanishes, and jq exits 0 with no output, which reads as an empty thread list rather than an error.

## Decision

`threads-render.py` writes the state to a `NamedTemporaryFile` and passes its path as jq's input argument. The subprocess itself gets `stdin=subprocess.DEVNULL`.

## Consequences

Do not switch back to `input=` or a pipe to save the temp file. The failure is silent, so a test that pipes on a host with `timeout` installed passes and misses it.
