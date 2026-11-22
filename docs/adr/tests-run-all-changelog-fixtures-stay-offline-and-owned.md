# tests-run-all: changelog fixtures stay offline, and the owned-cache fixtures keep the shapes that make them test ownership

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_changelog_single_remote_suppresses_defaults`, `test_changelog_survives_a_force_pushed_remote`, `test_changelog_owned_cache_ignores_global_insteadof`, `test_changelog_nested_cache_path_is_owned_on_first_clone`)

## Context

`CHANGELOG_REMOTE` selects one source and suppresses the three default remotes (CLAUDE.md, "Upstream changelog window"). If the suppression broke, the suite would clone Claude Code, Codex and OMP from the network and still pass. A cache under `$AUTODREAM_DIR/cache` is owned: `changelog_git` ignores the user's git config for it. A repo outside the cache keeps that config. Each test below can pass with the ownership code deleted if its fixture is tidied.

## Decision

- The single-source test asserts that `^## Codex` and `^## OMP` are absent. That is the only check that the suite never reaches the network.
- The force-push test puts the cache under `$root/autodream/cache`. Only an owned cache follows a rewritten remote; a cache outside it keeps the conservative pull and would fail for the wrong reason.
- The insteadOf test serves with `uploadpack.allowFilter`, so the clone is a real `blob:none` partial clone and `git log -p` has to fetch blobs on demand through the same config. It never creates the cache dir, so a fresh install's first clone must count as owned too. It adds two commits before run 2. The reset checks out only the newest, so the middle commit's blob is never materialized and the lazy fetch is what reads it. Panel review of PR #173 found that with one extra commit every blob was already local and the lazy fetch went untested.
- The nested-path test plants a symlink inside the cache that points outside it, with the rest of the path missing. Walking up to the nearest existing directory must still resolve the link and refuse ownership.

## Consequences

Removing the `^## Codex` and `^## OMP` assertions, pre-creating the cache dir, dropping the middle commit, or making the symlink's target path exist turns the matching test into one that passes with the ownership code gone. The insteadOf fixture models the real host: `https://github.com/` rewritten to ssh with no key loaded, which failed every source on 2026-10-30 and 10-31.
