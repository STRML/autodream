# bin-a: overlap counts distinct parent-session pairs from sidecars, and drops advisor and nested-worker sidecars

Status: accepted · Date: 2026-11-21 · Code: `bin/overlap-stats.sh` (`build_session_list`, the `has_overlap` jq function)

## Context

GitHub issue #14 asked for a model-free, cross-session pass that counts how many session pairs had a user turn within 30 minutes of each other (the same human working two sessions at once). The unit is pinned to seconds and the default window is 1800.

Two exclusions exist because the first versions measured nothing:

- An OMP advisor sidecar is a reviewer model tailing its parent session, so it inherits the parent's user-turn timestamps by construction and overlaps it 100% of the time. Including advisors made the stat read 90-of-90 sessions on 2026-08-19 and 629-of-629 on 2026-08-20. A measure that fires on every session carries no information.
- A subagent or workflow worker behaves the same way (#79). Its transcript is a separate file inside its parent's directory, with timestamps inside the parent's span and inside every sibling's. A 30-worker fanout paired every worker with its parent and with each other, and 2026-09-08 read "78 of 72 sessions".

## Decision

- `overlap_events` is the number of distinct unordered session-id pairs `{A,B}` such that some user turn of A and some user turn of B fall within the window. A pair counts once however many turn pairs qualify. `sessions_with_overlap` is the number of distinct ids in at least one such pair.
- Session identity is the sidecar's filename stem, the 12-character sha1 of the session path that `run.sh` already uses as the findings key. It is stable and needs no re-derivation from `session_path`.
- Sidecars with `is_advisor: true`, `isSidechain: true` (a claude worker) or `nested: true` (an omp child) emit no line at all, so the stat counts concurrency between parent sessions. The flags are absent on older sidecars and `null != true` keeps those, so old findings dirs pair exactly as before.
- Gated sessions stay in. The noise gate runs after `compute_session_stats` has written every sidecar, and a gated session is real concurrent human activity that was not worth triaging, whereas an advisor pair is the same activity counted twice. The script cannot see the gate decision and does not care about it. The stat therefore includes every gated top-level session, which the Activity snapshot's session total leaves out, and PROMPT.md says so beside the figure.
- A missing or empty `user_turn_timestamps` (pre-#14 sidecars, sessions with no timestamped user turn) becomes `[]` and cannot form a pair; `has_overlap` short-circuits on an empty array.
- `has_overlap` is a two-pointer sweep over two sorted epoch-second arrays, O(|a| + |b|), and deliberately not a cross product, since a long session can carry hundreds of user-turn timestamps.
- The script never fails the caller: a missing or empty findings dir yields `{"overlap_events":0,"sessions_with_overlap":0}`.

## Consequences

`run-stats.txt` carries `overlap_measured: yes|no` so a run where this pass did not run is not read as zero overlap (CLAUDE.md, "Degraded measurements must say so"). A new kind of derived transcript that shares its parent's timestamps needs its own exclusion here, or the stat saturates again.
