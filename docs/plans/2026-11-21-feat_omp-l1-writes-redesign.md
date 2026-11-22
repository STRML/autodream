# omp L1 confinement: redesign plan after four gate rounds (#169)

Twelve blocking findings and one P2 in four rounds reduce to six mistakes, and round 5 added three more classes (H, I and a sharper C). A fable-review pass on this plan then found a seventh class (G, below) and ten defects in the branch against rules A to F, all fixed or recorded here. Each section below names one mistake,
states the rule that rules it out, and says where the branch applies the rule. The findings are in
`.git/review-gate/246/round-{1..4}.md`.

## Every blocking finding, grouped

| Round | Finding | Group |
|---|---|---|
| 1 | A retry can truncate a file outside the sandbox (the verb's stderr was redirected into the stage) | D |
| 1 | OAuth refresh can discard the only valid refresh token (the worker rotates it in a disposable copy) | A |
| 1 | Copying live SQLite files can produce an inconsistent snapshot | A |
| 1 | OMP directory overrides bypass the seeded HOME | B |
| 1 | The staged worker loses valid YAML configuration (`config.yaml`) | B |
| 1 | A persistent staging failure can publish a completed report without triage | E |
| 1 | An inaccessible source directory is treated as empty state | C |
| 1 (P2) | `--measure` depended on staging state | F |
| 2 | OAuth-only workers cannot triage sessions (the fix for A removed their only credential) | A |
| 2 | XDG overrides still bypass the staged HOME on macOS | B |
| 2 | An inaccessible source can still be treated as empty state (an unsearchable ancestor) | C |
| 3 | OAuth-only workers again: a bare model selector derived no provider | A |
| 4 | Memory verification can pass without scanning the store | C |
| 5 | State setup hides inaccessible paths as absent (a database symlink into an unsearchable directory, `.env` links, an XDG tree) | C |
| 5 | The memory check misses deleted files and symlinked directories below the root | C |
| 5 | An overlay override bypasses the memory shutdown | H |
| 5 | Cached work still depends on preparing an unused engine | I |
| 6 | The overlay check read `backend: "off"` under any key | H |
| 6 | A store that vanished during the call read as a SKIP | C |
| 6 | With every finding cached, a findings file that vanished before dispatch could start an unprepared worker with no sandbox | I |

## The six mistakes and the rule for each

**A. Treating a live, shared, mutable store as something a worker can hold a copy of.**
Credentials rotate. A SQLite database is three files that change together. Which credential a worker
uses is decided by omp, not by us. Each fix was local (snapshot, drop the rows, check the provider) and
each one exposed the next hole in the same question: can this worker run on a throwaway copy of this
credential at all?

Rule: answer that question once, at setup, from the model the engine will use, and answer it
conservatively.

- A model on an api-key provider runs confined, on a consistent snapshot with every OAuth row removed.
- A model on an OAuth provider, or a model we cannot place (a bare selector, no model), leaves the engine
  unconfined. `l1_confined_omp: no` states the reason.

Applied in `seed-db.py --provider` (exit 4, provider compared without regard to case) and in the setup dry
run in `l1_confine_setup`. The worker's own call passes no model, so it decides nothing: it only leaves the
OAuth rows out of its copy.

**B. Assuming the environment instead of reading how omp resolves it.**
Overrides (`PI_CODING_AGENT_DIR`, `PI_CONFIG_DIR`, profiles, XDG), file spellings (`.yml` and `.yaml`) and
platforms (XDG applies on macOS too) were each found one round at a time.

Rule: the adapter encodes omp's own resolution (`packages/utils/src/dirs.ts`), and it refuses anything it
does not model. The verb pins `HOME`, `PI_CONFIG_DIR` and `PI_CODING_AGENT_DIR` into the stage. It refuses
a named profile, any existing `$XDG_*_HOME/omp` tree, and the path overrides omp reads that point outside
the seeded tree (`OMP_WORKTREE_DIR`, `OMP_GITHUB_CACHE_DB`, `OMP_COMMIT_CACHE_DB`, `OMP_JUDGMENT_CACHE_DB`,
`OMP_AUTH_BROKER_SNAPSHOT_CACHE`, `PI_NATIVES_DIR`). It seeds the three `.env` files omp loads (HOME, the
config root, the agent dir), where a provider key can live.

**C. Reading a failed test as a negative.**
`-f` on an unreadable directory, `-e` under an unsearchable parent, and a `find` whose error was discarded
each answered "nothing there" when the true answer was "could not look".

Rule: every existence or comparison check has three outcomes (present, absent, could not look), and "could
not look" fails. `path_state` in `bin/lib-path-state.sh` is the one definition: absent is believed only when
the nearest existing ancestor is a searchable directory, and a symlink that cannot be followed is "cannot
tell". The adapter uses it at every site that decides whether a file exists (the agent dir, each seeded
file, each `.env`, the XDG trees). Change detection is a before and after snapshot of the whole store
(`store_snapshot` and `store_unchanged` in `tests/lib-store-unchanged.sh`), so a deleted file, a new file and
a file behind a symlinked directory are all changes. Unit cases cover each, plus a missing store (a skip)
and unreadable or dangling stores (failures).

**D. The runner writing into territory the worker controls.**
The runner runs outside the sandbox, so every path inside a stage is attacker-chosen. A symlink the worker
left there redirected the runner's own write.

