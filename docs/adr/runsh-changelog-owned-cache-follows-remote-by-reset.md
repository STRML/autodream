# runsh: an owned changelog cache follows its remote with fetch and reset --hard, a foreign repo keeps pull --ff-only

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_sync`)

## Context

`git pull --ff-only` failed forever once a fork was rebased and force-pushed. The OMP fork is rebased on every upstream sync, so the section read "pull failed" every night. A cache this install owns is disposable. A repo outside the cache (a `CLAUDE_CODE_REPO` checkout) may hold someone's work.

## Decision

For an owned cache `changelog_sync` runs `fetch --quiet origin` then `reset --hard --quiet FETCH_HEAD` (both through `changelog_git yes`). For a foreign repo it runs the conservative `git pull --ff-only --quiet`, because resetting it would discard someone's work.

## Consequences

Do not use `reset --hard` on anything `cache_owns` has not approved (see `changelog-cache-ownership-resolved-physically`). A fork that is rebased makes `pull --ff-only` the wrong tool for any cache we own.
