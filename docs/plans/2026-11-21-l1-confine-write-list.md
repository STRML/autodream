# What a confined L1 worker may write, and what that costs (#169)

Decision: the claude adapter's `l1-writes` list is default deny. A confined L1 call may write its staging directory and the CLI's own cache, and nothing else. A host whose call fails without something more names that path in `AUTODREAM_L1_WRITES_EXTRA` and accepts its exposure.

## Why each candidate is in or out

| Path | In? | Why |
|---|---|---|
| staging directory | in | the worker's whole job |
| `$WORK_BUCKET` (`~/.claude/projects/<isolated cwd>`) | out | the one directory every worker, the thread linker and a concurrent date's L2 would share. A stub lands there only on an unconfined call; a confined call that cannot write it exits 0 (`tests/l1-confine-real.sh --no-bucket`, measured 2026-11-21: ALL PASS). `run.sh` still wipes it before L1, after L1 and after L2 for the engines that run unconfined |
| `~/Library/Caches/claude-cli-nodejs`, `~/.cache/claude-cli-nodejs` | in | the CLI's MCP and request logs; nothing reads them as code. A real unconfined call writes `claude-cli-nodejs/<cwd bucket>/mcp-logs-*` |
| `~/.claude.json` and `~/.claude.json*` temp files | out | holds `mcpServers`, `allowedTools` and `enabledMcpjsonServers`. An injected worker could add an MCP server command (code as the user in the next interactive session) or pre-grant tools |
| `~/.claude/backups` | out | copies of `.claude.json` that the CLI restores from; same exposure, one step removed |
| `~/.claude/session-env` | out | on this host each directory holds `sessionstart-hook-N.sh` env files, which Claude Code sources before a session's Bash calls. A worker could append shell to a live session's file |
| `~/.claude/plugins/{store,cache,known_marketplaces.json}` | out | an unconfined call writes them (plugin store index and cache). The confined call works without them (measured 2026-11-21) |
| settings, hooks, skills, the rest of plugins, the CLI install dir | out | code or configuration a later run executes; auto-update writes executables in the install dir |
| `todos`, `statsig`, `debug` | out | not seen in a measured call, so no reason to allow them |

The measured list came from `tests/l1-confine-real.sh --measure` on the coordinator's host (2026-11-21): one unconfined Haiku call wrote only `~/.claude/plugins/{store,cache,known_marketplaces.json}` and `~/Library/Caches/claude-cli-nodejs/<cwd bucket>/mcp-logs-*` among claude-owned paths. The plain run and the `--no-bucket` run, both under the default-deny list outside any other sandbox, printed ALL PASS: the call authenticated, reached the network, wrote its answer in the stage, was refused outside it, and wrote nothing under `$HOME`.

## Not verified: a token refresh inside the sandbox

Every measured call started with a valid login. A refresh writes the keychain (a different process, not a file the profile covers) and may write `~/.claude.json`, which is out. Two things bound the risk. The serial warmup is unconfined and runs before the first worker, so an expired token is refreshed there. A token that expires mid-run would hit it, and the failure reads "Not logged in" or "OAuth token has expired", which `failure-class.sh` now classes as `provider` (a retriable class) and not as a size failure. If it ever shows up, step 3 below is the answer.

## When a host's confined call fails

Run `bash tests/l1-confine-real.sh` on the host that runs the nightly (the real call needs the keychain and the network, and `sandbox-exec` cannot start inside another sandbox).

1. If it prints ALL PASS, ship the default list.
2. If the confined call fails, read stderr in the output: a refused write usually names the path. Add that path to `AUTODREAM_L1_WRITES_EXTRA` in `$AUTODREAM_DIR/config`, re-run, and note the path and its exposure here.
3. If the call needs `~/.claude.json` itself, the narrowest allowance is that one file (no `backups`, no prefix) and the residual risk is the table row above. A throwaway `CLAUDE_CONFIG_DIR` seeded with a copy is not an alternative on macOS: the keychain item name depends on the config directory, so the engine would log out.

## Residual risk if step 3 is needed

A prompt-injected worker that can write `~/.claude.json` can persist an MCP server entry. The post-L1 snapshot-and-restore of those keys is the follow-up that would close it; it is not built here.
