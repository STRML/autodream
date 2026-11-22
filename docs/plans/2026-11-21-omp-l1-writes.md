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
directory under `HOME`; the XDG redirects apply on Linux and macOS, and only when `$XDG_*_HOME/omp` exists. So `agent` leaves `run/daemon` (the live daemon's
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
It seeds only what the worker reads: `config` and `models` (`.yml` or `.yaml`), the three `.env` files omp loads, the context
files omp loads into its prompt (`AGENTS.md`, `APPEND_SYSTEM.md`, `RULES.md`), and one snapshot of each
database. `mcp.json` is not seeded. `Library` and `natives` are linked back read-only so a keychain lookup for an api key and the
native addon still resolve; a write through either link is refused like any other. The agent dir is
22 GB, so it is never copied wholesale.

| Decision | Why |
|---|---|
| Databases are snapshotted with SQLite's backup API (`seed-db.py`), not copied file by file | `agent.db` and `models.db` are live WAL databases. Copying `.db`, `.db-wal` and `.db-shm` one after another can pair an old database with a newer log. A test holds a committed row only the log has and finds it in the copy |
| OAuth credential rows are left out of the worker's copy; a model whose only credential is OAuth leaves omp unconfined | a worker that refreshed a token in its copy would rotate the refresh token there, and the copy dies with the stage; a provider that invalidates the old token would leave the real database holding a spent one. Leaving the rows out of an OAuth-only provider's copy would leave the worker nothing to log in with, so setup checks the engine's model (`seed-db.py --provider`, exit 4) and reports `l1_confined_omp: no` with the reason instead of failing every worker. Providers with an api key (this host's neuralwatt) are unaffected |
| `PI_CODING_AGENT_DIR` is the seed source and is replaced; `PI_CONFIG_DIR` is kept | an inherited override would otherwise point the worker at the real tree, where the sandbox refuses its database writes |
| A named profile (`OMP_PROFILE`, `PI_PROFILE`), or an `$XDG_*_HOME/omp` tree that exists (Linux and macOS, the condition omp itself uses), or one of the other path overrides omp reads (`OMP_WORKTREE_DIR`, the three `OMP_*_CACHE_DB` and snapshot overrides, `PI_NATIVES_DIR`), refuses | the state lives somewhere this seeding does not model; running on the wrong files is worse than failing |
| An agent dir that exists and cannot be read refuses; one that does not exist seeds nothing, once its nearest existing ancestor is shown searchable | a failed `-e` test must not read as "empty state": a path under a directory this user cannot search tests as absent too |
| Setup runs the verb once per engine with the engine's model, before any worker | a setup that cannot work (an unreadable database) stops the run there, with no stub and no report, instead of failing every attempt |
| The verb writes its stderr to a file beside the stages, not inside one | the runner runs outside the sandbox, and a worker can leave a symlink at any path in its own stage; a redirection into the stage would follow it and truncate the target |
| A setup failure writes no stub and, when it is what the last round left missing, is a fatal (ledger value `staging`) | a stub fills the slot, satisfies the missing-work check and lets a report publish over sessions that were never triaged. It is a fatal and not an outage deferral because it heals nothing by waiting: a deferral wrote no report, no banner and, with no findings JSON, no `unassembled_dates` entry, every night. The same holds for the staging-root, stage-directory and sandbox failures before the engine starts |
| The L1 overlay sets `memory.backend: off`, and `mcp.json` is not seeded | a worker reads untrusted transcripts, and omp retains and consolidates memory at the end of a session into a store every later session recalls from, through a server or daemon that is not the worker. The confined run on 03c327f saw the real mnemopi banks change; the overlay now switches the subsystem off for every headless omp call, and `l1-confine-real.sh` checks that nothing under `~/.omp/agent/memories` changes during the confined call (rerun on a quiet host if it fails: a live omp session writes there too) |
| A model selector with no provider (a fuzzy name omp resolves itself) leaves omp unconfined while any live OAuth credential exists | which credential the worker will use is unknown, and it may be the OAuth one |

## Cost and residual

- The worker reads copies of its settings, so a change made mid-run is not seen.
- Credentials sit in the stage for the life of the call (`models.yml` and the api-key rows of `agent.db`):
  0700 directory under `$AUTODREAM_DIR/staging`, removed when the session's answer is accepted and swept
  when the run is dead. The worker can already read the real files, so nothing new is readable.
- The mnemopi banks changed in the real tree during a confined run on 03c327f. The worker holds `Read` and
  `Write` only and its own config root is the stage, so the writer is a process outside the sandbox: a live
  interactive omp, or a memory server the worker reached. The memory backend is now off for every headless
  omp call this repo makes, `mcp.json` is not seeded, and the real check fails when anything under
  `~/.omp/agent/memories` changes during the confined call. A failure on a busy host needs a rerun on a quiet
  one before it is read as a leak. The claude worker cannot reach mnemopi: it runs `--strict-mcp-config` with
  no MCP servers (pinned by `tests/adapter-claude.sh`).
