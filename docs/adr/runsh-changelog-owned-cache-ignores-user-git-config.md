# runsh: every git call on an owned changelog cache runs with no user or system git config

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_git`)

## Context

An owned cache reads a public remote. This host's `~/.gitconfig` rewrites `https://github.com/` to `git@github.com:` (`url.git@github.com:.insteadOf`), and with no key loaded all three sources failed on 2026-10-30 and 10-31 while anonymous https worked. Fixing only the fetch is not enough: the caches are `blob:none` partial clones, so reset and `git log -p` fetch missing blobs from the same remote on demand through the same config, and a failure there reads as a quiet night. See CLAUDE.md, "Upstream changelog window".

## Decision

`changelog_git yes <args>` runs `git` with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0`. Every call on an owned cache (fetch, reset, clone, sparse-checkout, rev-parse, `log -p`) goes through it, not just fetch and clone. A repo outside the cache is someone's checkout and keeps their config (`changelog_git no`).

## Consequences

A private remote whose token comes from a credential helper in `~/.gitconfig` cannot be read from an owned cache; point such a source's cache path outside `$AUTODREAM_DIR/cache`. `test_changelog_owned_cache_ignores_global_insteadof` pins it, and its second run reads a commit whose blob no checkout fetched, so the lazy fetch is what it tests. A new git call on a source's repo must use `changelog_git`.
