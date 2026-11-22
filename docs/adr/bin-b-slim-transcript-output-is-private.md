# bin-b: the slim output is mode 0600 even into a destination the caller already made

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (`umask 077`, the `chmod 600` on `$dst`)

## Context

Everything this script writes is derived from a session transcript, so none of it may be readable by another local account, whatever umask the caller has. `umask` only governs files this script creates: a destination the caller already made keeps its own mode through the redirects.

## Decision

`umask 077` covers the files created here, and the destination is truncated and `chmod 600` explicitly. The `.pre.jsonl` intermediate is created under the same umask.

## Consequences

`tests/slim-transcript.sh` checks that a destination made with mode 644 is tightened to 600 and its old contents are replaced.
