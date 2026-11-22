# bin-a: the claude adapter reads a session's cwd with jq, never grep

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`project`)

## Context

A cwd containing a quote or a backslash is JSON-escaped in the transcript. A regex over the raw line either truncates at the escaped quote or hands `realpath` a doubled backslash.

## Decision

`project` extracts `.cwd` with `jq -re` and resolves it with `realpath`. A session with no cwd or an unresolvable one exits 1, which the runner counts as an unusable cwd for pin authorization.

## Consequences

`bin/apply-pins.sh` authorizes a pin only for a project whose cwd resolves here, so a parsing shortcut in this subcommand would silently change which projects can receive pins.
