# How a confined omp L1 worker runs (#169)

Decision: an omp worker runs under the sandbox with the same empty write list as before, on a throwaway
HOME inside its staging directory. This host runs `AUTODREAM_ADAPTERS=claude,omp` with L2 on omp, so until
now every omp worker ran unconfined and `l1_confined` read `partial`.

```
before   omp ─▶ no write profile ─▶ unconfined                          l1_confined: partial
after    omp ─▶ adapter l1-stage-env seeds <stage>/omp-home ─▶ HOME=...  l1_confined: yes
                 └─ sandbox: writes only the stage; every omp write lands in omp-home
```

## What was measured (2026-11-21, outside any sandbox, glm-5.3-flash)

| Run | Result |
|---|---|
| `--engine omp --measure` (unconfined) | exit 0. Wrote under `~/.omp`: `agent/{agent,models}.db` and their WAL, `agent/memories/mnemopi/**/mnemopi.db*`, `agent/memories/sharpshooter/work-*/state.json`, `cache/{judgment-cache,legacy-pi-extension-cache}.db*`, `logs/omp.<date>.<pid>.log`. The host was not quiet, so some rows are other omp processes |
| `--engine omp` (confined, empty list) | FAIL, exit 1 inside bun's SQLite close. No answer in the stage |
| `--engine omp --isolate agent` (`PI_CODING_AGENT_DIR` in the stage) | ALL PASS. Real-`$HOME` writes: `~/.omp/agent/{agent,models}.db-shm`, mnemopi bank `-shm`, `~/.omp/run/daemon/daemon.db{,-wal}` |
| `--engine omp --isolate home` (`HOME` in the stage) | ALL PASS. Real-`$HOME` writes: only mnemopi bank `-shm` files |

`PI_CODING_AGENT_DIR` moves the agent dir only. omp resolves its config root (`logs`, `run`, `cache`) from
`HOME` (`packages/utils/src/dirs.ts`: `rootSubdir`, `baseRootSubdir`), and `PI_CONFIG_DIR` only renames the
directory under `HOME`; the XDG redirects are Linux only. So `agent` leaves `run/daemon` (the live daemon's
registry) and the cache databases writable, and `home` is the shape that keeps all of it in the stage.

## Why not allow paths

| Path | Verdict | Why |
|---|---|---|
| `~/.omp/agent` | no | settings, extensions, rules, skills and the databases a later interactive omp trusts |
| `~/.omp/cache/judgment-cache.db` | no | a worker that can write it could pre-approve a judgment for a later session |
| `~/.omp/run/daemon` | no | the live daemon's registry |
| `~/.omp/logs` | harmless | but a file-by-file list is the shape that rots |

## What `l1-stage-env` does

The adapter verb runs in the runner, outside the sandbox, once per attempt (a retry reseeds from a clean
tree), and prints `HOME=<stage>/omp-home`. It seeds only what the worker reads: `config.yml`, `models.yml`,
`mcp.json`, the context files omp loads into its prompt (`AGENTS.md`, `APPEND_SYSTEM.md`, `RULES.md`),
and APFS clones of `agent.db` and `models.db` (`cp -c`, free for a 30 MB file). `Library` and `natives`
are linked back read-only so a keychain lookup for an api key and the native addon still resolve; a write
through either link is refused like any other. The agent dir is 22 GB, so it is never copied wholesale.

## Cost and residual

- The worker reads copies of its settings, so a change made mid-run is not seen.
- Credentials sit in the stage for the life of the call (`models.yml`, `agent.db`): 0700 directory under
  `$AUTODREAM_DIR/staging`, removed when the session's answer is accepted and swept when the run is dead.
  The worker can already read the real files, so nothing new is readable.
- The mnemopi bank `-shm` files changed in the real tree during the isolated run. They are the shared-memory
  index of a bank, mapped by the live mnemopi server (a separate process), not by the worker: with
  `HOME` in the stage the worker's own config root, and so its mnemopi socket and banks, are the stage's.
  Reaching the real server would take a tool, and the worker holds `Read` and `Write` only. Not proved
  here: a quiet-host rerun that shows no `-shm` write at all would.
