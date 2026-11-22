# What a confined omp L1 worker may write (#169)

Decision: the omp adapter's `l1-writes` is default deny, like claude's. A confined omp call writes its
staging directory and whatever `AUTODREAM_L1_WRITES_EXTRA` names, until a measurement says a path is
needed. This host runs `AUTODREAM_ADAPTERS=claude,omp` with L2 on omp, so without this verb every omp
worker ran unconfined and `l1_confined` read `partial`.

```
before   claude ─▶ sandbox      omp ─▶ no write profile ─▶ unconfined      l1_confined: partial
after    claude ─▶ sandbox      omp ─▶ default-deny list ─▶ sandbox        l1_confined: yes
```

## Why measure

omp keeps agent state under `~/.omp` (settings, extensions, rules, skills, sessions, `agent.db`), and a
headless omp registers a client under `~/.omp/run/daemons/`, the live daemon's state. A path is allowed
only if a confined call fails without it and writing it cannot make a later omp session run attacker
code. Settings, extensions, rules and skills are out whatever the measurement says: omp loads them in
the next interactive session.

## How to measure

Run outside any other sandbox, on a quiet host (a live omp session writes `~/.omp/agent/sessions` and
the shared logs while the call runs, and those rows are noise). The model is the host's pin
(`AUTODREAM_L1_MODEL_OMP` from the nightly's config), then the manifest default.

1. `bash tests/l1-confine-real.sh --engine omp --writes` prints the list the nightly would use. Expected: empty.
2. `bash tests/l1-confine-real.sh --engine omp --measure` makes one unconfined call and lists what it wrote under omp's state paths. That is what `l1-writes` may have to cover.
3. `bash tests/l1-confine-real.sh --engine omp` makes the same call under the default-deny profile. ALL PASS means ship the empty list.
4. If step 3 fails, stderr usually names the refused path. Add it to `AUTODREAM_L1_WRITES_EXTRA` in `$AUTODREAM_DIR/config`, re-run, and record the path and its exposure in the table below.

## Table

| Path | In? | Why |
|---|---|---|
| staging directory | in | the worker's whole job |
| `~/.omp/agent/{settings,extensions,rules,skills}` | out | loaded by the next interactive omp session: code or configuration |
| `~/.omp/agent/sessions` | out | `--no-session` leaves no transcript, so a confined call has no reason to write it |
| `~/.omp/run/daemons/<client>` | pending | a headless omp registers here. Whether a confined call fails without it is the open measurement |
| `~/.omp/logs`, `~/.omp/cache` | pending | not measured yet |

Filled in from the coordinator's run; until then the list is empty and the PR is not mergeable.
