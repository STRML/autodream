# runsh: a changelog cache is "owned" only when its path resolves physically inside the install's cache directory

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`cache_owns`, `changelog_clone`, `changelog_window`)

## Context

Ownership gates two things: `rm -rf` of a cache path before cloning, and running git without the user's config. `AUTODREAM_CHANGELOG_SOURCES` names the path, so a typo pointing at a real non-git directory must not be deleted to make room for a clone (debate review of e95e2f2). The path as written proves nothing: `$AUTODREAM_DIR/cache/../x` matches the prefix, and so does `$AUTODREAM_DIR/cache/link/x` where `link` points elsewhere, and `rm -rf` follows both (Codex review of 0129fc0). A nested source such as `cache/nested/source` must be owned on its first clone (#174).

## Decision

`cache_owns` refuses any path containing `..`, resolves `$AUTODREAM_DIR/cache` with `pwd -P`, then walks up from the path's parent past names that do not exist at all (neither a file nor a symlink, so a dangling symlink is still resolved or refused), resolves that nearest existing ancestor physically and tests that it sits under the cache. With no `..`, what `clone` creates below that ancestor stays below it. `changelog_clone` clears the repo directory only when owned; outside the cache nothing is deleted, a non-empty non-git directory is refused with a failure section, and `git clone` accepts a missing or empty target. `changelog_window` creates `$AUTODREAM_DIR/cache` first, because `cache_owns` resolves that directory as the root every owned path must sit under, so on a fresh install the first clone would otherwise count as foreign and run with the user's git config.

## Consequences

`test_changelog_refuses_foreign_cache_dir` pins that a non-git directory, a path that climbs out with `..` and a path through a symlink inside the cache are never deleted. `test_changelog_nested_cache_path_is_owned_on_first_clone` pins the nested case and a symlink out of the cache with a missing remainder behind it. Do not replace the physical resolve with a prefix test.
