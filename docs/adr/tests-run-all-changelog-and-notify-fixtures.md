# tests: run-all-changelog-and-notify-fixtures: run-all: changelog and notify fixtures

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_changelog_single_remote_suppresses_defaults`, `test_changelog_survives_a_force_pushed_remote`, `test_changelog_owned_cache_ignores_global_insteadof`, `test_changelog_nested_cache_path_is_owned_on_first_clone`), `tests/run-all.sh` (`test_changelog_refuses_foreign_cache_dir`), `tests/run-all.sh` (`test_notify_count`), `tests/run-all.sh` (`test_notify_count`, `test_notify_open_command`, `test_notify_dryrun`)

## changelog fixtures stay offline, and the owned-cache fixtures keep the shapes that make them test ownership

### Context

`CHANGELOG_REMOTE` selects one source and suppresses the three default remotes (CLAUDE.md, "Upstream changelog window"). If the suppression broke, the suite would clone Claude Code, Codex and OMP from the network and still pass. A cache under `$AUTODREAM_DIR/cache` is owned: `changelog_git` ignores the user's git config for it. A repo outside the cache keeps that config. Each test below can pass with the ownership code deleted if its fixture is tidied.

### Decision

- The single-source test asserts that `^## Codex` and `^## OMP` are absent. That is the only check that the suite never reaches the network.
- The force-push test puts the cache under `$root/autodream/cache`. Only an owned cache follows a rewritten remote; a cache outside it keeps the conservative pull and would fail for the wrong reason.
- The insteadOf test serves with `uploadpack.allowFilter`, so the clone is a real `blob:none` partial clone and `git log -p` has to fetch blobs on demand through the same config. It never creates the cache dir, so a fresh install's first clone must count as owned too. It adds two commits before run 2. The reset checks out only the newest, so the middle commit's blob is never materialized and the lazy fetch is what reads it. Panel review of PR #173 found that with one extra commit every blob was already local and the lazy fetch went untested.
- The nested-path test plants a symlink inside the cache that points outside it, with the rest of the path missing. Walking up to the nearest existing directory must still resolve the link and refuse ownership.

### Consequences

Removing the `^## Codex` and `^## OMP` assertions, pre-creating the cache dir, dropping the middle commit, or making the symlink's target path exist turns the matching test into one that passes with the ownership code gone. The insteadOf fixture models the real host: `https://github.com/` rewritten to ssh with no key loaded, which failed every source on 2026-10-30 and 10-31.

## the foreign-cache-dir test creates the cache directory first, or its `..` case passes with the guard removed

### Context

The changelog code refuses to `rm -rf` a configured cache path that is not a clone inside `$AUTODREAM_DIR/cache`. One fixture reaches a foreign directory through `$ad/cache/../../sneaky`. If `$ad/cache` does not exist, `cache/..` never resolves, so `rm -rf` is a silent no-op whether or not the guard is there. The first version of this check passed with the guard removed for exactly that reason.

### Decision

The test runs `mkdir -p "$ad/cache"` before the run, and resolves `$ad` with `cd ... && pwd` so the path compared is the physical one the runner uses. The `..` source and the symlink source (`$ad/cache/link/old-repo`) each assert their target's `notes.txt` survives.

### Consequences

Remove the `mkdir` and the `..` assertion stops testing the guard. A change to how `cache_owns` resolves a missing parent must be rechecked against this case; CLAUDE.md ("An owned cache ignores the user's git config") records the nested-path rule and `test_changelog_nested_cache_path_is_owned_on_first_clone`.

## the notify count fixtures include the incident shape and the "None" lead-in

### Context

`notify.sh` counts open questions from the `autodream:open-questions=N` marker and falls back to the section's shape for reports without one (`docs/adr/bin-a-notify-count-from-marker.md`).

### Decision

- The first fixture is the real 2026-07-24 shape: one numbered question, then a list of findings dropped by the gate. The old counter scored 6 for it and the marker says 1. The test asserts the marker wins over the six list lines.
- The no-marker fixture holding only a "None that clear the triviality gate" line stays in the suite. Without it, the bare-prose tier would turn every quiet pre-marker night into a false pop-up.

### Consequences

Replacing the first fixture with a plain numbered list stops it distinguishing the marker from the shape-based count. Deleting the "None" case lets a prose-tier regression through unnoticed.

## notify tests stub the branded notifier before any call that can post, and record argv one per line

### Context

`bin/notify.sh` resolves the branded notifier bundle first. With none present, resolution falls through to a system `terminal-notifier` and posts for real. Pointing `AUTODREAM_DIR` at a temp dir is not enough to avoid that. While `test_notify_dryrun` was being written without the stub, the suite posted a live notification for a fixture dated 2020-04-01.

### Decision

- Every call that can reach the posting code runs with an executable stub at `$root/cc-autodream.app/Contents/MacOS/terminal-notifier`. `AUTODREAM_NOTIFY_OSA_BACKUP=0` turns off the osascript fallback, and `SUBL=/usr/bin/true` stops an editor from opening.
- The dry-run assertions run with no stub on purpose. A dry run has to be safe without any stubbing. The stub is added only before the follow-up call without the flag, which proves the guard is not just off.
- The fake editor logs each argument on its own line, so the test can count arguments and prove word-splitting and quoting. Exit status alone would not show a path with a space being split.

### Consequences

Seeding the stub before the dry-run calls hides a dry run that posts. Removing it before the wet call posts a real banner. Logging with `echo "$@"` merges arguments and makes the "exactly two arguments" and "single argument" assertions meaningless.
