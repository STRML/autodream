# Plan 2: the OMP adapter, and the omp-autodream work cc-autodream lacks

Date: 2026-10-03
Status: in progress (5 of 8 PRs merged; the rest wait on four decisions below)
Design: `docs/design/unify-harness-adapters-2026-08-23.md` (approved), Migration steps 2, 3 and the facts half of 4.
Decision (Sam, 2026-10-03): cc-autodream survives and becomes `STRML/autodream`. omp-autodream is archived after the cutover.

## What this plan finds

Plan 1 built the seam, but the divergence between the repos is larger than the design doc counted. At the merge base (`e231314`, 2026-08-07) the two runners were one codebase. Since then omp-autodream gained 60 commits and cc-autodream 15. Measured against `origin/main` of each:

| Feature | cc-autodream | omp-autodream |
| --- | --- | --- |
| adapter seam, `adapters/claude`, `_fixture` | yes | no |
| Mnemopi pins, question streaks, drift check | yes | streaks and drift only |
| OMP session linearizer, OMP stats, skills inventory | no | stats and inventory only; no linearizer |
| `failure-class.sh`, provider-refusal classification | no | yes |
| network-outage deferral, `l1-netdown.txt` | no | yes |
| bounded L1 workers (`AUTODREAM_L1_TIMEOUT`), auth warmup, circuit breaker | no | yes |
| `l1-no-advisor.yml` overlay (mnemopi recall off, advisor off) | no | yes |
| launchd label ownership (`scheduler-label.sh`) | no | yes |
| three-harness changelog window | no | yes |
| review.sh cmux popup dedup (claim and confirmed token) | partial | yes |

The unified repo is not "cc plus an adapter". It is cc's architecture plus about 35 generic runner fixes that landed only in omp between 2026-09-04 and 2026-09-15. Plan 2 therefore ships in two parts: the adapter itself, then the ports.

## Scope of PR 1 (this change)

`adapters/omp/` with the five required subcommands plus `is-self` and `skills-inventory`:

