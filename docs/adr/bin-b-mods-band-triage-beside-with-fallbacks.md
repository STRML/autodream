# bin-b: default triage runs review.sh inline in a cmux split, with a fallback for each failure

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/register.tsx` (`triageBeside`, `runInNewSplit`, `triageInCmux`), `mods/autodream-band/hooks/lib.ts` (`triageCommandLine`, `surfaceRef`, `cmuxTriage`)

## Context

Triage in the current session derails whatever that conversation was about, so the default opens a fresh session beside it. `review.sh` normally hands off to a new cmux workspace; typed into a split it must instead fill that split. cmux's `new-split` and `send` default to the surface the session runs in. `new-split` prints a short ref (`surface:7`) or a UUID, and `send` reads a backslash-n in its text as Enter.

## Decision

- `triageCommandLine` runs `env AUTODREAM_TRIAGE_SURFACE=inline bash <script> [--force] <date>`, so the triage session fills the split instead of opening another workspace.
- `surfaceRef` reads the new split's address from `new-split`'s stdout (ref, else UUID). The command is sent as `<line>\n` with the two characters backslash and n.
- The cascade: no cmux or no review.sh means triage in this session; outside cmux (no `CMUX_SURFACE_ID`) there is nothing to split, so review.sh opens its own workspace; an unreadable split address or a failed send also falls back to the workspace, and the reply says so.
- `cmuxTriage` drives the workspace route through review.sh's documented knobs (`AUTODREAM_TRIAGE_SURFACE=cmux`, `AUTODREAM_TRIAGE_FOCUS=true`), so nothing in the user's autodream config changes.

## Consequences

The tests assert the exact argv of each step and the escaped newline. A change to cmux's output format or Enter convention lands in `surfaceRef` and the `send` text.
