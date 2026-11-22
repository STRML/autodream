# bin-b: install.sh never links over a missing source or a real directory, and says so

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`link`)

## Context

- A link to a file the checked-out tree does not have looks installed and does nothing at 03:15. That is the overlap-stats.sh dangle of 2026-07-24, which cost a night of data.
- `adapters/` was the first directory the installer links. With a real directory at the destination, `ln -s` silently creates `$dst/<basename>` (a nested `adapters/adapters`) and prints the same success line. The loader then finds an empty directory, rejects the nested link on containment, and every nightly run fails.
- Warning and returning 0 on that case reported a successful install while `adapters_root()` pointed at a directory the loader accepts nothing from: the "loader accepted no adapters" fatal on every nightly afterward, a total outage behind one line of output.

## Decision

- A missing source is a loud warning, the old link is left alone, and `link` returns 0 (one stale helper must not abort the rest of the install).
- A non-empty real directory at the destination, or one that cannot be removed, is a hard failure (`return 1`). An empty one is removed and linked. The dry run applies the same non-empty check, so it reports the refusal a real install would hit.

## Consequences

Adding a directory link means it inherits this refusal. Do not downgrade the directory case to a warning to make an install "succeed": the failure moves to 03:15.
