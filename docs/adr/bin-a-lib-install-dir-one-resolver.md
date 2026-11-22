# bin-a: one resolver decides the install dir, from the script's unresolved path

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-install-dir.sh` (`resolve_install_dir`)

## Context

Six scripts each carried their own copy of the resolver, and the copies drifted (#112). They disagreed on which files prove a directory is an install, on whether to warn, and one never looked at its own location at all. The writer and the reader of the operator notes disagreed on the directory the moment an install lived anywhere but `~/.claude/autodream` (#91), and every note landed in a file the nightly never opened, with no error.

One of the two markers some copies tested, `l1-no-advisor.yml`, came from the OMP install, and nothing in this repo installs it.

## Decision

A script sources the helper and calls `resolve_install_dir "${BASH_SOURCE[0]}" [NAME]`. It sets `AUTODREAM_DIR` and does not export it:

1. An `AUTODREAM_DIR` already in the environment wins.
2. Otherwise the directory the script sits in, when it holds `config` (written by `install.sh`) or `PROMPT.md` (one of its symlinks). The caller's `BASH_SOURCE` stays unresolved on purpose: `install.sh` symlinks each script into `$TARGET`, so the link's own directory is the install dir, while the resolved path is the repo. No marker lives in the repo's `bin/`, so running from a checkout never mistakes `bin/` for an install.
3. Otherwise the legacy default `~/.claude/autodream`. With `NAME` it prints `NAME: WARNING ...` on stderr; without it the fallback is silent, which is what the scripts that never warned (`autodream-now.sh`, `notify.sh`, `question-streaks.sh`) keep.

## Consequences

A new caller passes `BASH_SOURCE[0]`, not a resolved path, or it finds the repo and falls back to the default. Adding a marker is one line here. CLAUDE.md, "State locations" and `tests/install-dir.sh` pin the callers.
