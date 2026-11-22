# 0004: The OMP adapter

Status: accepted · Governs: `adapters/omp/adapter.sh`, `bin/lib-path-state.sh`, `adapters/omp/seed-db.py`, `adapters/omp/skills-inventory.sh`, `adapters/omp/linearize.sh`, `adapters/omp/stats.sh`

This record holds 21 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: The OMP adapter (`adapters/omp`)](#background-the-omp-adapter-adaptersomp)
- [omp stats and slim write through a unique temp and refuse a directory destination, and normalize leaves no output when linearize fails](#omp-stats-and-slim-write-through-a-unique-temp-and-refuse-a-directory-destination-and-normalize-leaves-no-output-when-linearize-fails)
- [the omp adapter linearizes and reads stats itself and delegates the rest to shared scripts, resolving its own directory physically](#the-omp-adapter-linearizes-and-reads-stats-itself-and-delegates-the-rest-to-shared-scripts-resolving-its-own-directory-physically)
- [omp enumerate is an mtime window and nothing more, and keeps find's stderr](#omp-enumerate-is-an-mtime-window-and-nothing-more-and-keeps-finds-stderr)
- [every headless omp call passes the shipped overlay through --config, and the L1 flags are each load-bearing](#every-headless-omp-call-passes-the-shipped-overlay-through---config-and-the-l1-flags-are-each-load-bearing)
- [omp is-self exits 3 on an unreadable file instead of answering not-ours](#omp-is-self-exits-3-on-an-unreadable-file-instead-of-answering-not-ours)
- [l1-stage-env builds the seeded state in a directory beside the stages and renames it into the stage at the end](#l1-stage-env-builds-the-seeded-state-in-a-directory-beside-the-stages-and-renames-it-into-the-stage-at-the-end)
- [l1-stage-env refuses when omp keeps state somewhere the seeding does not model, and never reads an unanswerable test as absent](#l1-stage-env-refuses-when-omp-keeps-state-somewhere-the-seeding-does-not-model-and-never-reads-an-unanswerable-test-as-absent)
- [a confined omp worker runs on a throwaway HOME inside its stage, seeded with what it only reads and with the OAuth rows left out](#a-confined-omp-worker-runs-on-a-throwaway-home-inside-its-stage-seeded-with-what-it-only-reads-and-with-the-oauth-rows-left-out)
- [the omp L1 write list is empty by default, extended only through AUTODREAM_L1_WRITES_EXTRA](#the-omp-l1-write-list-is-empty-by-default-extended-only-through-autodream_l1_writes_extra)
- [the omp binary resolves OMP_BIN, then PATH, then the known install places, and the adapter prints which one](#the-omp-binary-resolves-omp_bin-then-path-then-the-known-install-places-and-the-adapter-prints-which-one)
- [the omp project verb reads the cwd from the session header or autodream_meta with jq](#the-omp-project-verb-reads-the-cwd-from-the-session-header-or-autodream_meta-with-jq)
- [the omp skills-inventory verb prints names and descriptions, and a failure prints nothing and exits 1](#the-omp-skills-inventory-verb-prints-names-and-descriptions-and-a-failure-prints-nothing-and-exits-1)
- [the linearizer refuses a directory destination and checks it again after the move](#the-linearizer-refuses-a-directory-destination-and-checks-it-again-after-the-move)
- [the omp linearizer keeps only the live chain and fails closed](#the-omp-linearizer-keeps-only-the-live-chain-and-fails-closed)
- [omp nested and advisor provenance comes from the path, and the meta record carries it forward](#omp-nested-and-advisor-provenance-comes-from-the-path-and-the-meta-record-carries-it-forward)
- [the omp skills inventory lists the active on-disk surface from fixed roots, standalone roots first, first name wins](#the-omp-skills-inventory-lists-the-active-on-disk-surface-from-fixed-roots-standalone-roots-first-first-name-wins)
- [the inventory is written to a temp in the outfile's directory and renamed, and the script's exits tell usage and write failure apart from success](#the-inventory-is-written-to-a-temp-in-the-outfiles-directory-and-renamed-and-the-scripts-exits-tell-usage-and-write-failure-apart-from-success)
- [the frontmatter reader resolves name, description and enabled by fixed rules, and a skill is ignored by name or by directory name](#the-frontmatter-reader-resolves-name-description-and-enabled-by-fixed-rules-and-a-skill-is-ignored-by-name-or-by-directory-name)
- [the ignoredSkills parse follows exact YAML block-list rules, and a failed parse aborts instead of reporting an empty ignore list](#the-ignoredskills-parse-follows-exact-yaml-block-list-rules-and-a-failed-parse-aborts-instead-of-reporting-an-empty-ignore-list)
- [plugin skills are found with find and no maxdepth, because the path shape already bounds the result](#plugin-skills-are-found-with-find-and-no-maxdepth-because-the-path-shape-already-bounds-the-result)

## Background: The OMP adapter (`adapters/omp`)

This section was moved here from the former CLAUDE.md. Its original title: "The OMP adapter (`adapters/omp`)".

Plan 2 of the consolidation, `docs/plans/2026-10-03-omp-adapter.md`. An OMP session is an append-only tree, so `normalize` is real work here, unlike the claude adapter's copy:

- **`linearize.sh` keeps only the chain from the live leaf to the root.** The live leaf is the last entry in the file, because omp does not persist its in-memory leaf pointer. It fails closed with no output on a malformed line, an entry with no string `id`, a dangling `parentId` or a cycle, and callers must skip the session instead of reading the raw file, which credits the user with branches they abandoned. A cycle that excludes the root is caught by the chain's first entry still having a parent; a cycle through every entry is caught the same way, which is why that check is the load-bearing one.
- **Nested sessions are real sessions.** `<stamp>_<id>/__advisor.jsonl` and `<stamp>_<id>/<Name>.jsonl` are children of `<stamp>_<id>.jsonl`. Provenance comes from the path, not from the entries: an advisor has no user turns and no `session_init`. A child is found by its parent file existing, or, once the parent is deleted, by its directory being named like a session file (`<ISO stamp>_<id>`; a bucket is a dash-encoded path and never is). `autodream_meta` carries `nested` and `is_advisor`, and `stats` copies them into the sidecar, because the filename of a normalized temp copy says neither. `isSidechain` is `is_advisor or nested`, so a child is exempt from the noise gate the way a claude subagent is; a stats script handed a raw file works the same out of the path, because a linearized copy's own directory says nothing. A user-role message with `message.attribution` of `agent` (a parent steering a child, hook output, an advisor's whole prompt stream) is not a human turn: `user_message_count` and `user_turn_timestamps` skip it, and a message with no attribution field counts, as in files from before the field.
- **Accepted is not enabled.** `run.sh` scans only the adapters named in `AUTODREAM_ADAPTERS` (default `claude`), so a directory under `adapters/` is safe on a claude nightly. `install.sh --adapters claude,omp` writes the choice into the config.
- `skills-inventory` prints `name<TAB>description`; the claude adapter prints the name alone.
- **Tool calls have two shapes and a main session writes both.** `stats` counts `custom/tool_execution_start` records, and falls back to the assistant messages' `toolCall` blocks only when the file has none: an advisor transcript has only the blocks (minus the calls its toolset rejected with `Tool "<name>" not available`, matched to their result by call id), a main session has each call as a record and as a block, and a union counts every main-session call twice. `tools_used` follows the same source.
- **A skill read is a skill invocation (2026-11-03).** omp has no Skill tool: the model loads a skill with `read skill://<name>` or a read of `<dir>/<name>/SKILL.md`, and only a user `/<name>` leaves the `skill-prompt` record. `stats` counts both, through the same per-file source rule (a read is one call however many shapes record it). A reference file inside a skill, a directory, a glob and an errored read do not count, and a SKILL.md read is left out when the session also writes or edits that same file (#179; the hashline edit names its path only in the block's `[path#HASH]` header, relative). Paths are compared after a lexical resolve against the session cwd (`session` header, or `autodream_meta` in a linearized copy) with `~` expanded from `HOME`, so a project `.claude/skills/x` and `~/.claude/skills/x` do not mask each other. A path that cannot be resolved (no cwd, no `HOME`) falls back to the old match by skill name. Symlinks are not followed, so the sidecar depends on the transcript alone: a read through a symlinked install of a file the session edits under its target path counts as use. Until then the omp detector saw only `skill-prompt`, which 2 of 739 recent transcripts held, so `skills_invoked_count` read 0 almost everywhere.

## omp stats and slim write through a unique temp and refuse a directory destination, and normalize leaves no output when linearize fails

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`atomic`, `stats`, `slim`, `normalize`)

### Context

A half-written output that a later step reads as a whole session is worse than no output. `stats.sh` and `slim-transcript.sh` write their destination directly, so atomicity lives in the adapter, which is the one place that owns the destination. The full reasoning, including why `mv` into a directory reports success while writing nothing where the caller looks, and the check-then-act race that remains, is in `docs/adr/0003-adapters-and-engines.md#adapter-subcommands-write-through-a-unique-temp-in-the-destination-directory-refuse-a-directory-destination-and-verify-a-regular-file-afterwards`. This adapter carries the same shape.

`linearize.sh` is a different case. It is its own atomic writer, refuses a directory destination itself, and exits nonzero with no output for anything it cannot prove is the live conversation (a malformed line, a dangling `parentId`, a cycle). The callers skip such a session instead of reading the raw file, which would credit the user with branches they abandoned.

### Decision

`atomic DEST CMD...` runs the command with a unique `mktemp "$dest.tmp.XXXXXX"` as its last argument, then `mv -f` onto the destination. It refuses a directory destination up front, removes the temp on any failure, and after the `mv` checks the destination is a regular file (removing the stray inside a directory otherwise). `stats` and `slim` use it. `normalize` calls `linearize.sh` directly and maps its failure to exit 1 with no output.

### Consequences

Wrapping `linearize.sh` in `atomic` would add nothing and would hide its own refusal. Pointing `normalize` at the raw file on failure would silently count abandoned branches as work.

## the omp adapter linearizes and reads stats itself and delegates the rest to shared scripts, resolving its own directory physically

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (header, `ADIR`, `BIN`, `normalize`, `stats`, `slim`, `is-self`, `enumerate`)

### Context

An omp session is an append-only tree, not a flat transcript (docs/adr/0004-omp-adapter.md#background-the-omp-adapter-adaptersomp, "The OMP adapter"). Unlike the claude adapter, whose `normalize` is a copy, this one has real work to do: `normalize` linearizes the tree to the live conversation (`linearize.sh`) and `stats` reads omp's own record shapes (`stats.sh`). The shared scripts (`slim-transcript.sh`, `prune-self-sessions.sh`, the enumeration `find`) already understand omp records, so rewriting them per harness would give two copies to keep in step (see `docs/adr/0003-adapters-and-engines.md#the-claude-adapter-delegates-to-the-existing-bin-scripts-and-never-reimplements-their-predicates`).

The store is `$HOME/.omp/agent/sessions/<project-encoded>/<stamp>_<uuid>.jsonl`. Child sessions sit in a directory named after the parent file (`<stamp>_<uuid>/__advisor.jsonl`, `<stamp>_<uuid>/<Name>.jsonl`) and ARE sessions to triage, so the enumeration walk takes every `*.jsonl` below the root and does not stop at a bucket's top level.

`install.sh` symlinks the adapter, so `${BASH_SOURCE[0]}` is a link into the install dir. `ADIR` and `BIN` are resolved with `cd -P` for the same reason as the claude adapter: so `ADIR` is the real `adapters/omp` and `BIN` the real `bin/`, whichever way the adapter was reached.

### Decision

- `normalize` runs `linearize.sh` and `stats` runs `stats.sh` through the atomic writer. `slim` and `is-self` call the shared scripts, and `enumerate` is a plain `find` over `*.jsonl`.
- `ADIR` and `BIN` come from `cd -P`, never from the unresolved path.
- Child sessions are enumerated like any other file. Nothing in the adapter excludes them.

### Consequences

A fix to a shared script reaches both harnesses at once, and a change to omp's record shapes is made in `linearize.sh` and `stats.sh` only. An unresolved `ADIR` under a symlinked install would look for `../../bin` relative to the link and miss it.

## omp enumerate is an mtime window and nothing more, and keeps find's stderr

Status: accepted · Date: 2026-10-04 · Code: `adapters/omp/adapter.sh` (`enumerate`)

### Context

The adapter contract is `enumerate <root> <from> <to>`, filtered on mtime. Since #113/#119 the runner places a session in a report day by the timestamps inside the transcript (`bin/session-window.sh`), not by file mtime, and passes a `to` far in the future (the report day plus five years) so the mtime test becomes a lower bound only: a file last written before the day began cannot hold a record from it. The decision and its reasoning are in `docs/adr/0003-adapters-and-engines.md#enumerate-is-an-mtime-window-only-and-keeps-finds-stderr` and docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to".

`find` exits 1 for an unreadable directory, and the runner has to tell a partial corpus from a failed root on that status.

### Decision

- The adapter never learns about the in-transcript window. `$2` and `$3` are an mtime window and nothing more, which keeps the adapter contract free of any knowledge of it.
- `find`'s stderr is not redirected, so the runner sees the exit status and the message and can count a partial root.

### Consequences

Adding `2>/dev/null` here would turn every unreadable directory into a silently short corpus. Putting window logic in the adapter would duplicate `session-window.sh` per harness.

## every headless omp call passes the shipped overlay through --config, and the L1 flags are each load-bearing

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`OVERLAY`, `l1-argv`, `warmup-argv`, `l2-argv`, `threads-argv`)

### Context

`l1-argv` prints the invocation omp-autodream ran, so a night on the unified runner is the same worker. Three of its flags each cost a night to learn:

| Flag | Why it is there |
|---|---|
| `--config <overlay>` | Turns off the advisor, local provider probes (a sleeping Mac made them take 3.6s each) and first-turn mnemopi recall, which made headless workers exit 0 with empty stdout before any model call. |
| `--tools=Read,Write` | The worker reads the transcript and writes the findings JSON, nothing else. |
| `--no-session` | Leaves no transcript, so the next night does not triage this one (docs/adr/0011-self-pollution.md#background-self-pollution-the-eating-its-own-tail-bug, "Self-pollution"). |

The overlay also sets `memory.backend: off`. A worker that retained or consolidated memory would write a store every later session recalls from (`docs/plans/2026-11-21-omp-l1-writes.md`).

The warmup is omp-autodream's: the worker's flags minus `--tools`, with a system prompt that asks for one word. It carries the same overlay, so the call that refreshes the token is the call a worker would have made. The L2 aggregator gets the overlay too (advisor off, no local provider probes, no first-turn recall) and only `Glob,Read`: the report and the pins come back on stdout. Its system prompt is `prompts/L2_SYSTEM.txt`, read through the loader in `bin/l2-prompt.sh`, and no file means no argv (exit 2).

### Decision

- `OVERLAY` is always `$ADIR/l1-no-advisor.yml`, the shipped file. A replacement hook would need a YAML parser in this adapter to prove it still turns the memory backend off, so there is none.
- Every argv builder (`l1-argv`, `threads-argv`, `warmup-argv`, `l2-argv`) passes `--config "$OVERLAY"`.
- L2 reads its system prompt through `l2_system_prompt`; a failure there is `exit 2` rather than starting the engine without it (`docs/adr/0003-adapters-and-engines.md#the-l2-system-prompt-has-one-copy-found-through-the-install-symlink-and-a-missing-or-blank-copy-is-an-error`).

### Consequences

Dropping the overlay from one builder brings back empty-stdout workers or live memory writes for just that call. Making the overlay path configurable reopens the memory-write exposure.

## omp is-self exits 3 on an unreadable file instead of answering not-ours

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`is-self`)

### Context

`is-self` asks whether a transcript is one of autodream's own (the self-pollution filter in docs/adr/0011-self-pollution.md#background-self-pollution-the-eating-its-own-tail-bug, "Self-pollution"). The shared predicate answers "not ours" for a file it cannot read. That is exactly the answer a real user session gets, so an unreadable autodream transcript would be triaged as the user's work.

### Decision

The verb checks `[ -r "$1" ]` first and exits 3 when it fails, the same readability guard as every sibling adapter. Only then does it `exec prune-self-sessions.sh --is-self`.

### Consequences

The caller must treat 3 as "cannot tell", not as "not ours". Removing the guard silently lets own-transcripts through whenever a permission problem makes one unreadable.

## l1-stage-env builds the seeded state in a directory beside the stages and renames it into the stage at the end

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-stage-env`)

### Context

The verb runs outside the sandbox, as the user, and every path inside a stage is chosen by the last worker that ran there: a read-only directory, a symlink at a seeded name, a database that is a link. A copy or snapshot written straight into the stage would follow any of those, so a worker could aim the runner's write at a file of its choosing.

### Decision

- Remove the previous `<stage>/omp-home` first, and refuse if it cannot be removed.
- Build everything under `mktemp -d "$(dirname "$1")/seed.XXXXXX"`, a directory of its own beside the stages. An EXIT trap removes it on any failure.
- Nothing below writes into the stage. A final `mv` renames the finished tree to `<stage>/omp-home`, then the trap is cleared.

### Consequences

The stage is touched exactly once, by the final rename. Moving a seeding step to write into `$1` directly re-opens the symlink-in-stage hole. The runner also writes the verb's stderr to a file beside the stages for the same reason (`docs/adr/0006-l1-confinement.md#each-l1-engine-call-writes-only-its-own-staging-dir-under-an-os-sandbox-and-the-runner-copies-the-answer-out`).

## l1-stage-env refuses when omp keeps state somewhere the seeding does not model, and never reads an unanswerable test as absent

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-stage-env`), `bin/lib-path-state.sh` (`path_state`)

### Context

Running a confined worker on the wrong files is worse than failing it. A named profile, an XDG redirect, or a path override moves omp's state to a place the throwaway-HOME seeding (`docs/adr/0004-omp-adapter.md#a-confined-omp-worker-runs-on-a-throwaway-home-inside-its-stage-seeded-with-what-it-only-reads-and-with-the-oauth-rows-left-out`) does not look. A failed `-e` test is also not proof that nothing is there: a path under a directory this user cannot search tests as absent too.

### Decision

The verb exits 1 with an `omp l1-stage-env:` message in each of these cases:

- `OMP_PROFILE` or `PI_PROFILE` is set. A named profile moves the state.
- `$XDG_DATA_HOME`, `$XDG_STATE_HOME` or `$XDG_CACHE_HOME` is set and `<it>/omp` exists. omp redirects a directory category to `$XDG_<CATEGORY>_HOME/omp` on Linux and on macOS, but only when that directory exists, so the refusal is on the same condition and not on the variable alone.
- One of `OMP_WORKTREE_DIR`, `OMP_GITHUB_CACHE_DB`, `OMP_COMMIT_CACHE_DB`, `OMP_JUDGMENT_CACHE_DB`, `OMP_AUTH_BROKER_SNAPSHOT_CACHE`, `PI_NATIVES_DIR` is set. These point outside any tree the seeding covers (omp's `dirs.ts`).
- `PI_CONFIG_DIR` is not a plain directory name under `HOME`.
- The stage path holds a newline.

`path_state` has three answers: present, absent, and "cannot tell" (an unreachable path, a symlink into a directory this user cannot search). Only "absent" is believed to mean nothing there. "Cannot tell" refuses for the XDG trees, the agent dir, every seeded file and database (a database that cannot be snapshotted is not an absent one), and the `.env` files. An agent dir that exists and cannot be read also refuses; one that is absent seeds nothing.

### Consequences

A new omp env override that relocates state needs a line in the override list, or workers silently run on the wrong files. The newer the omp, the likelier a missed override: re-read omp's `dirs.ts` when upgrading across a major version. A refusal here is a setup failure for the engine (docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A host with no working sandbox says so"): no stub, a fatal before any worker starts.

## a confined omp worker runs on a throwaway HOME inside its stage, seeded with what it only reads and with the OAuth rows left out

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-stage-env`), `adapters/omp/seed-db.py`

### Context

A confined omp call cannot run on an empty write list: bun's SQLite close dies on its first database write. `~/.omp/agent` holds the settings, extensions, rules and skills that a later interactive omp loads, so it cannot be allowed either. omp resolves its whole state tree (agent dir, logs, run, cache) from `HOME`, so a `HOME` inside the stage puts every write in the stage.

Measured 2026-11-21 on a real host with `tests/l1-confine-real.sh --engine omp`: ALL PASS, and no write reached `~/.omp` except the `-shm` of mnemopi banks (a live server mapping them, not the worker). The measurement, the rejected allow-lists and the cost are in `docs/plans/2026-11-21-omp-l1-writes.md`; docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A host with no working sandbox says so", records the setup behaviour.

### Decision

The verb runs in the runner, outside the sandbox, once per attempt, and prints `HOME`, `PI_CONFIG_DIR` and `PI_CODING_AGENT_DIR`, all pointing into `<stage>/omp-home`.

- **Seeded:** settings (`config` and `models`, `.yml` or `.yaml`), the context files omp loads into its prompt, the `.env` files omp reads (at `HOME` and at the config root, where a provider key may live), `kimi-device-id`, and one consistent SQLite snapshot of each database through `seed-db.py` (the backup API: a live database is not safe to copy file by file).
- **OAuth rows left out** (`--drop-oauth`, with `--provider` from the model's prefix when a model is given). A worker that refreshed a token in its copy would rotate the refresh token there, and the copy dies with the stage. Exit 4 from `seed-db.py` (an OAuth-only provider) is passed through, so setup reports `l1_confined_omp: no` with the reason instead of failing every worker.
- **Linked back read-only:** `Library` (so a keychain lookup for an api key still resolves) and `natives` (the native addon). A write through either link is refused by the sandbox like any other.
- **Not seeded:** `mcp.json`. A worker holds Read and Write only, and an MCP server it started would be one more process outside the sandbox's reach to talk to.
- **Overrides:** `PI_CODING_AGENT_DIR` is the seed source and is replaced in the output; `PI_CONFIG_DIR` names the directory under `HOME`. An inherited override therefore cannot point the worker at the real tree.

### Consequences

The agent dir is large (22 GB measured), so it is never copied wholesale: add to the seeded list only what the worker reads. Credentials sit in the stage for the life of the call (0700 under `$AUTODREAM_DIR/staging`, removed when the answer is accepted and swept when the run is dead). A worker already reads the real files, so nothing new is readable. Settings changed mid-run are not seen.

## the omp L1 write list is empty by default, extended only through AUTODREAM_L1_WRITES_EXTRA

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-writes`, `nl_refuse`)

### Context

`run.sh` runs the worker under an OS sandbox that can write nothing besides its staging directory and this list (#169, `bin/l1-confine.sh`; docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "What the sandbox allows"). The claude adapter's list is default deny with the CLI cache on it (`docs/adr/0006-l1-confinement.md#an-l1-worker-may-write-only-its-staging-directory-plus-a-default-deny-list-that-holds-the-clis-own-cache`). omp cannot run on an empty list by itself, so `l1-stage-env` gives each confined worker a throwaway HOME inside its stage and every omp write lands there (`docs/adr/0004-omp-adapter.md#a-confined-omp-worker-runs-on-a-throwaway-home-inside-its-stage-seeded-with-what-it-only-reads-and-with-the-oauth-rows-left-out`). The measurement is in `docs/plans/2026-11-21-omp-l1-writes.md`.

### Decision

The list stays empty. A host whose confined call still fails names the path in `AUTODREAM_L1_WRITES_EXTRA` (colon-separated, absolute, a trailing `*` is a prefix) and accepts that path's exposure.

- The output is one path per line, so a path holding a newline would read as two. An extra entry that holds one is refused outright (exit 3, `l1-writes: refusing a path that holds a newline`), not split, because the second half could be a directory like `/Users/you`.
- Globbing is off (`set -f`) while the extras are split, so an entry such as `~/x.json*` stays a prefix and does not expand to the files that exist.
- IFS is restored and globbing turned back on afterwards.

### Consequences

Adding a default path widens what an injected worker can persist. `tests/run-all.sh` pins the output, the newline refusal and the unknown-verb exit. The test cases `sed` the `l1-writes)` label line to prove the runner copes with an adapter that lacks the verb, so keep that label at the start of its line.

## the omp binary resolves OMP_BIN, then PATH, then the known install places, and the adapter prints which one

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`omp_bin`, `engine-bin`)

### Context

On 2026-08-25 a 17.3.7-versus-18.0.4 split between PATH and the hard-coded default cost half of every L1 round to provider 400s, and nothing in the log said which omp ran. A launchd job has a minimal PATH, so a bun or homebrew install is not found by `command -v` alone.

### Decision

`omp_bin` answers in order: an explicit `OMP_BIN` (for pinning a build), then `command -v omp`, then the places omp installs to (`~/.local/bin`, `~/.bun/bin`, `/opt/homebrew/bin`, `/usr/local/bin`), then the bare name `omp`. The `engine-bin` verb prints the answer, an absolute path or the bare name when none was found, so the runner can log and verify exactly which binary every argv starts with. `l1-argv`, `threads-argv`, `warmup-argv` and `l2-argv` all start from the same function, so a worker, its warmup and the aggregator cannot run different builds.

### Consequences

Installing a second omp earlier on PATH changes which one runs, unless `OMP_BIN` pins it. docs/adr/0023-install-and-scheduling.md#background-what-goes-in-the-plist-path, "What goes in the plist PATH", covers how `install.sh` makes the directory reachable from launchd.

## the omp project verb reads the cwd from the session header or autodream_meta with jq

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`project`)

### Context

The runner needs a session's real working directory. An omp raw session carries it in its `session` header record. A linearized copy carries it in `autodream_meta`. The runner can hand the verb either shape. A cwd with a quote or a backslash is JSON-escaped on the line, so a regex over the raw line truncates it. The claude adapter made the same choice (`docs/adr/0003-adapters-and-engines.md#the-claude-adapter-reads-a-sessions-cwd-with-jq-never-grep`).

### Decision

`jq -re` selects the first record whose `.type` is `session` or `autodream_meta` and whose `.cwd` is a string, takes the first result, and the verb prints its `realpath`. An unreadable file, no such record or an unresolvable path exits 1 with nothing printed.

### Consequences

A grep-based reader would pass a plain path and fail on exactly the paths that need escaping. Dropping `autodream_meta` from the selection breaks `project` on every normalized copy.

## the omp skills-inventory verb prints names and descriptions, and a failure prints nothing and exits 1

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`skills-inventory`), `adapters/omp/skills-inventory.sh`

### Context

L2 treats the inventory as the authoritative list of active skills (`docs/adr/0003-adapters-and-engines.md#l2s-skills-inventory-and-per-harness-facts-come-from-the-adapters-and-facts-are-taken-only-for-sources-that-had-sessions-from-the-pre-model-source-map`). An empty inventory would claim no skills are installed, so the caller must be able to tell "failed" from "none". The claude adapter prints the name alone; omp knows each description too. `skills-inventory.sh` writes a file that starts with four comment lines.

### Decision

The verb prints one active skill per line: the name and, when known, a TAB and its description. A consumer that wants only names takes field 1. It runs the script into a `mktemp` file, drops the `#` header lines with `grep -v '^#'`, removes the temp, and exits with the script's status. A failure prints nothing and exits 1, so the caller writes its `unavailable` sentinel instead of an empty inventory.

### Consequences

Letting a failed script fall through to an empty listing would make L2 file coverage gaps for every skill.

## the linearizer refuses a directory destination and checks it again after the move

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/linearize.sh`

### Context

A directory at the destination makes `mv` move the temp file inside it and report success, with nothing written where the caller looks. The same happens if a directory appears at `$dst` between a guard and the `mv`: it takes the temp inside and still returns 0. The claude adapter hit the same shape, see `bin-a-adapter-claude-atomic-destination-write`.

### Decision

The script refuses a directory destination up front (exit 1) and writes through a temp file beside the destination. After `mv` it checks that `$dst` is a regular file. If it is not, it removes the temp that landed inside and exits 3.

### Consequences

A check-then-act guard alone is not enough, which is why the post-condition stays. The temp is created beside `$dst`, never in `$TMPDIR`, so the move is a rename and not a cross-filesystem copy.

## the omp linearizer keeps only the live chain and fails closed

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/linearize.sh`

### Context

An OMP session file is an append-only tree. Every entry carries `id` and `parentId`, and backing out of a branch moves a leaf pointer instead of rewriting the file, so the file keeps every branch the user abandoned. Read line by line, it credits the user with work they threw away.

omp does not persist its in-memory leaf pointer. The last appended entry is what omp falls back to when it has none, so the last entry in the file is the live leaf.

An unparseable line can change which entry is last. That puts the walk on an abandoned branch, and a confident triage of rejected work is worse than one visibly skipped session.

The tree semantics and the fail-closed rule were worked out in STRML/cc-autodream#47. The script is a rewrite with its own fixtures (`tests/adapter-omp.sh`), not that code. The adapter shipped in #81 (aee73fa). docs/adr/0004-omp-adapter.md#background-the-omp-adapter-adaptersomp, "The OMP adapter", has the user-facing record.

### Decision

The script keeps the chain from the live leaf back to the root, root first, behind one `autodream_meta` record. The jq program does four things in order: parse every line strictly, index entries by id, walk `parentId` from the last entry bounded by the entry count so a cycle ends, then insist the chain reaches a root. A chain that stops early cannot be shown to be the live conversation.

It fails closed with no output at all, and callers must skip the session on a nonzero exit instead of reading the raw file. Nothing is written to the destination on failure.

A format gate runs first. An OMP file opens with a title slot and then a session header whose `id` is a string. A Claude transcript has no such record, so the check is structural and not a guess.

Exit codes are the caller's contract:

| Code | Meaning |
|---|---|
| 0 | wrote dst |
| 1 | usage, unreadable input, jq missing, or dst is a directory |
| 2 | not an OMP session (no session header with a string id in the first lines) |
| 3 | produced no output |
| 4 | unparseable line, entry without a string id, a duplicated id, or a broken tree (cycle, or a parentId with no entry behind it) |

### Consequences

Any new refusal must exit 4 with nothing written, and a caller must never fall back to the raw file. A duplicated id is refused because ids index the tree, and a repeated one would let the later entry silently replace the earlier one. Before changing the walk, run `tests/adapter-omp.sh` and the `test_omp_*` and `test_window_omp_*` cases in `tests/run-all.sh`.

## omp nested and advisor provenance comes from the path, and the meta record carries it forward

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/linearize.sh`, `adapters/omp/stats.sh`

### Context

A child omp session lives in a directory named after its parent file:

```
<bucket>/<stamp>_<id>.jsonl            parent
<bucket>/<stamp>_<id>/__advisor.jsonl  child (advisor)
<bucket>/<stamp>_<id>/<Name>.jsonl     child (task subagent)
```

An advisor child has no user turns and no `session_init`, so the entries cannot say what it is. The filename of a normalized temp copy says nothing either, and a linearized copy lives in the runner's work directory where "my directory plus `.jsonl` is a file" is false.

A child whose parent file is gone (deleted or archived) is still a child. Its directory is named like a session file (`<ISO stamp>_<id>`), and a project bucket never is, because a bucket is a dash-encoded path. The shape of the directory name answers without the parent.

omp reserves two stems, `__advisor.jsonl` and `__advisor-<name>.jsonl`, for a reviewer model that tails a primary session. It is an observability record and not an agent session, with a read-only toolset, so `Tool "bash" not available` is its normal shape. Its calls are `toolCall` content blocks and not `tool_execution_start` records.

### Decision

`linearize.sh` derives `nested`, `parent` and `is_advisor` from the path (parent file exists, or the directory name has the session-file shape, or the basename is one of the two advisor stems) and records them in `autodream_meta`. `stats.sh` ignores that record in every count and reads the flags from it. For a raw file it applies the same path rules itself: advisor from its own name, nested from the parent file or the directory shape.

The same rule is therefore written twice, once in `linearize.sh` and once in `stats.sh`.

### Consequences

A change to one copy must change the other. `tests/adapter-omp.sh` pins both against `__advisor-<name>.jsonl` and the nested cases. Do not derive these flags from entry contents. See also `tests-adapters-omp-stats-and-overlay` and docs/adr/0004-omp-adapter.md#background-the-omp-adapter-adaptersomp, "The OMP adapter" (nested sessions are real sessions).

## the omp skills inventory lists the active on-disk surface from fixed roots, standalone roots first, first name wins

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (header, `scan_skill`, `already_emitted`, the emit block)

### Context

The L2 prompt treats the output file as the authoritative active-skill list (`docs/adr/0003-adapters-and-engines.md#l2s-skills-inventory-and-per-harness-facts-come-from-the-adapters-and-facts-are-taken-only-for-sources-that-had-sessions-from-the-pre-model-source-map`). A skill that is on disk but disabled must not appear, and a list that claims more or fewer skills than are active misleads the coverage-gap findings. Some skills cannot be enumerated from the runner.

### Decision

- **Excluded:** skills named in `~/.omp/agent/config.yml` `skills.ignoredSkills`, and on-disk skills whose `SKILL.md` frontmatter sets `enabled:` to a false-family value. The built-in binary skills (compiled into the omp binary) and project-local `.claude/skills` are not enumerable from the runner and are deliberately absent. The output's own header says to reconcile those against the session skill surface.
- **Corpus:** every `$HOME/.claude*` bucket that exists (top-level `skills/*/SKILL.md` plus plugin skills found recursively under `plugins/`), and the standalone roots `$HOME/.agents/skills`, `$HOME/.config/opencode/skills` and `$HOME/.omp/agent/managed-skills`. The standalone roots are scanned first, then the buckets.
- **Dedup:** names are deduplicated, first occurrence wins, so the scan order above decides which copy of a name is reported.
- **Missing roots are normal.** An empty scan still writes a valid, header-only inventory.
- The script is read-only and uses `$HOME` throughout; it never expands `~`.

### Consequences

Reordering the roots changes which duplicate wins, and so which description L2 reads. A new skill root is a new loop in the emit block. An empty inventory is a real answer ("nothing active"), which is why failures exit 1 instead (`docs/adr/0004-omp-adapter.md#the-ignoredskills-parse-follows-exact-yaml-block-list-rules-and-a-failed-parse-aborts-instead-of-reporting-an-empty-ignore-list`).

## the inventory is written to a temp in the outfile's directory and renamed, and the script's exits tell usage and write failure apart from success

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (the `tmpfile` and `mv` block, the `usage` check)

### Context

The output is the file L2 reads. A half-written inventory would read as a short, authoritative list. The caller (`adapters/omp/adapter.sh`, verb `skills-inventory`) writes an unavailable sentinel whenever the script fails, so the exit code is the contract.

### Decision

- Exit 1 with a `usage:` line when `<outfile>` is missing.
- Create the output directory if needed, then `mktemp "$outdir/skills-inventory.XXXXXX"`. An unwritable directory exits 1 with `cannot create a temp inventory`.
- Write the whole inventory (four `#` header lines, then one `name<TAB>description` line per active skill) into the temp, then `mv -f` it onto `<outfile>`. A failed `mv` removes the temp and exits 1.
- Exit 0 on any successful emit, including zero skills found.

### Consequences

The temp lives in the destination directory so the rename stays on one filesystem. Success with zero skills and failure must stay distinguishable: an empty inventory is a valid answer, a failure is not, and the sentinel only fires on the exit code. The header line the script prints names `bin/skills-inventory.sh` as its writer, which is a historical path in a printed string and is not changed here.

## the frontmatter reader resolves name, description and enabled by fixed rules, and a skill is ignored by name or by directory name

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (`read_frontmatter`, `strip_comment`, `scan_skill`)

### Context

`SKILL.md` frontmatter in the wild uses single-line values, block scalars (`>`, `>-`, `|`, `|-`) and inline comments. A skill's frontmatter `name:` routinely differs from the directory it lives in, and an operator disables a skill by whichever spelling they see.

### Decision

`read_frontmatter` reads the file head up to the closing `---` into `FM_NAME`, `FM_DESC` and `FM_ENABLED`, and stops at the closing delimiter.

- **name:** a single line, or a block scalar whose value is the first following indented line. A name left empty, or a block scalar whose value never came and is followed by a column-0 key, resolves to the directory basename. In that empty-block case the column-0 line is not swallowed: it is a real key and is processed normally.
- **description:** a single line, or a folded block (`>`/`>-`) in which all following more-indented lines are joined with single spaces. A column-0 line ends the fold and is processed as a key.
- **enabled:** only a false-family value (`false`, `False`, `0`, `no`) disables the skill. The first token is taken, which drops an inline comment.
- Inline YAML comments (`value # note`) are stripped from name and description the same way the config parse strips them from ignore lists (`strip_comment` cuts at the first ` #`).
- `scan_skill` skips a skill when its resolved name OR its on-disk directory name is in `ignoredSkills`.

### Consequences

Checking only the resolved name would leave a skill active that the operator disabled by its directory name. Treating an empty block-scalar name as a value would emit `>-` as a skill name (`scan_skill` also clears a name that is still a block-scalar marker). A reader that swallowed the column-0 line after an empty `name: >-` would lose the next key, for example `description:`.

## the ignoredSkills parse follows exact YAML block-list rules, and a failed parse aborts instead of reporting an empty ignore list

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (`CLEAN_ITEM`, the `ignored=` block, `in_ignored`)

### Context

An empty ignore list would wrongly claim every on-disk skill is active, including ones the operator explicitly disabled. The config may also be absent, which is normal and means an empty set. python3 is present on macOS; an awk fallback exists for hosts without it.

### Decision

The block list under `ignoredSkills:` is parsed with these rules, identical in the python and awk paths:

- Only items indented deeper than the `ignoredSkills:` key line are list items.
- Blank lines inside the block keep parsing.
- A same-or-less-indented non-blank line (a sibling key) ends the block.
- Inline comments (`- skill # note` becomes `skill`) and surrounding quotes are stripped from each item.

python3 is the primary parser and a strict awk implementation the fallback. A python3 failure prints `python3 parser failed for <config>` on stderr and exits 1, so the nightly's `||` writes its unavailable sentinel. Only "neither parser present" degrades to "no ignores", and it logs that on stderr. A config that does not exist is an empty ignore set.

### Consequences

The three outcomes are different on purpose: absent config (empty set), parser failure (abort), no parser (empty set with a logged warning). Merging the last two into one quiet fallback brings back the false "all skills active" inventory. `CLEAN_ITEM` is awk text spliced into the awk program, so edits to it follow awk quoting, not shell (the single quote is the `\047` escape). The python and awk bodies carry their own inline comments because they are program text inside a string, not shell comments.

## plugin skills are found with find and no maxdepth, because the path shape already bounds the result

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (the `find "$bucket/plugins"` loop)

### Context

Plugin skills live at arbitrary depth under `plugins/`. A `*` glob cannot cross `/`, so `find` with `-path '*/skills/*/SKILL.md'` is used. A fixed `-maxdepth` silently drops deeper skills: measured, 4 plugin `SKILL.md` files nested one level past an `-maxdepth 8` cut.

### Decision

No `-maxdepth`. The `*/skills/*/SKILL.md` path shape already bounds the result set. `find` errors go to `/dev/null`, and the skills are read through a process substitution so `scan_skill` runs in the main shell and sees the dedup state.

### Consequences

Adding a depth cap to speed up the walk loses skills with no error. The cost is a full walk of each plugin tree, which is acceptable for a nightly job.
