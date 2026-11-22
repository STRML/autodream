# bin-b: a cmux triage launch is deduplicated by a claim directory plus a confirmed token bound to the report's digest

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (cmux branch: `REPORT_KEY`, `LAUNCH_MARKER`, `LAUNCH_CONFIRMED`, `CLAIM_GRACE`)

## Context

`install.sh` provisions the review job with five triggers a day (08:00, 09:15, 12:15, 15:30, 18:15). Whichever fires first after the report lands opens the workspace, and later ones for the same report must not open a second.

## Decision

- **Key by content digest, not mtime.** mtime has one-second resolution, so a same-second rebuild would share a marker and its triage would be swallowed. A rebuild with `AUTODREAM_FORCE=1` has new content, so it invalidates the old marker. A missing `shasum` is a hard error (the key is checked for emptiness, since the assignment's status is awk's); an empty key would collapse every report of that day into one marker.
- **Claim by `mkdir`**, which is atomic, so two overlapping triggers cannot both pass. A failed `mkdir` where the directory now exists is a genuine race (exit 0). Where it does not exist it is an I/O error (exit 1), because reporting it as "in progress" silently drops triage.
- **The confirmed token is a sibling file**, not inside the claim directory. The stale reap uses `find -delete`, which cannot remove a non-empty directory, and both names still match the `review-launched-*` prune glob. Claims and tokens older than 14 days are reaped, including on `--force`, since that is the retry-after-failure route.
- **A claim with no token** younger than `CLAIM_GRACE` (900 s) is an in-flight launch. An older one is abandoned (a killed process) and is reclaimed, so a dead popup cannot suppress triggers forever.
- **The token is bound to the launch-time digest and stamped as soon as cmux returns 0**, before any output parsing. The workspace reads the report path when it starts, so the parent cannot know which bytes it read. Re-hashing after the create could mark a rebuilt report B confirmed when the workspace triaged A, swallowing B's questions. Bound to A, B has no token and its own trigger surfaces it. The worst case is a duplicate popup, never a lost triage. A failed `touch` is a warning, not a failure, because the workspace exists.
- **A failed create releases the claim only if this process owns it or it is past the grace window.** A `--force` run never claims, so it must not delete a live claim of a concurrent normal run, but it does release a stale one.

## Consequences

Changing the key, the token location or the grace window changes what `tests/review-cmux.sh` pins. Do not re-hash the report after launch.