Rule: the runner never opens a path inside a stage for writing. It removes or renames it. Its scratch files
live beside the stages (`senv.*` in the staging root). The verb builds the whole state tree in a directory
beside the stage (`seed.*`) and renames it in, after checking that the previous `omp-home` is gone. A
symlink left where the stage's private `tmp` goes is removed and the directory made again, so one hostile
worker cannot turn a retry into a failed night.

**E. Converting an infrastructure failure into completed work.**
A stub fills a slot and satisfies the missing-work check, so a setup that failed every attempt published a
report over sessions that were never triaged.

Rule: a setup failure writes no stub. When it is what the last round left missing, it is a fatal (banner,
`fatal:` in run-stats, the marker the next run reads). It is not an outage deferral, because waiting heals
nothing and a deferral names nothing.

**F. A diagnostic that needed the thing it diagnoses.**
`--measure` seeded state it never used. It no longer does.

**H. Inherited configuration that bypasses a safeguard.** `NO_ADVISOR_CFG` replaced the overlay that turns
the memory backend off. Two rounds each found a way past a hand-written check of the replacement (a grep, then
a block-aware awk), so the check was the wrong tool: proving a YAML file keeps memory off takes a YAML parser.
Rule: the seam is gone. Every headless omp call (worker, linker, warmup, L2) passes the shipped
`adapters/omp/l1-no-advisor.yml`, and `NO_ADVISOR_CFG` is ignored (a test pins that for all four verbs). Nothing
in the repo used the override but the tests and the threads probe.

**I. Setup for an execution path that will not run.** Setup prepared every engine in the source map, so a
retry after L2 failed, with every finding already cached, fatalled over an unreadable omp database no worker
needed. Rule: setup prepares only engines that still have a session without findings, says `l1_confined: n/a`
when there are none, and an attempt for an engine setup skipped fails (never runs unconfined).

**G. State other processes must see, copied into a private tree.** Found by the plan review, not by the
gate. With a private `HOME`, omp's in-flight request leases are per worker, so a configured
`maxInFlightRequests` multiplies by the fanout. Credential blocks and usage history die with the stage.
These are limits on how well a confined worker behaves, not holes, and the L1 provider here sets no
in-flight cap. Recorded, not fixed.

## Failure matrix

| State | Result |
|---|---|
| Model on an api-key provider, omp confined | Snapshot with OAuth rows removed; `HOME`, `PI_CONFIG_DIR`, `PI_CODING_AGENT_DIR` in the stage |
| Model's provider holds only OAuth | omp unconfined; `l1_confined_omp: no`; the reason names the model |
| Bare selector and any live OAuth credential | Same; the reason says the selector names no provider |
| Bare selector and no live OAuth credential | Confined; there is nothing to lose |
| Named profile, or an existing `$XDG_*_HOME/omp` | Setup fatal |
| Agent dir or an ancestor cannot be read or searched | Setup fatal |
| A database cannot be snapshotted | Setup fatal: no stub, no report, banner |
| Setup passes and every attempt's setup fails | No stubs; fatal after the last round; banner; marker for the next run |
| A worker leaves a symlink where the runner once wrote | Never opened |
| The memory store cannot be scanned in the real check | FAIL |
| The memory store does not exist | SKIP, stated |
| A file under the memory store changes during the confined call | FAIL; rerun on a quiet host |
| Memory backend | Off for every headless omp call (the L1 overlay); `mcp.json` not seeded |

## What the plan review found, and what was done

| Finding | Done |
|---|---|
| `.env` files not seeded (B) | Seeded: the agent dir's, the config root's and HOME's |
| The verb wrote into stage paths a worker controls (D) | Builds beside the stage, renames in, checks the old tree is gone; unit case with a symlink at `omp-home` |
| The worker call re-decided the provider, and a spelling could slip past (A) | The worker call carries no model; the comparison ignores case |
| `find` did not follow a symlinked store; the real check hard-coded `~/.omp`; a SKIP read as ALL PASS (C) | `find -H`; the agent dir is resolved as the adapter resolves it; the final line counts skips |
| The matrix said "names no provider" but the runner printed a fixed sentence | The reason is the verb's own stderr |
| A `case` inside `$(...)` in the worker's FAIL line broke under bash 3.2 | Rewritten without it; a test asserts the line prints |
| A symlinked stage `tmp` was a fatal | Removed and recreated |
| `autolearn` not off in the overlay | Off, as omp's own worker overlay does |
| Path overrides other than the profile and XDG not refused | Refused (list above) |
| Matrix rows without a test | `.env`, a symlink at `omp-home`, `PI_PROFILE`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, the other overrides, a case-different provider, a worker call with no model, the FAIL line |
| Predicting credentials instead of observing them | Not built: a confined warmup at setup (one `ping` through the confined worker command) would observe a missing credential directly, and would also replace the provider guess. It costs one model call per run and a second warm-up path. Recorded as a follow-up for the coordinator |

The stale text the review named (Linux-only XDG, `mcp.json` listed as seeded, "deferred" where the code is
a fatal) is corrected in `adapters/omp/adapter.sh`, `docs/plans/2026-11-21-omp-l1-writes.md` and the
`bin/run.sh` comments.
