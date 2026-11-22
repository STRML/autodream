# bin-b: PATH entries under a temp directory never reach the launchd plist

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`ephemeral_dir`, `install_schedule`)

## Context

A directory under a temp location belongs to the shell that ran the installer: a tool shim (cmux puts `$TMPDIR/cmux-cli-shims/<uuid>` first on PATH in every terminal it opens) or a per-session scratch dir. It is gone by the time launchd runs the job, so a PATH entry or a `CLAUDE_BIN` taken from one rots the schedule with no error. CLAUDE.md, "What goes in the plist PATH", records the incident on a real host.

## Decision

`ephemeral_dir` matches a directory against a prefix list (`$TMPDIR`, `/tmp`, `/private/tmp`, `/var/folders`, `/private/var/folders`), comparing physical paths. `install_schedule` drops matching entries from `PATH` first and resolves every tool against what is left, naming what it skipped. `AUTODREAM_EPHEMERAL_DIRS` replaces the list; set but empty it turns the check off, which the install test suites need because their fake tools live under `TMPDIR`. A development build under `DerivedData` is not ephemeral.

## Consequences

Any new place the installer takes a binary path from must go through the same check (`config_bin_dir` does).
