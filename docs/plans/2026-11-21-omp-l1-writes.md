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
tree), and prints `HOME`, `PI_CONFIG_DIR` and `PI_CODING_AGENT_DIR`, all pointing into `<stage>/omp-home`.
It seeds only what the worker reads: `config` and `models` (`.yml` or `.yaml`), `mcp.json`, the context
files omp loads into its prompt (`AGENTS.md`, `APPEND_SYSTEM.md`, `RULES.md`), and one snapshot of each
database. `Library` and `natives` are linked back read-only so a keychain lookup for an api key and the
native addon still resolve; a write through either link is refused like any other. The agent dir is
22 GB, so it is never copied wholesale.

| Decision | Why |
|---|---|
| Databases are snapshotted with SQLite's backup API (`seed-db.py`), not copied file by file | `agent.db` and `models.db` are live WAL databases. Copying `.db`, `.db-wal` and `.db-shm` one after another can pair an old database with a newer log. A test holds a committed row only the log has and finds it in the copy |
| OAuth credential rows are left out of the worker's copy | a worker that refreshed a token in its copy would rotate the refresh token there, and the copy dies with the stage; a provider that invalidates the old token would leave the real database holding a spent one. An L1 model on an OAuth-only provider fails with a login error, classed `provider` and retried. Providers with an api key (this host's neuralwatt) are unaffected |
| `PI_CODING_AGENT_DIR` is the seed source and is replaced; `PI_CONFIG_DIR` is kept | an inherited override would otherwise point the worker at the real tree, where the sandbox refuses its database writes |
| A named profile (`OMP_PROFILE`, `PI_PROFILE`), or an XDG redirect on Linux, refuses | the state lives somewhere this seeding does not model; running on the wrong files is worse than failing |
| An agent dir that exists and cannot be read refuses; one that does not exist seeds nothing | a failed `-f` test must not read as "empty state" |
| The verb writes its stderr to a file beside the stages, not inside one | the runner runs outside the sandbox, and a worker can leave a symlink at any path in its own stage; a redirection into the stage would follow it and truncate the target |
| A setup failure defers the date (ledger value `staging`) and writes no stub | a stub fills the slot, satisfies the missing-work check and lets a report publish over sessions that were never triaged. The same holds for the staging-root, stage-directory and sandbox failures before the engine starts |

## Cost and residual

- The worker reads copies of its settings, so a change made mid-run is not seen.
- Credentials sit in the stage for the life of the call (`models.yml` and the api-key rows of `agent.db`):
  0700 directory under `$AUTODREAM_DIR/staging`, removed when the session's answer is accepted and swept
  when the run is dead. The worker can already read the real files, so nothing new is readable.
- The mnemopi bank `-shm` files changed in the real tree during the isolated run. They are the shared-memory
  index of a bank, mapped by the live mnemopi server (a separate process), not by the worker: with
  `HOME` in the stage the worker's own config root, and so its mnemopi socket and banks, are the stage's.
  Reaching the real server would take a tool, and the worker holds `Read` and `Write` only. Not proved
  here: a quiet-host rerun that shows no `-shm` write at all would. The confirming run on 0a6a819 wrote
  nothing under the real `$HOME`.
