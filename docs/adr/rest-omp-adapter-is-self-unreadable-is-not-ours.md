# rest: omp is-self exits 3 on an unreadable file instead of answering not-ours

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`is-self`)

## Context

`is-self` asks whether a transcript is one of autodream's own (the self-pollution filter in CLAUDE.md, "Self-pollution"). The shared predicate answers "not ours" for a file it cannot read. That is exactly the answer a real user session gets, so an unreadable autodream transcript would be triaged as the user's work.

## Decision

The verb checks `[ -r "$1" ]` first and exits 3 when it fails, the same readability guard as every sibling adapter. Only then does it `exec prune-self-sessions.sh --is-self`.

## Consequences

The caller must treat 3 as "cannot tell", not as "not ours". Removing the guard silently lets own-transcripts through whenever a permission problem makes one unreadable.
