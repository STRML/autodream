# rest: an L1 worker runs under an OS sandbox that denies every write except its staging directory

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`emit_prefix`, `sb_profile`, `tool_for`)

## Context

An L1 worker holds the Write tool, so until #169 it could write any path the user can: another session's findings, a chunk answer before the runner checked it, a new `*.json` in the findings dir, `$AUTODREAM_DIR/config`. No check on the files in the findings dir can tell the runner's writes from a worker's, because the worker can forge any marker the runner could leave. So the access is what changes, not the validation.

## Decision

The runner makes a staging directory per answer (`run.sh` does that, not this helper), tells the worker to write its answer there, runs the engine under an OS sandbox that can write only that directory plus the narrow list of state paths the engine itself needs, and copies the answer into the findings dir after the engine has exited. `bin/l1-confine.sh` builds the sandbox around the stage and is the only place that knows the two tools:

- `sandbox-exec` (macOS) gets a profile of `(allow default)` then `(deny file-write*)`, a short allow list of `/dev` nodes (`/dev/null`, `/dev/tty`, `/dev/dtracehelper`, `/dev/stdout`, `/dev/stderr`, `/dev/fd/N`), the writable paths, the protected paths as later denies, and the stage allow last so it wins inside a protected directory.
- `bwrap` (Linux) gets a read-only bind of `/` and read-write binds of the same list.
- `L1_CONFINE_TOOL=sandbox-exec|bwrap` picks the tool; unset prefers `sandbox-exec`, then `bwrap`; any other value is refused. A named tool that is not on PATH yields no prefix.

The profile denies writes only. Reads, the network and process exec are unchanged: the engine must read transcripts and reach its provider, and read access is not what #169 is about.

The subcommands are `probe`, `prefix <stage> [writable-path ...]` and `engine-prefix <adapter.sh> <stage>`; `prefix` prints a NUL-delimited argv to put in front of the engine command. A writable path is a directory (`subpath`), or a prefix when it ends in `*` (`~/.claude.json` and, under `sandbox-exec`, the temp files claude renames over it).

## Consequences

Setup and every worker call build the same prefix from the same list, so a list that cannot be confined is found before a worker starts (see `runsh-l1-confine-setup-fails-fast`). The bwrap limit on prefix rules is in `runsh-l1-confine-bwrap-prefix-rule-limit`. The write list and the work-bucket decision are in `bin-a-adapter-claude-l1-writes-default-deny` and `runsh-l1-work-bucket-not-on-confine-write-list`; the runner side is `runsh-l1-write-confinement-staging` and CLAUDE.md, "A worker writes only its staging directory (#169)" and "What the sandbox allows". Widening the deny to reads or the network would break the engine; widening the allow list grants every worker the same write, so add a path only with a measurement (`tests/l1-confine-real.sh --measure`).
