# tests-review-cmux: the dedup token is written when cmux exits 0, and nothing else can override it

Status: accepted · Date: 2026-11-22 · Code: `tests/review-cmux.sh` (`test_force_bypasses_marker`, `test_confirmed_marker_survives_grace`, `test_missing_claude_preflights`, `test_missing_shasum_fails_closed`, `test_empty_ref_still_confirms`), `bin/review.sh`

## Context

The scheduled review job fires several times a day, and a second workspace for the same report is the failure to prevent. `review.sh` keeps two markers under `$LOGS_DIR`:

- the claim dir `review-launched-$DATE-$DIGEST`, made with an atomic `mkdir`;
- the sibling token `review-launched-$DATE-$DIGEST.confirmed`, written only after cmux returns success.

Dedup keys on the token. An unconfirmed claim older than the 900 second grace is an abandoned launch and gets reclaimed. A review round found that gating the token write on having claimed the dir left a first `--force` run without a token, so the next scheduled trigger opened a duplicate.

## Decision

- `--force` stamps its own token on a first-ever run, and that token dedups the next routine trigger.
- cmux exit 0 is the creation contract. The token is written even when the stdout ref does not parse. A kill between create and confirm, or a change in cmux's output format, must never let the age-based reclaim open a duplicate. An empty ref costs only the cosmetic tab rename.
- A workspace whose embedded claude cannot start is a dead end that the token would then dedup forever. The script preflights the exact `CLAUDE_BIN` path it passes into the workspace and writes no token when it is missing.
- The digest comes from `shasum`. If `shasum` is missing the script exits non-zero instead of falling back to a seconds-resolution mtime, which reintroduces same-second collision dedup bugs.
- `test_confirmed_marker_survives_grace` ages the pair by two days: past the 900 second grace, under the 14 day prune. A naive reclaim would misfire there, and the unconditional 14 day reap does not delete the fixture. Aging past 14 days would pass the test for the wrong reason.

## Consequences

Keep the fixture ages between 900 seconds and 14 days. The abandoned-claim test uses the same window.
