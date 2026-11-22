# bin-b: vault-notes resolves its install dir and sources the config the way run.sh does

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (the `resolve_install_dir` call, the config-source block)

## Context

A hard-coded `$HOME/.claude/autodream` made the writer and the reader disagree whenever an install lived elsewhere. vault-notes takes `AUTODREAM_DIR` from the launchd plist, so every note landed in a file the nightly never opened, with no error and no missing-note report.

`status` is run by hand. A `status` that says "vault: not configured" about a vault the user configured is worse than no `status`.

## Decision

- The install dir comes from `resolve_install_dir`: the environment first, else the script's own directory when it carries an install marker, else the legacy default with a warning. `BASH_SOURCE` stays unresolved on purpose, because `install.sh` symlinks the scripts into `$TARGET`, so the link's directory is the install dir.
- `portable.sh` and `lib-install-dir.sh` are found next to the script first, then next to the symlink target, because a merge updates the installed links before `install.sh` links a new helper.
- The config is sourced here as well as in `run.sh`, under `set +u` (the same reason `run.sh` does it: a typo'd variable in the user-edited config would abort the script under `nounset` and cost a night's notes) with the caller's exports replayed from an `export -p` snapshot afterwards. Double-sourcing is harmless because `run.sh` has already exported these values. `run.sh` warns about the typo, and staying quiet here avoids the same complaint twice.

## Consequences

CLAUDE.md, "run.sh sources the config now", states the `set -a` and snapshot rules. A new variable this script reads from the config works for `status` run by hand only because of this block.
