# tests-run-all: the foreign-cache-dir test creates the cache directory first, or its `..` case passes with the guard removed

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_changelog_refuses_foreign_cache_dir`)

## Context

The changelog code refuses to `rm -rf` a configured cache path that is not a clone inside `$AUTODREAM_DIR/cache`. One fixture reaches a foreign directory through `$ad/cache/../../sneaky`. If `$ad/cache` does not exist, `cache/..` never resolves, so `rm -rf` is a silent no-op whether or not the guard is there. The first version of this check passed with the guard removed for exactly that reason.

## Decision

The test runs `mkdir -p "$ad/cache"` before the run, and resolves `$ad` with `cd ... && pwd` so the path compared is the physical one the runner uses. The `..` source and the symlink source (`$ad/cache/link/old-repo`) each assert their target's `notes.txt` survives.

## Consequences

Remove the `mkdir` and the `..` assertion stops testing the guard. A change to how `cache_owns` resolves a missing parent must be rechecked against this case; CLAUDE.md ("An owned cache ignores the user's git config") records the nested-path rule and `test_changelog_nested_cache_path_is_owned_on_first_clone`.
