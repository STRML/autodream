# bin-a: an L1 worker may write only its staging directory plus a default-deny list that holds the CLI's own cache

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`l1-writes`, `nl_refuse`)

## Context

`run.sh` runs the worker under an OS sandbox that can write nothing else (#169, `bin/l1-confine.sh`), so this list is the whole of what the claude CLI may touch of its own. The table, the measurement and the procedure for a confined call that fails without something are in `docs/plans/2026-11-21-l1-confine-write-list.md`; CLAUDE.md, "What the sandbox allows", summarizes it.

## Decision

Default deny: a path is listed only because a confined call needs it or because it is a cache no later run executes. Today that is the CLI's own cache (`~/Library/Caches/claude-cli-nodejs`, `~/.cache/claude-cli-nodejs`), which holds logs and nothing read as code. Deliberately not listed, each a way for a prompt-injected worker to run code as the user later: `~/.claude.json` and its backups (`mcpServers`, `allowedTools`, `enabledMcpjsonServers`), the config dir's settings, hooks, skills and plugins, `session-env` (sessionstart-hook env files a live session sources), and the CLI's install dir (auto-update writes executables there). The isolated work bucket, where an AI-title stub lands, is not listed either: it is the one directory every worker, the thread linker and a concurrent date's L2 share, and a confined call exits 0 with its write refused (`tests/l1-confine-real.sh --no-bucket`, measured 2026-11-21).

A host whose confined call fails without something else names it in `AUTODREAM_L1_WRITES_EXTRA` (colon-separated, absolute, a trailing `*` is a prefix) and accepts that path's exposure. The output is one path per line, so a path holding a newline would read as two; `HOME` or an extra entry that does is refused outright (exit 3), not split, because the second half could be a directory like `/Users/you`. Globbing is off while the extras are split, so an entry such as `~/.claude.json*` stays a prefix and does not expand to the files that exist.

## Consequences

Adding a path widens what an injected worker can persist. Check the "not listed" reasons above before adding one.
