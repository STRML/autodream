# rest: a confined omp worker runs on a throwaway HOME inside its stage, seeded with what it only reads and with the OAuth rows left out

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-stage-env`), `adapters/omp/seed-db.py`

## Context

A confined omp call cannot run on an empty write list: bun's SQLite close dies on its first database write. `~/.omp/agent` holds the settings, extensions, rules and skills that a later interactive omp loads, so it cannot be allowed either. omp resolves its whole state tree (agent dir, logs, run, cache) from `HOME`, so a `HOME` inside the stage puts every write in the stage.

Measured 2026-11-21 on a real host with `tests/l1-confine-real.sh --engine omp`: ALL PASS, and no write reached `~/.omp` except the `-shm` of mnemopi banks (a live server mapping them, not the worker). The measurement, the rejected allow-lists and the cost are in `docs/plans/2026-11-21-omp-l1-writes.md`; CLAUDE.md, "A host with no working sandbox says so", records the setup behaviour.

## Decision

The verb runs in the runner, outside the sandbox, once per attempt, and prints `HOME`, `PI_CONFIG_DIR` and `PI_CODING_AGENT_DIR`, all pointing into `<stage>/omp-home`.

- **Seeded:** settings (`config` and `models`, `.yml` or `.yaml`), the context files omp loads into its prompt, the `.env` files omp reads (at `HOME` and at the config root, where a provider key may live), `kimi-device-id`, and one consistent SQLite snapshot of each database through `seed-db.py` (the backup API: a live database is not safe to copy file by file).
- **OAuth rows left out** (`--drop-oauth`, with `--provider` from the model's prefix when a model is given). A worker that refreshed a token in its copy would rotate the refresh token there, and the copy dies with the stage. Exit 4 from `seed-db.py` (an OAuth-only provider) is passed through, so setup reports `l1_confined_omp: no` with the reason instead of failing every worker.
- **Linked back read-only:** `Library` (so a keychain lookup for an api key still resolves) and `natives` (the native addon). A write through either link is refused by the sandbox like any other.
- **Not seeded:** `mcp.json`. A worker holds Read and Write only, and an MCP server it started would be one more process outside the sandbox's reach to talk to.
- **Overrides:** `PI_CODING_AGENT_DIR` is the seed source and is replaced in the output; `PI_CONFIG_DIR` names the directory under `HOME`. An inherited override therefore cannot point the worker at the real tree.

## Consequences

The agent dir is large (22 GB measured), so it is never copied wholesale: add to the seeded list only what the worker reads. Credentials sit in the stage for the life of the call (0700 under `$AUTODREAM_DIR/staging`, removed when the answer is accepted and swept when the run is dead). A worker already reads the real files, so nothing new is readable. Settings changed mid-run are not seen.
