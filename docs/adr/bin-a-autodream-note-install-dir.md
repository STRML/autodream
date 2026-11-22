# bin-a: autodream-note.sh resolves its install dir like the reader of the notes file does

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-note.sh` (the `resolve_install_dir` call, `NOTES`)

## Context

The writer of `notes.md` and its reader must agree on one directory. `autodream-note.sh` once hard-coded `$HOME/.claude/autodream`, while `vault-notes.sh` takes `AUTODREAM_DIR` from the launchd plist. The moment an install lived anywhere else, every note landed in a file the nightly never opened. There was no error and no missing note reported (#91, #112; `bin/lib-install-dir.sh` carries the resolver).

## Decision

The script calls `resolve_install_dir` with its own name: the environment first, else the script's own directory when it carries an install marker (`install.sh` writes `config` and links `PROMPT.md`), else the legacy default with a warning. `BASH_SOURCE` stays unresolved on purpose, because `install.sh` symlinks the scripts into `$TARGET`, so the link's directory is the install dir. `AUTODREAM_NOTES_FILE` overrides the file itself.

## Consequences

`bin-b-vault-install-dir-and-config-like-run-sh.md` records the reader's side of the same rule, and `bin-b-install-helper-link-fallback.md` the symlink-target fallback for `lib-install-dir.sh`. `tests/notes-path.sh` and `tests/install-dir.sh` pin the agreement.
