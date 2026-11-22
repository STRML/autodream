# runsh: the L1 dispatcher hands each session path to its worker NUL-delimited, one argument per worker

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1`)

## Context
`xargs -I {}` turned a tab into a space, deleted a backslash and died on a quote with "unterminated quote", taking the whole night's dispatch with it (#54). `-I` also caps the substituted argument at 255 bytes.

## Decision
`tr '\n' '\0' < "$SESSIONS_LIST" | xargs -0 -n 1 -P "$FANOUT" bash -c '...' _` passes each path byte for byte as `$1`. `-n 1` without `-I` lifts the 255-byte limit. A newline cannot reach the list because enumeration refuses it (`sessions.txt` is line-based).

## Consequences
Do not return to `-I {}`. A new field in `sessions.txt` that could hold a newline breaks the invariant that makes the `tr` safe. See CLAUDE.md, "Which day a session belongs to".
