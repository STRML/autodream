# What a confined L1 worker may write, and what that costs (#169)

Decision: the claude adapter's `l1-writes` list is default deny. A confined L1 call may write its staging directory, the isolated work bucket and the CLI's own cache, and nothing else. A host whose call fails without something more names that path in `AUTODREAM_L1_WRITES_EXTRA` and accepts its exposure.

## Why each candidate is in or out

| Path | In? | Why |
|---|---|---|
| staging directory | in | the worker's whole job |
| `$WORK_BUCKET` (`~/.claude/projects/<isolated cwd>`) | in | an AI-title stub lands there; `run.sh` wipes it right after L1 and again after L2, because L2 also launches from that directory |
| `~/Library/Caches/claude-cli-nodejs`, `~/.cache/claude-cli-nodejs` | in | the CLI's MCP and request logs; nothing reads them as code. A real unconfined call writes `claude-cli-nodejs/<cwd bucket>/mcp-logs-*` |
| `~/.claude.json` and `~/.claude.json*` temp files | out | holds `mcpServers`, `allowedTools` and `enabledMcpjsonServers`. An injected worker could add an MCP server command (code as the user in the next interactive session) or pre-grant tools |
| `~/.claude/backups` | out | copies of `.claude.json` that the CLI restores from; same exposure, one step removed |
| `~/.claude/session-env` | out | on this host each directory holds `sessionstart-hook-N.sh` env files, which Claude Code sources before a session's Bash calls. A worker could append shell to a live session's file |
| `~/.claude/plugins/store/*.json` | out, pending | an unconfined call writes it (plugin store index). Whether a confined call fails without it is not known yet |
| settings, hooks, skills, the rest of plugins, the CLI install dir | out | code or configuration a later run executes; auto-update writes executables in the install dir |
| `todos`, `statsig`, `debug` | out | not seen in a measured call, so no reason to allow them |

The measured list came from `tests/l1-confine-real.sh --measure` on the coordinator's host: one unconfined Haiku call wrote `~/.claude/plugins/store/*.json` and `~/Library/Caches/claude-cli-nodejs/<cwd bucket>/mcp-logs-*` among claude-owned paths. The first draft of the list allowed more than that, and its confined call passed. That proves the draft list is enough, not that the shorter one is. A call under the shorter list has to run outside any other sandbox, so it is the open step.

## How to settle the open step

Run `bash tests/l1-confine-real.sh` on the host that runs the nightly (the real call needs the keychain and the network, and `sandbox-exec` cannot start inside another sandbox).

1. If it prints ALL PASS, ship the default list.
2. If the confined call fails, read stderr in the output: a refused write usually names the path. Add that path to `AUTODREAM_L1_WRITES_EXTRA` in `$AUTODREAM_DIR/config`, re-run, and note the path and its exposure here.
3. If the call needs `~/.claude.json` itself, the narrowest allowance is that one file (no `backups`, no prefix) and the residual risk is the table row above. A throwaway `CLAUDE_CONFIG_DIR` seeded with a copy is not an alternative on macOS: the keychain item name depends on the config directory, so the engine would log out.

## Residual risk if step 3 is needed

A prompt-injected worker that can write `~/.claude.json` can persist an MCP server entry. The post-L1 snapshot-and-restore of those keys is the follow-up that would close it; it is not built here.