| Subcommand | Implementation |
| --- | --- |
| `enumerate` | `find` over the session root, NUL-delimited; includes nested child sessions |
| `normalize` | `linearize.sh`, written from scratch; fails closed |
| `project` | header `cwd` (or `autodream_meta.cwd` of a normalized copy), resolved |
| `stats` | `stats.sh` (omp-autodream's stats plus `is_advisor` and `nested`), through an atomic temp |
| `slim` | shared `bin/slim-transcript.sh`, which already strips OMP `toolResult` and `toolCall` payloads |
| `is-self` | shared `bin/prune-self-sessions.sh`, now matching OMP's `{"type":"message","message":{"role":"user"}}` shape |
| `skills-inventory` | `skills-inventory.sh` from omp-autodream; prints `name<TAB>description` |

`manifest.json` declares `writes_memory: false`, so `memory-root` is empty and legal (the subcommand is retired upstream, issue #74). The adapter is not enabled by the runner until per-session dispatch is adapter-aware: `run.sh` already logs and skips any adapter other than `claude`.

Design credit: `STRML/cc-autodream#47` (closed) worked out the tree semantics and the fail-closed rule. `linearize.sh` is a rewrite with its own fixtures, as the design requires.

### Two deviations from the design doc, both small

1. `skills-inventory` prints a second TAB-separated column. The claude adapter prints the name alone. A consumer that wants names takes field 1. The L2 prompt needs the descriptions to decide whether a skill already exists.
2. The L1 flags in `manifest.json` are the ones omp-autodream actually runs (`--approval-mode yolo --no-session --tools=Read,Write`), not the ones in its stale `PORT_CONTRACT.md` (`--permission-mode bypassPermissions --no-session-persistence`).

## Failure matrix

| Condition | Where | Behavior | Test |
| --- | --- | --- | --- |
| malformed JSON line | normalize | exit 4, no output, no temp | `tests/adapter-omp.sh` |
| `parentId` with no entry | normalize | exit 4 | same |
| cycle including the root's child | normalize | exit 4 (chain does not reach a root) | same |
| cycle excluding the root | normalize | exit 4 | same |
| entry with no string `id` | normalize | exit 4 | same |
| Claude transcript, empty file, no session header | normalize | exit 2 | same |
| unreadable input, missing arg, directory destination | normalize | exit 1, nothing planted | same |
| header only, legacy file with no title slot, blank lines, spaces in path | normalize | exit 0 | same |
| abandoned branch | normalize | dropped, counted in `dropped` | same |
| advisor child, task subagent child, parent | normalize, stats | `nested` and `is_advisor` from the path | same |
| `my__advisor.jsonl` | stats | not an advisor (stem anchored) | same |
| header with no `cwd`, `cwd` containing a quote | project | no project / survives escaping | same |
| omp-only host | enumerate | omp sessions enumerated, claude root absent is not an error | contract + `adapters.sh` |
| claude-only host | runner | adapter `omp` accepted by the loader, logged and skipped | existing `run-all.sh` |
| both | runner | claude only until PR 4; omp enabled by PR 4 | PR 4 |
| same path claimed by two adapters, hash collision | union | existing `sessions_duplicate_path`, `sessions_hash_collision` | existing |
| newline, tab, quote, backslash in a path | runner | existing `sessions_rejected_path` | existing |
| empty or missing skill roots | skills-inventory | valid empty inventory, exit 0 | `tests/adapter-omp.sh` |

Mutation checks run against three deliberate defects (leaf taken from the first entry, root check removed, advisor stem unanchored); each is caught.

## PR sequence and status (2026-10-03)

| PR | Content | State |
| --- | --- | --- |
| 1 | `adapters/omp`, linearizer with fixtures, omp stats, skills inventory, OMP-aware `is-self`, contract run for omp, CI wiring | merged, https://github.com/STRML/cc-autodream/pull/81 |
| 6 | launchd label ownership, guarded install, hashed on-demand label, adoptable template | merged, https://github.com/STRML/cc-autodream/pull/82 |
| 7 | three-harness changelog window; also a force-pushed remote is followed, dedupe is scoped to the release, the sparse step works | merged, https://github.com/STRML/cc-autodream/pull/83 |
| 4a | overlap pass drops advisor sidecars (omp-autodream #16, `bin/overlap-stats.sh`) | merged, https://github.com/STRML/cc-autodream/pull/84 |
| 8a | `review.sh` cmux popup dedup by report digest, `tests/review-cmux.sh` | merged, https://github.com/STRML/cc-autodream/pull/85 |
| 2 | L1 worker hardening: stdout and exit-code capture into the `.err`, bounded workers (`AUTODREAM_L1_TIMEOUT`), auth warmup, circuit breaker, the worker overlay, network-outage deferral, no stub on a permanent provider refusal (omp-autodream #37), `failure-class.sh`, oversized-gate classification | not started, see "Why PR 2 is not a port" |
| 4 | per-session dispatch: source sidecar, normalize/stats/slim/is-self through the adapter, per-adapter L1 engine, enable `omp`, advisor triage schema (`SESSION_TRIAGE.md`, `PROMPT.md` text of omp-autodream #16) | not started, needs the decisions below |
| 5 | one `SESSION_TRIAGE.md`, `facts.md` concatenated into the L2 prompt, skills inventory in `PROMPT.md` | not started, after 4 |
| 6b | the review LaunchAgent (cmux popup job) that omp's `install.sh` provisions | not started |

Merged work follows the plan's own rule: each PR passed `omp-review.sh` on its final commit and CI, and the review found real defects in four of the five (one blocking P1 in the adapter, one in `autodream-now.sh`).

## Why PR 2 is not a port

The 35 generic fixes cannot be lifted commit by commit. A trial `git cherry-pick` of the first one conflicts in six files, and a trial `git merge omp/main` leaves 62 conflict hunks in 12 files that look mechanical but are not. They are the same decision seen in different places:

- **The L2 delivery protocol differs.** omp-autodream's L2 has no `Write` tool: it prints the report on stdout, `run.sh` slices at an `AUTODREAM_REPORT_END` sentinel, and `report_complete` requires it. cc-autodream's L2 still runs `Glob Read Write Edit`, writes the report file itself, and writes `pins.jsonl` for the Mnemopi pin step (#68). The design doc wants stdout and a sentinel, with pins in a block after it, but cc has not built that, so every L2-touching hunk of the merge picks a side of an unmade decision.
- **Engine invocations are woven through the omp additions.** The warmup, the worker, the version stamp and the fatal "omp not found" check all name `OMP_BIN` and omp flags. In cc they have to become "the L1 engine of this session's adapter". The adapter manifest already lists the flags; nothing builds the command from it yet.
- **The failure classifier reads a `.err` layout the cc worker does not write.** `failure-class.sh` expects the worker's exit code, its stdout and a log tail, which is the first thing the hardened `dispatch_l1` adds.

So PR 2 and PR 4 are one piece of work, the rewrite of `dispatch_l1` around an adapter-built engine command, and it needs these decided first:

1. **L2 delivery.** Adopt stdout plus sentinel plus a pin block now (Plan 3), or keep cc's file-based L2 and port omp's hardening around it.
2. **Where the engine command comes from.** A new `l1-argv` adapter subcommand printing a NUL-delimited argv is the least invasive; the manifest's `engine_flags_l1` is data and cannot express `--model` or the overlay path alone.
3. **L2 engine.** cc runs the `claude` CLI default model; omp runs `omp --model claude-opus-5`. The design makes it a global knob; pick the default.
4. **Model per adapter.** `AUTODREAM_L1_MODEL` is an omp-only knob today and this host sets it in omp's `config` to a neuralwatt model. Either rename it per adapter or scope it to omp.

## Cutover notes for Plan 4 (found on this host, 2026-10-03)

- Both installs have scheduled jobs and review jobs: `com.samuelreed.autodream`, `com.samuelreed.autodream-review`, `com.samuelreed.omp-autodream`, `com.samuelreed.omp-autodream-review`. Cutover has to unload the omp pair or every report opens two triage popups.
- `~/.claude/autodream` carries a `backfill.sh` and a `com.samuelreed.autodream.backfill` job that are not in this repo. Decide whether they belong in `bin/` before the install is repointed.
- `~/.omp/agent/autodream` symlinks into `~/git/oss/omp-autodream`; `~/.claude/autodream` symlinks into this checkout. The live nightly runs whatever is checked out, so a merged PR changes the cc nightly once the main checkout is fast-forwarded.
- omp-autodream PR 16 (advisor sidecar schema) is merged there; its `overlap-stats.sh` change is ported (https://github.com/STRML/cc-autodream/pull/84), its prompt text is not.

## omp-only commits (60, from `e231314..omp/main`)

Status: **in cc** already present; **PR n** ported by that PR; **n/a** not needed, with the reason; **verify** classification pending a read of the cc code in the named PR.

| Commit | Subject | Status |
| --- | --- | --- |
| `216c791` | permanent provider refusal defers the date (#37) | PR 2 |
| `dfd39a1`, `7f89556`, `b67c2f1`, `5f7ddaa` | question-streaks `clear` fixes | in cc (#71, #75) |
| `1d11e03`, `b72f0e4`, `cb76639`, `600e6dd`, `4eea84d`, `764d77d` | question-streaks watermark, lock, escalation | in cc (#71, `4e5aaf5`) |
| `3c2215f`, `8166f38`, `d905ad7` | docs for streaks and the drift check | in cc (CLAUDE.md carries both) |
| `e1e8f10`, `232c94c` | sibling drift check | in cc (`4b19c8c`); retires with the sibling |
| `d771d59` | X 16-character chunk hash | in cc (`7f11f64`) |
| `896a971` | drop the rtk grep gotcha | in cc (`c2a5eee`) |
| `fa0a317`, `9210dd9`, `acff8a8`, `05d6ead`, `cdfdf3b`, `6ca1584`, `b19ec84`, `676d9b0`, `a9912d4`, `7eda1a8` | `failure-class.sh` and the oversized gate classification | PR 2 |
| `16a3bf5`, `33bf9b1`, `cd309b6` | unmeasured sidecars and skills | PR 2 (sidecar rules) and PR 6 (label parts) |
| `fa5a430`, `d63cf3e` | no route to the API defers the date | PR 3 |
| `d6438d5` | six nights of empty stubs: warmup, breaker; three-harness changelogs | PR 3 (warmup, breaker) and PR 7 (changelogs) |
| `1ff1b59` | mnemopi first-turn recall killed workers | PR 3 (overlay) |
| `e95084d` | bound each L1 worker (#17) | PR 3 |
| `36282e5` | resolve omp from PATH, record the build (#18) | PR 4 (engine resolution per adapter) |
| `4507066`, `0129fc0` | changelog cache guards, warmup wants `ok` | PR 7 and PR 3 |
| `e95e2f2` | launchd ownership reads every plist, warmup timeout validated | PR 6 and PR 3 |
| `bbb4d4b`, `e70492a`, `2ef3031`, `ec829a4`, `aacbc0a`, `1ee66e4` | launchd label ownership, install hardening, stale paths | PR 6 |
| `d1d0cfb` | macOS runners end TMPDIR with a slash | PR 6 (test) |
| `387e7bc`, `87e2588`, `10e1c52`, `90e535b`, `bc9ba5a`, `c8303f6`, `1fef17d`, `3c7587f` | review.sh cmux popup panel rounds 1 to 7 | PR 8 |
| `c16318a` | close out the /code-review sub-80 cleanups (#8) | verify in PR 8 |
| `9db799d` | stop L2 memory writes; broaden the skill-coverage walk for OMP (#3) | n/a for memory (cc routes pins to Mnemopi, #68); skill walk in PR 5 |
| `790d1b6` | README rewrite for the OMP port | n/a (the unified README replaces it, Plan 4) |
| `6c41c46` | port cc-autodream to OMP | PR 1 and PR 4 |
| `0dffef5` | retire `compliance_markers` telemetry | verify: cc `session-stats.sh` still computes it; port with PR 4 |

Not a commit but part of the work: omp-autodream #16 (advisor sidecar schema, open, being merged into omp-autodream first) lands in PR 4, and its `SESSION_TRIAGE.md` and `PROMPT.md` text lands in PR 5.

## Remaining after this plan

- Plan 3: pure-stdout `PROMPT.md`, sentinel grammar tests.
- Plan 4: `tests/replay.sh`, cut the live nightly over (`~/.omp/agent/autodream` currently symlinks into omp-autodream), rename to `STRML/autodream`, archive omp-autodream and `autodream-merge` with pointers. Not started, and not to be started without Sam: it touches the live install.
