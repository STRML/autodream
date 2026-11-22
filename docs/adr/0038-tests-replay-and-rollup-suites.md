# 0038: replay and rollup suites

Status: accepted · Date: 2026-11-22 · Code: `tests/replay.sh` (`replay_artifacts`, `replay_ingest`, `cmp_num`, `cmp_num_warn`), `tests/replay.sh` (`replay_ingest`), `tests/rollup.sh` (the fixture block and the assertions after it)

## a difference an archive explains is a WARN, and only checks about this code can FAIL

### Context

`tests/replay.sh` runs the current runner's code over archived data and compares each figure with the `run-stats.txt` the original night wrote. An archive is not frozen to the code under test: it can predate a counter, be rebuilt or pruned since, or have been counted by an older rule. Measured cases:

- The 2026-05-28 claude archive, the tool's first day, holds one findings JSON with no `findings` array.
- 2026-09-13 holds 7 findings JSONs where its run-stats recorded 9.
- Before advisor sidecars were dropped from the overlap pass (omp-autodream 2026-08-21), the old figure counted each advisor against its parent, and its sidecars carry no `is_advisor`. The replay therefore reads lower by design.
- A directory rebuilt in place keeps the sidecars of earlier runs, which the overlap pass reads along with the latest run's.
- A session resumed later changes its mtime, so a corpus can move after the night it was counted.

### Decision

- Counts of what is on disk (findings written, errors, gated, sessions found or triaged, overlap) go through `cmp_num_warn`: a mismatch is a WARN. A shape violation in an archive is reported with its count and is a WARN too, because the current runner would have refused that file and retried or stubbed it.
- The checks that can FAIL (`cmp_num`) are the ones about this code: failure classification, skill-field enforcement, that the overlap pass and the oversized gate run, and that every staged session is enumerated and triaged.
- The skill-field comparison covers only sessions the enforcement pass would touch. Gated stubs and error records are never rewritten by it and carry no skill fields.
- Where the cause is known, the WARN names it: the advisor count, or the sidecar count of a rebuilt directory against the run's session count.

### Consequences

Turning a WARN into a FAIL makes the replay fail on archives that are correct for their time. Add a FAIL only for a figure the current code computes alone. A new explained difference should say what explains it in the WARN text. The harness is kept honest by `test_replay_harness_works_on_synthetic_data` in `tests/run-all.sh`.

## ingest replays a copy of the store, staged from the report day to five years after

### Context

`run.sh` enumerates with `find`, which does not follow a symlinked root, so a sandbox whose root is only a link finds nothing. The real store must also never be written. The runner places a session in a day by the timestamps inside it, not by mtime (#113), so a session written to again after its day closed still belongs to that day. Staging only files last modified on the day would drop exactly those sessions. The runner's own reach is the report day plus five years (`ENUM_END` in `run.sh`).

### Decision

- The sandbox holds a copy of every `*.jsonl` modified from the start of the date until five years after it (`pdate_shift "$date" 5 y`), with mtimes preserved. The runner applies its own window to what is staged, so an older runner, which bounds mtime itself, reads the same copy.
- Files from later days are staged too. A run whose window holds none of them is a quiet day and the runner counts it in `sessions_out_of_window`. That is a WARN. Staged files with no enumerated session and nothing counted out of window is a FAIL, because the runner lost them.
- The sandbox is removed on every exit path, since it holds real transcripts, and kept only when `REPLAY_KEEP` is set.

### Consequences

Narrowing the staging window to the day itself would make the replay pass while leaving out the resumed sessions it exists to check. The five years track `ENUM_END`; if the runner's reach changes, change both. See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to (the report-day window, #113)".

## the fixture holds 224 sessions and every expected number is a literal derived by construction

### Context

L2's Glob and directory reads stop at 200 entries. On 2026-10-31 the findings dir held 2683 entries (885 findings JSONs, 885 `.served`, 885 sidecars, about 28 side files), so L2 counted from a 90-file sample and never saw `fanouts.tsv`. A fixture under 200 entries would pass against a script that still listed the directory. The production decision is in `bin-b-rollup-counting-outside-l2`.

### Decision

The fixture holds 224 sessions plus every side file that shares the directory (`pins-like.json`, `outside-worklist/`, `.err`, `run-stats.txt`). The totals are worked out from how the fixture is built: 100 + 90 + 20 + 5 + 3 + 1 + 1 + 1 + 1 + 1 + 1 = 224 sessions, with 125 triaged, 95 gated, 1 error and 3 unreadable, so the ungated set the report calls N is 129. No expected value is recomputed with the same `jq` the script uses.

Fixture cases whose purpose is not visible from the code:

- Session 6 carries one category at two severities and counts once in that category's `all` row.
- Session 12's sidecar predates `sandbox_shape_denies` and 13's holds a string. Both read blank, never 0, so a degraded measurement is not a measured zero.
- Gated omp children (221-225) are nested but have no `fanouts.tsv` row, since that file holds ungated rows only.
- Advisors 231-233: `sandbox_friction` is a tool-behavior finding that L1 suppresses for advisors, so it is a triage failure and never a ranked pattern. 232 and 233 both carry `memory_miss:medium`, a content finding that counts once, as the parent's.
- Session 245 is a gated stub whose `findings` is not an array. It is unreadable, because the array check comes before the gate.

### Consequences

Keep the fixture over 200 sessions and keep the expected numbers literal. When a case is added, update the totals line by hand from the construction.

## Background: Replay: does this code read real data the way the code that wrote the archive did

This section was moved here from the former CLAUDE.md. Its original title: "Replay: does this code read real data the way the code that wrote the archive did".

`tests/replay.sh` runs the unified runner's code over archived data, offline and read-only. `--artifacts <findings-dir>...` recomputes shape, failure classes, enforced skill fields, the overlap pass and the oversized gate from a findings directory on disk and compares each figure with the `run-stats.txt` the original run wrote. `--ingest <adapter> <session-root> <date> [--against <findings-dir>]` stages a copy of the sessions modified from that date until five years after, the runner's own reach (the enumeration `find` does not follow a symlinked root, so a link would find nothing; the window is the runner's job, so an older runner reads the same copy), installs into a throwaway home, runs the whole pipeline with `tests/mock-claude.sh` as every engine, and checks that every session was enumerated, normalized, given a sidecar and a findings JSON. Output is PASS, WARN or FAIL per check; only a FAIL fails the run. A WARN is a difference the archive explains (a counter it predates, a corpus that moved, a rebuilt directory, advisor sidecars the old runner did not flag), and the line says which. It cannot say whether a model would triage these sessions well, because the engines are mocks. Results for this host's archives are in `docs/plans/2026-10-03-omp-adapter.md`; `test_replay_harness_works_on_synthetic_data` keeps the harness itself honest.
