# 0010: Counting and self-audit: rollup, run-stats and the measured-or-unknown rule

Status: accepted · Governs: `bin/overlap-stats.sh`, `bin/oversized-gate.sh`, `bin/pending-triage.sh`, `bin/rollup.sh`, `bin/run.sh`, `bin/session-stats.sh`, `bin/lib-project.sh`

This record holds 34 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Self-audit](#background-self-audit)
- [Background: Degraded measurements must say so, not read as zero](#background-degraded-measurements-must-say-so-not-read-as-zero)
- [Background: Skill fields are measured, not guessed (omp-autodream 2026-09-04)](#background-skill-fields-are-measured-not-guessed-omp-autodream-2026-09-04)
- [overlap counts distinct parent-session pairs from sidecars, and drops advisor and nested-worker sidecars](#overlap-counts-distinct-parent-session-pairs-from-sidecars-and-drops-advisor-and-nested-worker-sidecars)
- [the oversized gate recomputes from artifacts and never reads a clean result from a measurement that did not happen](#the-oversized-gate-recomputes-from-artifacts-and-never-reads-a-clean-result-from-a-measurement-that-did-not-happen)
- [a linked script finds its sibling helpers by following its own symlink, because `install.sh` links each script on its own](#a-linked-script-finds-its-sibling-helpers-by-following-its-own-symlink-because-installsh-links-each-script-on-its-own)
- [category tallies count an advisor under its parent and drop its tool-behavior findings](#category-tallies-count-an-advisor-under-its-parent-and-drop-its-tool-behavior-findings)
- [the per-session and per-category counts are computed by rollup.sh, not by L2](#the-per-session-and-per-category-counts-are-computed-by-rollupsh-not-by-l2)
- [a failed stage fails rollup.sh and publishes nothing](#a-failed-stage-fails-rollupsh-and-publishes-nothing)
- [a malformed findings JSON or sidecar costs its own row's cells, never the table](#a-malformed-findings-json-or-sidecar-costs-its-own-rows-cells-never-the-table)
- [rollup takes each session's source, project and cwd from the runner's environment, not from files a worker can write](#rollup-takes-each-sessions-source-project-and-cwd-from-the-runners-environment-not-from-files-a-worker-can-write)
- [rollup status mirrors run.sh's report N, with one deliberate difference](#rollup-status-mirrors-runshs-report-n-with-one-deliberate-difference)
- [the sidecar carries no compliance_markers count](#the-sidecar-carries-no-compliance_markers-count)
- [sandbox-shape denies are counted here, anchored to the start of the tool result](#sandbox-shape-denies-are-counted-here-anchored-to-the-start-of-the-tool-result)
- [skill invocation and authoring are counted by the stats script, as two fields](#skill-invocation-and-authoring-are-counted-by-the-stats-script-as-two-fields)
- [L1 outcome counters are derived after the fact from the findings dir, and failures are classified before they are read as size evidence](#l1-outcome-counters-are-derived-after-the-fact-from-the-findings-dir-and-failures-are-classified-before-they-are-read-as-size-evidence)
- [The count of already-valid findings is recorded before any worker runs](#the-count-of-already-valid-findings-is-recorded-before-any-worker-runs)
- [Nested transcripts find their parent by walking up, and the session total is split into top-level and nested](#nested-transcripts-find-their-parent-by-walking-up-and-the-session-total-is-split-into-top-level-and-nested)
- [The overlap pass is global and carries a measured marker so a zero is never a non-measurement](#the-overlap-pass-is-global-and-carries-a-measured-marker-so-a-zero-is-never-a-non-measurement)
- [The oversized-transcript counters are derived post hoc by walking the worklist, with unmeasurable sessions excluded and unparseable sidecars counted](#the-oversized-transcript-counters-are-derived-post-hoc-by-walking-the-worklist-with-unmeasurable-sessions-excluded-and-unparseable-sidecars-counted)
- [L2 counts from rollup.tsv, categories.tsv and findings.tsv, written by the runner from trusted inputs](#l2-counts-from-rolluptsv-categoriestsv-and-findingstsv-written-by-the-runner-from-trusted-inputs)
- [run-stats stamps the commit of the code that produced it (`runner_commit`, `runner_dirty`)](#run-stats-stamps-the-commit-of-the-code-that-produced-it-runner_commit-runner_dirty)
- [run-stats records the counters that make a silent corpus shortfall visible](#run-stats-records-the-counters-that-make-a-silent-corpus-shortfall-visible)
- [the runner's git commit is read from the real checkout, and only a resolved, tracked-state-dirty answer is stamped](#the-runners-git-commit-is-read-from-the-real-checkout-and-only-a-resolved-tracked-state-dirty-answer-is-stamped)
- [run-stats names who answered L1 (login, served model, verdict, cost) and counts the unmeasured separately](#run-stats-names-who-answered-l1-login-served-model-verdict-cost-and-counts-the-unmeasured-separately)
- [run-stats keys are always emitted, and an unmeasured value says so instead of reading as zero](#run-stats-keys-are-always-emitted-and-an-unmeasured-value-says-so-instead-of-reading-as-zero)
- [run-stats records what L1 workers actually did (rounds, confinement, chunk cost)](#run-stats-records-what-l1-workers-actually-did-rounds-confinement-chunk-cost)
- [run-stats counts sessions and L1 failures so each denominator is honest](#run-stats-counts-sessions-and-l1-failures-so-each-denominator-is-honest)
- [Session stats are computed once from the final enumeration, and overlap runs after every sidecar and before the noise gate](#session-stats-are-computed-once-from-the-final-enumeration-and-overlap-runs-after-every-sidecar-and-before-the-noise-gate)
- [stale-row and per-source counts are measured from the final sidecar, and an error reads as unknown](#stale-row-and-per-source-counts-are-measured-from-the-final-sidecar-and-an-error-reads-as-unknown)
- [The mechanical skill fields are enforced from the sidecars with jq, outside the optional-python3 block](#the-mechanical-skill-fields-are-enforced-from-the-sidecars-with-jq-outside-the-optional-python3-block)
- [source provenance lives in a sidecar keyed by artifact hash, and sessions.txt stays one bare path per line](#source-provenance-lives-in-a-sidecar-keyed-by-artifact-hash-and-sessionstxt-stays-one-bare-path-per-line)
- [A session's stats are computed by its own adapter, over the live linearized conversation](#a-sessions-stats-are-computed-by-its-own-adapter-over-the-live-linearized-conversation)
- [`compute_session_stats` does not count sidecar failures: `STATS_SIDECARS_UNPARSEABLE` is initialised later, in the oversized-gate loop](#compute_session_stats-does-not-count-sidecar-failures-stats_sidecars_unparseable-is-initialised-later-in-the-oversized-gate-loop)

## Background: Self-audit

This section was moved here from the former CLAUDE.md. Its original title: "Self-audit".

run.sh writes `run-stats.txt` (raw/excluded/triaged counts, L1 rounds/done/missing/err, elapsed). PROMPT.md's "Autodream self-audit" section reads it and is told to flag self-pollution regressions (excluded count climbing), pipeline-capacity problems (oversized transcripts that blow the token budget), retry/sleep health, and to propose concrete cc-autodream source fixes since the user authors the tool. It proposes; it does not edit cc-autodream source.

## Background: Degraded measurements must say so, not read as zero

This section was moved here from the former CLAUDE.md. Its original title: "Degraded measurements must say so, not read as zero".

Two counters exist only to keep a broken measurement from looking like a real result, and any new stat should follow the same rule. `overlap_measured: yes|no` (#26) marks whether the cross-session overlap pass actually ran. `stats_sidecars_unparseable: N` (#27) counts sessions whose `*.stats.json` sidecar was missing, empty, or had no numeric `transcript_bytes`.

The sidecar counter is deliberately one number rather than a flag per stat: a broken sidecar degrades several counters at once (the noise gate and the oversized gate both read the same file), so the failure is counted once and PROMPT.md caveats the affected keys. The oversized loop walks `sessions.txt` rather than the `*.stats.json` glob — a sidecar that was never written is absent from the glob, and the session it belonged to used to vanish from `oversized_total` silently. Sizes for those sessions fall back to `wc -c` on the transcript itself, which is exactly what `transcript_bytes` holds anyway, so the #12 gate keeps a truthful number instead of a clamped 0.

The noise gate's own sidecar read still biases to triage on an unparseable sidecar and that stays — the cost is one wasted model call. What was missing there was never the behavior, only the signal.

## Background: Skill fields are measured, not guessed (omp-autodream 2026-09-04)

This section was moved here from the former CLAUDE.md. Its original title: "Skill fields are measured, not guessed (omp-autodream 2026-09-04)".

`skills_invoked`, `skills_invoked_count`, `skills_invoked_counts` and `skills_authored` come from the stats sidecar (`session-stats.sh` for claude: a `Skill` tool call or a `<command-name>` slash line is an invocation, a Write or Edit of a `SKILL.md` is authoring). After L1 the runner overwrites those four fields in every findings JSON from the sidecar. A sidecar that is missing, unreadable or lacks any of the four means the skills were not measured, so all four are removed from that findings JSON and counted in `skills_unmeasured`. A worker's own list was how a report concluded a 200-skill inventory never fires.

## overlap counts distinct parent-session pairs from sidecars, and drops advisor and nested-worker sidecars

Status: accepted · Date: 2026-11-21 · Code: `bin/overlap-stats.sh` (`build_session_list`, the `has_overlap` jq function)

### Context

GitHub issue #14 asked for a model-free, cross-session pass that counts how many session pairs had a user turn within 30 minutes of each other (the same human working two sessions at once). The unit is pinned to seconds and the default window is 1800.

Two exclusions exist because the first versions measured nothing:

- An OMP advisor sidecar is a reviewer model tailing its parent session, so it inherits the parent's user-turn timestamps by construction and overlaps it 100% of the time. Including advisors made the stat read 90-of-90 sessions on 2026-08-19 and 629-of-629 on 2026-08-20. A measure that fires on every session carries no information.
- A subagent or workflow worker behaves the same way (#79). Its transcript is a separate file inside its parent's directory, with timestamps inside the parent's span and inside every sibling's. A 30-worker fanout paired every worker with its parent and with each other, and 2026-09-08 read "78 of 72 sessions".

### Decision

- `overlap_events` is the number of distinct unordered session-id pairs `{A,B}` such that some user turn of A and some user turn of B fall within the window. A pair counts once however many turn pairs qualify. `sessions_with_overlap` is the number of distinct ids in at least one such pair.
- Session identity is the sidecar's filename stem, the 12-character sha1 of the session path that `run.sh` already uses as the findings key. It is stable and needs no re-derivation from `session_path`.
- Sidecars with `is_advisor: true`, `isSidechain: true` (a claude worker) or `nested: true` (an omp child) emit no line at all, so the stat counts concurrency between parent sessions. The flags are absent on older sidecars and `null != true` keeps those, so old findings dirs pair exactly as before.
- Gated sessions stay in. The noise gate runs after `compute_session_stats` has written every sidecar, and a gated session is real concurrent human activity that was not worth triaging, whereas an advisor pair is the same activity counted twice. The script cannot see the gate decision and does not care about it. The stat therefore includes every gated top-level session, which the Activity snapshot's session total leaves out, and PROMPT.md says so beside the figure.
- A missing or empty `user_turn_timestamps` (pre-#14 sidecars, sessions with no timestamped user turn) becomes `[]` and cannot form a pair; `has_overlap` short-circuits on an empty array.
- `has_overlap` is a two-pointer sweep over two sorted epoch-second arrays, O(|a| + |b|), and deliberately not a cross product, since a long session can carry hundreds of user-turn timestamps.
- A missing findings directory yields `{"overlap_events":0,"sessions_with_overlap":0}` and exit 0. The window argument is passed to `jq --argjson` unchecked: text that is not valid JSON (`invalid`) makes the script exit 2, and any valid JSON value is accepted.

### Consequences

`run-stats.txt` carries `overlap_measured: yes|no` so a run where this pass did not run is not read as zero overlap (docs/adr/0010-rollup-and-run-stats.md#background-degraded-measurements-must-say-so-not-read-as-zero, "Degraded measurements must say so"). A new kind of derived transcript that shares its parent's timestamps needs its own exclusion here, or the stat saturates again.

## the oversized gate recomputes from artifacts and never reads a clean result from a measurement that did not happen

Status: accepted · Date: 2026-11-21 · Code: `bin/oversized-gate.sh`

### Context

The issue #12 gate is a trailing-window judgment: the share of oversized transcripts that still failed to triage because of size. `run.sh` records one night at a time, and an old runner (#29) may omit the counters, so the gate recomputes the window from sidecars, findings and `.err` files. A false-clean reading is the failure it was written to refuse, and each rule below closes one way a clean number could appear without a measurement behind it.

### Decision

- **Size** comes from the sidecar's `transcript_bytes`. When that is missing or unusable the gate measures the transcript with `wc -c`, which is the same quantity from its original source (#27). A session whose transcript is also gone is counted as unmeasurable and left out of the ratio, never sized at 0.
- **The key** comes from `session_hash` (see `docs/adr/0002-session-enumeration.md#the-artifact-key-is-a-validated-12-character-hex-prefix-of-sha1-and-nothing-derives-it-any-other-way`), so an empty hash cannot make the gate read the wrong files.
- **A date counts as measured** only when at least one of its sessions was sized. A list of transcripts that are all gone says nothing about size (Codex review of cdfdf3b). When no date in the window was measured, the output says the gate has no evidence either way, because "no oversized transcripts" would claim a measurement that never happened (Auditor verification of 6ca1584).
- **A network-deferred run** (`network_deferred: yes`) is excluded. It stopped before its workers finished, so its oversized sessions were counted but the ones that never ran have no stub, and its share reads lower than the evidence supports. PROMPT.md already says to keep it out of the trailing week.
- **An errored session** is recognized by the top-level `error` key of its findings JSON, not by a text match: a successful file whose evidence quotes an error would otherwise count as a failure with no `.err` to classify.
- **The share** leaves out silent, provider and unclassified failures on both sides of the ratio. When nothing remains, the window gets no verdict. With zero size failures it also prints the rule-of-three bound (95% upper bound about 3/n), so a clean run is not read as stronger evidence than the sample supports.
- A window with no oversized transcripts is reported as "nothing to measure", which "is not the same as a measured 0%" and does not close #12 on its own.

### Consequences

The gate opens at 5% or more (the threshold in the help text). A new failure class has to be added to `failure-class.sh` and to both sides of the ratio here, or it is counted as a size failure by default. `tests/run-all.sh` pins the gate in the `# oversized-gate.sh: a context overflow opens the size gate` section.

## a linked script finds its sibling helpers by following its own symlink, because `install.sh` links each script on its own

Status: accepted · Date: 2026-11-21 · Code: `bin/oversized-gate.sh` (library and classifier lookup), `bin/pending-triage.sh` (`_lib`)

### Context

`install.sh` symlinks each script into `~/.claude/autodream` individually. Merging a branch swaps the script those links point at at once, while a new library link does not exist until `install.sh` is re-run. `cd -P` resolves a symlinked directory but not a symlinked file, so `$HERE` is the install dir every time, and the script stopped working entirely during that window. For `oversized-gate.sh` that was the one tool whose purpose is recomputing the #12 gate from artifacts after a runner problem. An install made before `failure-class.sh` existed linked the script but not the classifier (Codex review of b19ec84).

### Decision

- `oversized-gate.sh` looks for `lib-project.sh` beside itself, then in the directory its symlink chain ends in (up to 8 hops, relative link targets resolved against the link's directory). It exits 2 if neither has it.
- It looks for `failure-class.sh` in three places in order: its own directory, the real directory behind its symlink, then `AUTODREAM_DIR`. It exits 1 if none has it. `run.sh` uses the same walk.
- `pending-triage.sh` does the same for `portable.sh`, `lib-install-dir.sh` and `report-format.sh` through `_lib`: its own directory first, then the directory of what `readlink` returns.

### Consequences

docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "A failed worker leaves its evidence", states the classifier rule for `run.sh` and `oversized-gate.sh`. A new helper that these scripts source must be found the same way, or an update of the checkout breaks the nightly until the next `install.sh`.

## category tallies count an advisor under its parent and drop its tool-behavior findings

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`tally_categories`)

### Context

An advisor sidecar overlaps its parent session by construction. Counting both double-counts a pattern the parent and its advisor both showed, which PROMPT.md rules out. L1 suppresses `sandbox_friction`, `tool_loop` and `missed_skill` for advisors, so one that arrives is a triage failure and not a pattern.

### Decision

- Each category gets a row per severity and a row with severity `all`. A session with a high and a low finding in one category counts once in the `all` row.
- A finding is counted under its owner: the parent when the row is an advisor with a parent, else the session itself. A parent and its advisor with the same finding are one session. The example hashes stay the real ones, capped at 5.
- An advisor's `sandbox_friction`, `tool_loop` and `missed_skill` findings are not counted. L2 reads them from `rollup.tsv` as triage failures.
- Each counted session is real or sandbox by the owner's `sandbox` flag. `weighted` is `sessions_real + floor(sessions_sandbox / 4)`.
- Rows are ordered by the category's total findings (descending), then category, then `all`, `high`, `medium`, `low`.

### Consequences

docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (the `categories.tsv` bullet), states the weighting and why L2 ranks by `weighted`. The `advisor_tool_findings` figure on stdout counts what this pass skipped. A new advisor-restricted category needs an entry in both `advisor_tool` in `tally_categories` and the regex in the stdout summary.

## the per-session and per-category counts are computed by rollup.sh, not by L2

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (the whole script; `session_hashes`)

### Context

L2 reads with Glob and Read, and both stop at 200 entries. A findings dir holds three files per session plus about 28 side files. On 2026-10-31 the dir held 2683 entries for 885 sessions, and the report counted from a 90-file sample and never saw `fanouts.tsv`.

### Decision

- `rollup.sh` writes `rollup.tsv`, `categories.tsv` and `findings.tsv`, and L2 counts from those. L2 opens a single `<hash>.json` only to quote evidence.
- The script reads only inputs it names exactly: `<hash>.json`, its `.stats.json` sidecar, `sessions-source.txt` and `fanouts.tsv`.
- `session_hashes` takes only files directly in the dir whose name is 12 lowercase hex digits plus `.json`, in `LC_ALL=C` order. Sidecars, `.served` and `.err` files, side files and anything under `outside-worklist/` never match.

### Consequences

A new side file L2 needs gets a named line in `PROMPT.md`, never a glob. docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (the `rollup.tsv` bullet), records the same incident and the 224-session fixture that `tests/rollup.sh` pins it against.

## a failed stage fails rollup.sh and publishes nothing

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`set -o pipefail`, `write_atomic`, the `RAW`/`BODY`/`FINDS`/`CATS` checks, `publish`)

### Context

L2 reads the tallies as ground truth. A tally built from a pipeline that lost a stage (a `sort` with no temp space, a failed `jq` or `awk`) looks like a genuine, smaller result.

### Decision

- The script runs under `pipefail`, and each of the four build stages is checked. A failure prints a message and exits 1 before any file is written. The three files are then published one after another.
- Each output is written through `write_atomic`: a temp file beside the target and one `mv`, so a reader never sees half a file and a failed write leaves no temp behind.

### Consequences

Exit 1 from a build stage means the previous `rollup.tsv`, `categories.tsv` and `findings.tsv` are untouched. Each file is replaced atomically but the three are not one unit: a failed write of `categories.tsv` or `findings.tsv` leaves the earlier files already replaced. Removing `pipefail` or the per-stage checks turns a broken tally into an empty one that L2 reports as a quiet night.

## a malformed findings JSON or sidecar costs its own row's cells, never the table

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`session_row`, `ROW_JQ`, `UNREADABLE_JQ`)

### Context

One bad file must not blank the whole roll-up, and a cell nothing measured must not read as a measured zero.

### Decision

- Each session is read by its own `jq` call. `session_row` tries four programs and the first that succeeds wins: the record with its sidecar, the record alone (a sidecar that does not parse or is not an object), the sidecar alone (a record that does not parse), then the bare hash.
- A cell nothing measured is blank, never 0. This covers `sandbox_shape_denies` from a missing or old sidecar and from omp, which does not measure it.
- Text cells go through `@tsv`, so a tab or newline in a value cannot break a row. Category and severity words and skill names have `,`, `:` and `=` replaced, because they sit in comma lists.
- A record whose `findings` is not an array is `unreadable`, judged before the noise gate.

### Consequences

The cost is one `jq` per session (up to four on a malformed one): about 3 seconds for 885 sessions. Batching the files into one `jq` would make a single bad file fail the batch.

## rollup takes each session's source, project and cwd from the runner's environment, not from files a worker can write

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`join_source_parent`, awk `sandbox()`)

### Context

An L1 worker holds the Write tool and can rewrite `sessions-source.txt`, and a findings JSON's `project` field is model output. The `source` column and the sandbox flag must not depend on either. Trigger evals from the skill-creator run `claude -p` from `/private/var/folders/<x>/<y>/T/trig-<id>/repo`; 32 of 45 projects on 2026-11-17 were such runs, and they must not rank like real work.

### Decision

- The source comes from `AUTODREAM_SOURCE_MAP` (hash, adapter) when the runner passes it, since the runner built that map before any model ran. `sessions-source.txt` is the fallback for a standalone run.
- `AUTODREAM_SESSION_ROWS` holds hash, project and cwd rows the runner built from the session paths. `?` means the cwd is unknown. A hash in these rows is trusted: its cwd decides `sandbox`, matched against `^/private/var/folders/.+/T/trig-[^/]+(/repo)?$`.
- Only an unknown cwd falls back to the project key: the runner's key for the session, else the row's own (blank when the findings JSON does not parse). The key is matched against `^-private-var-folders-.+-T-trig-[A-Za-z0-9_-]+$`. The trial dirs are deleted after a run, so the cwd is often unresolvable and the key decides.
- Both patterns are anchored at both ends. An ordinary checkout at `/Users/x/T/trig-parser` encodes to a key that contains `-T-trig-` and is not a sandbox.
- The first row for a hash wins, in both the source map and the session rows.

### Consequences

docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (the `sandbox` column), records the same rule. A harness whose sessions have no row falls through to the row's own project key. `tests/rollup.sh` covers the cwd, the key fallback and the anchoring.

## rollup status mirrors run.sh's report N, with one deliberate difference

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`ROW_JQ` status expression); `bin/run.sh` (`compute_fanout_stats`, `fanout_rows`)

### Context

L2 counts the report's N from `rollup.tsv`, and the runner already computed N in `compute_fanout_stats`. Two numbers for one quantity would drift.

### Decision

- `status` is `unreadable` when `findings` is not an array (checked first), `gated` for a `below_noise_gate` stub, `error` when the record has an `error` key, else `triaged`. Every status except `gated` is the set `compute_fanout_stats` calls N.
- One difference remains: a gated stub whose `findings` is not an array is `gated` to `compute_fanout_stats`, which reads the text, and `unreadable` here, because the array check comes first.
- `nested` is the sidecar's `isSidechain` or `nested`, the same test `fanout_rows` applies.
- `parent` comes from `fanouts.tsv`, which lists ungated workers only, so a gated child reads nested with a blank parent.

### Consequences

Change the status expression and `compute_fanout_stats` together, or the report's N and the tallies disagree.

## the sidecar carries no compliance_markers count

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh` (the output object)

### Context

The sidecar used to count compliance markers. Retired 2026-10-30 (omp: 2026-08-08): agents follow the retry and delegation rules without typing the marker line, so the count measured silence.

### Decision

The key is absent. `adapters/omp/triage.md` records the same retirement for omp.

### Consequences

Do not add a marker count back as a proxy for rule compliance. Measure the behavior the rule governs.

## sandbox-shape denies are counted here, anchored to the start of the tool result

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh` (`$sandbox_shape_denies`)

### Context

L1 stopped scoring the sandbox-shape guard's denies as `sandbox_friction` (#175), so this count is the only place a session that keeps hitting the guard shows up. Each deny is a turn spent on a `dangerouslyDisableSandbox` the guard refused. A Read or grep of a file that mentions the guard holds the same words mid-text; measured 2026-11-03: 52 real denies and 1 such echo in one session. docs/adr/0001-runner-lifecycle.md#background-where-state-lives names the field under `rollup.tsv`.

### Decision

Count `tool_result` blocks with `is_error` true whose text (a string, or the joined text blocks) matches `\A\s*(<tool_use_error>)?\s*sandbox-shape: `, bare or inside `<tool_use_error>`.

### Consequences

Loosening the anchor makes quoted documentation count as denies. If the guard changes its prefix, change the pattern.

## skill invocation and authoring are counted by the stats script, as two fields

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh` (the `$skills_invoked` and `$skills_authored` jq bindings)

### Context

The L1 model used to fill the skill fields in, and a guess ranked as a count is wrong. docs/adr/0010-rollup-and-run-stats.md#background-skill-fields-are-measured-not-guessed-omp-autodream-2026-09-04, "Skill fields are measured, not guessed", says the runner now overwrites them from this sidecar. "Wrote five skills, invoked none" is a different finding from "ignored the inventory", so the two cannot share a field.

### Decision

- Invocation is a `Skill` tool call (`input.skill`) or a slash command, which Claude Code records as a user line carrying `<command-name>/name</command-name>`.
- Authoring is a `Write`, `Edit` or `MultiEdit` whose path is a `SKILL.md` under a `skills/` directory.
- Claude Code's own commands (`/clear`, `/model` and the rest of the list in the jq `IN(...)` filter) are not skills. The list is best effort: a command added later counts as a skill until it is named there.

### Consequences

Update the built-in command list when Claude Code adds a command, or a session that only ran it measures as having invoked a skill.

## L1 outcome counters are derived after the fact from the findings dir, and failures are classified before they are read as size evidence

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `L1_ERRORED*`, `GATED`)

### Context
- A worker that ran to completion but could not fit the transcript writes a findings JSON carrying a top-level `error` key with empty findings. These are not `.json.err` files, so `l1_err_files=0` masked them.
- Each noise-gate decision happens inside an independent xargs subshell with no shared state to increment.
- A provider refusal or a worker that died silently is not evidence about transcript size. See docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, 'A failed worker leaves its evidence, and the failure is classified', and `bin/failure-class.sh`.

### Decision
- In-band failures are counted explicitly (`L1_ERRORED`) by walking the findings JSONs with `findings_has_error`, so the self-audit can alarm on a high extraction-failure rate (slimming should drive it to zero).
- Every stub is counted, then its surviving `.err` is classified (`classify_failure`: silent, provider, unclassified) before the self-audit decides whether the failure says anything about size.
- `GATED` is counted from the findings dir (files containing `"skipped": "below_noise_gate"`) rather than from a shared counter.

### Consequences
- Do not move these counts into the worker subshells; the increments are lost.
- Do not read `l1_err_files` alone as the failure count.

## The count of already-valid findings is recorded before any worker runs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `L1_PRECACHED`)

### Context
Without it, a re-run after a partial crash shows an "impossible" `l1_elapsed_seconds` (for example 2s for 36 sessions), because the dispatcher's idempotent skip exits every worker instantly. The aggregator's self-audit needs the count to tell "fast run" from "broken timer".

### Decision
Before any worker runs, `L1_PRECACHED = COUNT - l1_missing_count`, the sessions in the worklist that already have a valid findings JSON. It feeds `l1_sessions_already_done_at_start` and `l1_sessions_freshly_processed`.

### Consequences
- Measure it before the first dispatch; after it the number is the run's own output.

## Nested transcripts find their parent by walking up, and the session total is split into top-level and nested

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`session_parent`, `fanout_rows`, `compute_fanout_stats`)

### Context
Issue #79: a parent that spawned thirty workers read as thirty-one sessions in the report. A child lives in a directory named after its parent's file: claude nests workers at `<bucket>/<id>/subagents/` and `<bucket>/<id>/subagents/workflows/wf_*/`, omp at `<bucket>/<stamp>_<id>/`.

### Decision
`session_parent` walks up from the transcript (at most 6 levels) until `<dir>.jsonl` is a file, which finds the parent at any depth. `fanout_rows` writes one `worker-hash<TAB>parent-hash` row per nested transcript in `sessions.txt` (a stats sidecar with `isSidechain` or `nested` set: a claude subagent or workflow worker, an omp advisor or task child). When the parent file is gone, the parent hash is taken from the path that file would have (the part before `/subagents/` plus `.jsonl` for a claude worker, else the transcript's directory plus `.jsonl`, the string `session_parent` would have returned), so a fanout still groups. The rows are held in the runner's memory, like `session_rows`, because L1 and L2 can rewrite the worklist. `compute_fanout_stats` runs after L1 (so a gated stub drops out, the same set the Activity snapshot's N counts), sets `FANOUT_TOP`, `FANOUT_NESTED`, `FANOUT_PARENTS` and `FANOUT_LARGEST`, and writes `fanouts.tsv` for L2 from `FANOUT_ROWS`, which ran before any model did.

See docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (`fanouts.tsv`).

### Consequences
The depth cap of 6 bounds the walk; a new nesting deeper than that needs the cap raised.

## The overlap pass is global and carries a measured marker so a zero is never a non-measurement

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_overlap_stats`)

### Context
Issue #14 (cross-session "multi-clauding" stat) and #26. Overlap is a GLOBAL, cross-session computation: it cannot be done per-session inside `compute_session_stats` or `dispatch_l1`'s xargs subshells, which only ever see one session at a time. A genuine zero-overlap night must not be confusable with a non-measurement.

### Decision
`compute_overlap_stats` runs once `compute_session_stats` has written every sidecar (each carries the mechanical `user_turn_timestamps` array). It sets `OVERLAP_EVENTS` and `SESSIONS_WITH_OVERLAP` (default 0/0 on any failure or absence, so the run-stats writer always has a value and never aborts the pipeline) and `OVERLAP_MEASURED`: 1 when `overlap-stats.sh` ran and produced parseable output (even 0 pairs is a legitimate result), 0 when the script was missing or not executable, produced no output, or produced output `jq` could not extract both fields from. Each of those gets its own explicit "overlap not measured" log line, which says the counts were left at 0/0. The old comment called the marker a tri-state, but it only ever holds 1 or 0; the "three" are the three not-measured causes.

See docs/adr/0010-rollup-and-run-stats.md#background-self-audit, "Self-audit" (`overlap_measured: yes|no` (#26)).

### Consequences
A new failure path must set `OVERLAP_MEASURED=0` and log its own reason, never fall through to the "overlap: 0 pair(s)" line.

## The oversized-transcript counters are derived post hoc by walking the worklist, with unmeasurable sessions excluded and unparseable sidecars counted

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `OVERSIZED_*` loop over `$SESSIONS_LIST`); mirrored by `bin/oversized-gate.sh`

### Context
- Issue #12 proposes chunk-summarizing oversized transcripts instead of slimming them; that implementation is BLOCKED pending evidence it is needed. The two counters are the measurement: how many triaged sessions exceeded `AUTODREAM_SLIM_BYTES` (the same threshold `dispatch_l1` checks before calling `slim-transcript.sh`), and of those how many still ended in an in-band failure despite the fallback stack (slimming, chunked-Read guidance, metadata-stub path). Gate: if `oversized_errored / oversized_total` sustains >= 5% over a trailing week, issue #12's gate has opened; below that the fallback stack is doing its job. The runner only records the counters; the L2 self-audit and the human do the trailing-week judgment. See docs/adr/0010-rollup-and-run-stats.md#background-self-audit, 'Self-audit' and 'Degraded measurements must say so, not read as zero'.
- The per-worker `sz` variable at dispatch time lives in an xargs subshell with no shared state to increment, so the counter is re-derived post hoc from the `*.stats.json` sidecars' `transcript_bytes`, written before dispatch (same pattern as `GATED` and `L1_ERRORED`).
- #27: a sidecar that was never written (`compute_session_stats` deletes the file whenever `session-stats.sh` fails) is absent from a `*.stats.json` glob, so the session it belonged to used to drop out of `oversized_total` without appearing anywhere. Stale sidecars from an earlier enumeration also snuck into the count.
- `STATS_SIDECARS_UNPARSEABLE` is the shared health signal for every sidecar consumer: one broken sidecar corrupts several counters at once (the noise gate in `dispatch_l1` reads the same file), so failures are counted once here rather than each stat carrying its own measured/not-measured flag. A sidecar counts as unparseable when it is missing, empty, not valid JSON, or carries no numeric `transcript_bytes`. The noise gate's own read is deliberately left alone: it already biases to triage on an unreadable sidecar (worst case, a wasted model call), and the only thing missing there was the signal.
- A session with no derivable hash has no sidecar. An earlier version counted it in `oversized_total` but never in `oversized_errored`, and its comment claimed that dropping the session biased the #12 gate closed. The reasoning was inverted: the gate is `oversized_errored / oversized_total`, so padding the DENOMINATOR with sessions whose size was never read pushes the share DOWN and holds the gate closed; dropping one raises it. That version also made the runner and `oversized-gate.sh` disagree about the same findings dir: run.sh reporting `12 / 0` and GATE CLOSED where the gate tool reported 0 oversized and 12 unmeasurable. Conflating a keying failure with a sidecar parse failure hid the former inside a counter about file contents.
- A clamped 0 size for an unparseable sidecar would bias the #12 gate toward staying closed, which is the whole point of the issue. `transcript_bytes` is `wc -c` of the file the stats were computed over, which is the file the worker reads (the transcript, the normalized copy, or the day slice).

### Decision
- The loop walks `$SESSIONS_LIST`, not the sidecar glob, so every triaged session is accounted for exactly once, whatever state its sidecar is in.
- A session whose hash cannot be derived is `OVERSIZED_UNMEASURABLE`: excluded from both counters, logged, and given its own counter (as `oversized-gate.sh` does for the same case).
- A missing or non-numeric `transcript_bytes` increments `STATS_SIDECARS_UNPARSEABLE` and the size falls back to `wc -c` of the transcript itself: the same quantity from its original source for a single-day transcript, and the whole file (an overstatement) for a multi-day one. It is not an estimate.
- An oversized session whose findings JSON carries an `error` counts in `OVERSIZED_ERRORED`, split by `classify_failure` into silent, provider and unclassified.

### Consequences
- Keep the runner and `bin/oversized-gate.sh` in agreement on what is unmeasurable.
- Never pad the denominator with sessions whose size was not read, and never clamp an unreadable size to 0.
- The comments being replaced pointed at line numbers ("line ~309" for the dispatch-time `sz`, `oversized-gate.sh:105` for the unmeasurable handling) that had already gone stale; refer to the `dispatch_l1` worker's size read and to `oversized-gate.sh`'s `session_hash ... || unmeasurable` branch by name, not by line.

## L2 counts from rollup.tsv, categories.tsv and findings.tsv, written by the runner from trusted inputs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`write_rollup`)

### Context
L2's Glob and directory reads stop at 200 entries. On 2026-10-31 the findings dir held 2683 entries for 885 sessions, and the report counted a 90-file sample and never saw `fanouts.tsv`.

### Decision
`write_rollup` runs after the skill-field pass (which rewrites the fields the roll-up reads) and after `compute_fanout_stats` (whose `fanouts.tsv` gives each worker its parent). It passes `rollup.sh` the source map and the session rows (hash, bucket, cwd) built before any model ran, not `sessions-source.txt` or `session-cwds.tsv`, which an L1 worker can rewrite. A failure logs, says so in `run-stats.txt` (`rollup: helper missing` or `rollup: failed`) and leaves no stale file from an earlier run, so L2 reports the counts as unavailable rather than wrong. On failure all three files are removed together: one file without the others would be read as a whole roll-up. A success is judged by `rollup.sh`'s last line starting `rollup: rows=`; its counters go into run-stats as `rollup_<name>`, plus `sandbox_sessions` and `sandbox_shape_denies_min`.

See docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (`rollup.tsv`, `categories.tsv`, `findings.tsv`).

### Consequences
Never source the roll-up inputs from a file in the findings dir.

## run-stats stamps the commit of the code that produced it (`runner_commit`, `runner_dirty`)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the full-run `run-stats.txt` block; also the zero-session block)

### Context
Issue #29. `install.sh` symlinks `~/.claude/autodream/*.sh` straight at the repo working tree, so the nightly executes whatever is checked out at 03:15: a tree sitting behind origin runs old code even though the fix is merged. That cost real data twice: the 2026-07-24 `overlap-stats.sh` dangle, and a tree stuck on a local commit from 2026-07-20 to 2026-07-24 that wrote four nights of `run-stats.txt` with no `oversized_*`/`gated`/`overlap_*` keys at all. Absent keys are a terrible signal: they read as "this stat did not apply" rather than "this runner predates the stat", and telling those apart took a reflog dig both times. See docs/adr/0001-runner-lifecycle.md#background-which-code-actually-ran-runner_commit, 'Which code actually ran (`runner_commit`)'.

### Decision
`runner_commit` and `runner_dirty` are the first keys, straight after the header line, of every `run-stats.txt` (`$RUNNER_COMMIT`, `$RUNNER_DIRTY`), so the runner's age is legible from the artifact itself. A `run-stats.txt` that is missing keys means an old runner, not a stat that did not apply.

### Consequences
- Keep both keys on every path that writes run-stats (full run, zero-session stub, fatal exit).

## run-stats records the counters that make a silent corpus shortfall visible

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the full-run `run-stats.txt` block: `session_roots`, `sessions_rejected_path`, `sessions_out_of_window`, `session_window`, `sessions_windowed`, `roots_*`, `adapters_enabled`)

### Context
Each of these was a way for a night to look quiet while the corpus was short. See docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, 'Session roots: one dir is not the corpus', 'Which day a session belongs to (the report-day window, #113)' and 'Self-audit'.
- `session_roots` (colon-count + 1) is its own stat so a regression to single-root scanning is visible from the artifact.
- Paths dropped at enumeration because a line-based `sessions.txt` cannot hold them: a nonzero value means a real transcript exists that no report will ever mention.
- Files modified since the day began that hold no record inside it (a session still being written on a later day, or one touched after its own day) belong to another day's report. A count here keeps a night whose files all fell outside the window from reading as a quiet one. `session_window` says whether the timestamp window was in force at all: a stats file with it off, or without the key, was placed by file mtime alone. `sessions_windowed` is how many triaged sessions spill outside the day, whose stats and L1 read are cut to the day.
- Roots whose enumerator errored yet still returned paths: the night's corpus may be short by an unknown amount, not a failure but not a clean read either, and the aggregator should not treat the totals as complete.
- Adapter refusals that still left claude accepted (a third-party adapter failing containment, a mismatched manifest name, a lost exec bit) are otherwise completely silent: same silent-shortfall class as `overlap_measured` and `stats_sidecars_unparseable`, recorded as `adapters_rejected`.
- A source that drops to zero on a day the user worked in it is the signal that its ingest broke, invisible without a per-source count.

### Decision
`run-stats.txt` carries `session_roots`/`session_roots_list`, `sessions_rejected_path`, `sessions_out_of_window`, `session_window`, `sessions_windowed`, `roots_partially_enumerated`/`roots_unavailable`/`roots_failed`, `adapters_enabled` with `sessions_by_source` (the per-source count) and `adapters_rejected` on every full run, written even when zero so that a zero means something.

### Consequences
- A new way for a night to be short needs its own counter here, and the same key on the zero-session path (see `zero-session-night-writes-full-run-stats-and-still-cleans-up`).
- Do not fold these into one combined number.

## the runner's git commit is read from the real checkout, and only a resolved, tracked-state-dirty answer is stamped

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`RUNNER_REPO_DIR`, `RUNNER_COMMIT`, `RUNNER_DIRTY`)

### Context
Issue #29: `run-stats.txt` must say which code actually ran. `install.sh` symlinks each script individually into `~/.claude/autodream`, so that directory is real and has no `.git`, and `cd "$(dirname "$0")"` resolves symlinked directories but not a symlinked file: it lands in the install dir every time. Six of the eight runs through 2026-08-03 wrote `runner_commit: unknown` for that reason alone; the two that stamped a sha were launched from the repo by hand. See docs/adr/0001-runner-lifecycle.md#background-which-code-actually-ran-runner_commit, "Which code actually ran (`runner_commit`)".

### Decision
- The repo dir comes from the symlink walk (`RUNNER_SRC`, see `runner-symlink-walk-hop-cap`), not from `SCRIPT_DIR`, which is a working directory and not a checkout (`SCRIPT_DIR` stays as it is: helper lookup genuinely wants the install dir).
- Still a symlink after the walk means it gave up (a cycle, or a chain past the cap) rather than arriving anywhere: `RUNNER_REPO_DIR` is empty. Resolving the truncated path would stamp whatever checkout it happens to sit in, and a confidently wrong sha is worse than no sha.
- The empty case short-circuits before git rather than leaning on git to reject it: `git -C "" rev-parse HEAD` does NOT fail, it silently stays in `$PWD` and answers for whatever repo the caller launched from, and launchd starts this job from an unrelated cwd, so git would stamp a stranger's sha.
- `git status --porcelain --untracked-files=no` for the dirty check: "dirty" warns that the run used code that exists in nobody's history, which only tracked modifications can cause. Counting untracked files made the first production run report `runner_dirty: yes` over a stray scratch directory, the kind of false alarm that gets a signal ignored.
- Everything degrades to `unknown` / `no`: a tarball install with no git, or no git binary, is a supported way to run this and must not fail the run.

### Consequences
A `run-stats.txt` that is missing keys (rather than holding odd values) means an old runner. Keep the empty-dir short-circuit.

## run-stats names who answered L1 (login, served model, verdict, cost) and counts the unmeasured separately

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`: `login_<src>`, `l1_served_*`, `l1_cost_*`)

### Context
- `l1_model_<src>` is the model each adapter's workers ran and `l1_engine_<src>` the adapter whose engine ran them (which `AUTODREAM_L1_ENGINE_<NAME>` can move off the source), one key per source that had sessions tonight, so a report that reads differently can be traced to the engine that produced it.
- `login_<src>` records who each engine the run used ran as (`engine_login_ok`), and `l1_served_models` records which models answered the L1 calls recorded for this date in `l1-served.tsv`, so a report traces to the login and model behind it. The cost is the engine's own estimate at API prices, not what a subscription bills.
- `l1_served_mismatch` is the adapter verdict (column 6 of `l1-served.tsv`), the same one `AUTODREAM_L1_REQUIRE_SERVED` acts on. A call the engine reported no model for (omp has no `served` verb), or a row written before the verdict existed, is unmeasured: counted on its own line (`l1_served_unmeasured`), never as a match or a mismatch.
- `l1_cost_unmeasured` counts the calls the cost sum leaves out because their engine reported no cost (omp, or a claude call with no result object), so an all-omp night reads `0.0000` beside a count, not alone.

### Decision
Mismatch, unmeasured and cost-unmeasured are separate counters; with no `l1-served.tsv` all of them print their zero/none defaults. See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "Who starts the L1 worker" ("What answered, and whether it counts").

### Consequences
Folding unmeasured into match or mismatch would make an omp-only night look verified, or a cost of `0.0000` look measured. The cost number is an API-price estimate: never present it as spend.

## run-stats keys are always emitted, and an unmeasured value says so instead of reading as zero

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`, the post-L1 appends `x_queryid_source`, `l2_engine`/`l2_model`, and the citation check)

### Context
Several keys exist only because a missing or zero value would otherwise be indistinguishable from "this runner predates the key" or "the measurement did not run". The comments being retired say so key by key:

- `adapters_rejected`: refusals that still left claude accepted (a third-party adapter failing containment, a mismatched manifest name, a lost exec bit) are otherwise completely silent. Same silent-shortfall class as `overlap_measured` and `stats_sidecars_unparseable`: a zero here has to mean something.
- `overlap_measured` (#26; the overlap stat itself is #14, `compute_overlap_stats`) disambiguates a genuine zero-overlap night from the script not running or producing usable output. The two count keys (`overlap_events`, `sessions_with_overlap`) are always emitted (0 when unmeasured) so existing consumers never hit a missing key.
- `unassembled_dates` (#36): other dates triaged and never assembled. Empty means none in the window, which is the reading that matters; this is the key that gets a killed run noticed the next morning instead of during an unrelated investigation two days on.
- `legacy_marker_reports`: always emitted, even empty, so a reader never has to tell "no legacy reports" apart from "this runner predates the key", the same ambiguity the marker epoch exists to resolve.
- `l2_engine` / `l2_model`: neither is fixed by `run.sh`. When a report's character changes, the first question is what produced it, and the answer has to survive in the artifact rather than in a log nobody reads. `default` is the honest value when no model was named (the engine picks and this script is not told what it picked). The keys are absent on a zero-session night, which is correct: that path returns before L2 runs.
- `l1_warmup`, `l1_model_<adapter>`, `l1_breaker_fired`, `l1_sessions_already_done_at_start`, `l1_cache_dropped`: each exists so one reading cannot be confused with another. A failed warmup before a night of empty stubs is the diagnosis and an `ok` one rules it out; the per-adapter model lets a report that reads differently be traced to the engine that produced it (one key per source that had sessions); `l1_breaker_fired: yes` keeps a short `l1_rounds_used` from reading as a run that finished early and cleanly; the cached-versus-fresh count lets the aggregator tell a sub-second `elapsed` caused by everything already being done from a broken timer; `l1_cache_dropped` counts cached results this run would not reuse (`drop_unacceptable_l1_cache`) and triaged again.
- `citations_*`: the checker (`CITECHECK`) can fail to run (missing jq, unreadable inputs). Record `unmeasured` for all three keys rather than leaving them absent, which reads as "this runner predates the stat".

### Decision
These keys are written on every path that reaches them, with an explicit `unmeasured`, `none`, `no`, `0` or empty value as appropriate. Two exceptions are by design: `l2_engine` and `l2_model` are absent on a zero-session night (that path returns before L2 runs), and `legacy_marker_reports` is written only by the full-run block, not by the zero-session stub. The `x_queryid_source` and `x_fetch_path` keys exist only on nights that reach the collectors (a zero-session night, or one an L1 network deferral ends, returns first), and `citations_*` only when `CITECHECK` is executable and a report exists. For the other keys, absence means an old runner, not a stat that did not apply. See docs/adr/0010-rollup-and-run-stats.md#background-degraded-measurements-must-say-so-not-read-as-zero, "Degraded measurements must say so, not read as zero" and "Which code actually ran (`runner_commit`)".

### Consequences
Do not turn an always-emitted key into a conditional one, and do not replace `unmeasured` with `0`. A new stat should follow the same rule. PROMPT.md's self-audit names `adapters_rejected`, `overlap_measured`, `unassembled_dates` and `l2_model` (checked by grep), so renaming one of those breaks the report. `legacy_marker_reports`, `l2_engine` and `citations_*` are not named there: grep `bin/` and `tests/` for consumers before renaming them.

## run-stats records what L1 workers actually did (rounds, confinement, chunk cost)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`: `l1_rounds_used`, `l1_confine_stat_lines`, the `l1_chunk*` keys)

### Context
- `l1_rounds_used` is read from `LAST_ROUND_RUN`, not `$round`: the loop variable is assigned before a round dispatches, so a loop that stopped before dispatching would still read as having used that round. (The round-budget and circuit-breaker behavior is in docs/adr/0005-l1-workers.md#background-a-hung-worker-a-cold-token-and-a-deterministic-failure-omp-autodream-2026-08-to-2026-09, "A hung worker, a cold token and a deterministic failure".)
- Confinement (#169): whether workers could write only to their staging directory, and with what. A `no` is a degraded night, not a failed one; the reason says why. `l1_confine_stat_lines` writes the keys.
- `l1_warmup` says how the auth warmup went (`ok`, `failed`, `skipped`, or `skipped_no_timeout`; `not_reached` if the run never got there): a failed warmup ahead of a night of empty stubs is the diagnosis, an ok one rules it out. `l1_breaker_fired` is `yes` when the circuit breaker cut the retry budget, so a short `l1_rounds_used` is not mistaken for a run that finished early and cleanly.
- Chunked triage cost: `l1_chunk_bytes` is the setting in force (0 = off, including when the helpers were not found); the counters (`l1_chunked_sessions`, `l1_chunks`, `l1_chunk_calls`, `l1_chunks_elided`) are 0 on a night nothing was over the limit, and `l1_max_chunks` is the cap in force. `l1_chunks` is the chunk workers the oversized sessions needed, `l1_chunk_calls` the engine calls actually made (retries add, a reused answer makes none), and `l1_chunks_elided` how many chunks the cap dropped from the middle of a session. A nonzero `l1_chunks_elided` is a degraded read, named here so it cannot pass as a complete one.

### Decision
`l1_rounds_used` uses `LAST_ROUND_RUN`; `l1_chunk_bytes` prints `0` unless `L1_CHUNKING = 1`, and the four counters default to 0 when unset. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Reading a long session: chunked triage" ("What it costs") and "A worker writes only its staging directory (#169)".

### Consequences
Do not swap `LAST_ROUND_RUN` for `$round`. Do not fold `l1_chunks_elided` into a quieter place: it is the only signal that a session was read with its middle cut.

## run-stats counts sessions and L1 failures so each denominator is honest

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`; the oversized-gate computation just above it)

### Context
Counts that look similar measure different things, and the self-audit divides one by another. Facts the retired comments record:

- `gated`: sessions skipped before any model call (noise gate). They are within `sessions_triaged` but structurally cannot appear in `l1_findings_with_error` (they never reached a model), so the extraction-failure rate's denominator must subtract this out.
- `sessions_dropped_after_failures` is the vs.-raw figure: `RAW - COLLIDED_DROPPED - L1_OK - EXCLUDED - SKIPPED_EMPTY`, clamped at 0, so a session lost to ANY path (prune misclassification, silent worker death, slim leftovers) shows up here. If nonzero the aggregator should investigate even when `l1_missing` is 0. The retired comment sat above `sessions_dropped_to_collision` (which is just the collision-handling count, `COLLIDED_DROPPED`), followed by `sidecar_stale_rows` and `sessions_dropped_after_failures`; its text describes the last of these, so the comment was misplaced.
- `l1_sessions_already_done_at_start` (cached) versus `l1_sessions_freshly_processed` lets the aggregator tell a sub-second `l1_elapsed_seconds` caused by everything already being done from a broken timer; `l1_cache_dropped` counts cached results this run would not reuse (`drop_unacceptable_l1_cache`) and triaged again.
- `l1_errored_silent`, `l1_errored_provider`, `l1_errored_unclassified`: a silent worker death (exit 0, empty stdout), a provider refusal and an unclassifiable failure are not evidence that a transcript was too large. The size-attributable extraction-failure rate is `(errors - silent - provider - unclassified) / (triaged - gated)` (PROMPT.md's self-audit computes it).
- Oversized-transcript measurement gate (#12): the comment says "see the computation above `L1_ERRORED`", but the computation actually sits below it (the `OVERSIZED_*` block). Gate: if `oversized_errored / oversized_total` sustains >= 5% over a trailing week, the signal for issue #12 has opened. The runner only records counters; the L2 self-audit and the human do the trailing-week judgment.
- Sidecar health (#27): `stats_sidecars_unparseable` counts sessions of `sessions_triaged` whose stats sidecar was missing, empty, or without numeric `transcript_bytes`. Every sidecar consumer degrades when it is non-zero (`gated` under-counts, because an unreadable sidecar never gates by design, and oversized sizes came from a live read), so it caveats those two keys instead of duplicating a flag onto each.
- `l1_err_files_orphaned`: `.err` files with no findings JSON and no session in tonight's worklist, i.e. failed triage nothing will retry. Nonzero is a stale failure, not tonight's.
- `l1_findings_outside_worklist`: findings JSONs no session in tonight's worklist owns. L2 reads them all, so a nonzero value means the report includes sessions this run did not place in the day.
- `sessions_top_level` / `sessions_nested` (#79): the Activity snapshot's total split into top-level sessions and nested workers. Both count ungated sessions, the same set as the report's N; `fanouts.tsv` names each worker and its parent.

### Decision
The keys are emitted as listed, with the class counts beside both `l1_findings_with_error` and `oversized_errored`, so the audit can take the three classes out (of the extraction-failure numerator, and of the #12 share's numerator and denominator per docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26). See docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "A failed worker leaves its evidence, and the failure is classified", "Degraded measurements must say so", and "Which day a session belongs to".

### Consequences
Changing which sessions each counter includes silently changes the #12 rate and the report's N. If a key is renamed, PROMPT.md's self-audit must move with it. The pointer "see the computation above `L1_ERRORED`" is inexact (the block is below it); the ADR is the record.

## Session stats are computed once from the final enumeration, and overlap runs after every sidecar and before the noise gate

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `compute_session_stats`, `compute_overlap_stats`)

### Context
Overlap is a cross-session computation, not a per-session one. Gated sessions' sidecars still exist and still participate in overlap (see `docs/adr/0010-rollup-and-run-stats.md#overlap-counts-distinct-parent-session-pairs-from-sidecars-and-drops-advisor-and-nested-worker-sidecars`: the script cannot see the gate decision, and the stat deliberately includes every gated top-level session).

### Decision
- `compute_session_stats` runs once from the final enumeration. Retry rounds reuse those sidecars and intentionally do not regenerate them during dispatch retries.
- `compute_overlap_stats` runs after every session's sidecar exists and before the noise gate that runs inside `dispatch_l1`.
- `FANOUT_ROWS` is taken from the findings dir after that.

### Consequences
- Overlap must run after `compute_session_stats` has written every sidecar; run before it, it measures over missing sidecars.
- Placement before the noise gate is deliberate, so a later move must keep gated sessions in the measurement.
- Retry rounds reuse the sidecars; they are not regenerated during dispatch retries.

## stale-row and per-source counts are measured from the final sidecar, and an error reads as unknown

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`build_source_sidecar`: `SIDECAR_STALE_ROWS`, `SESSIONS_BY_SOURCE`)

### Context

Collision resolution removes provenance rows after the fact, so a count taken during the walk reported sessions that no longer exist in the worklist. The first stale-row count was wrong in both directions: it added one when a rewrite ATTEMPT failed and then iterated dropped PATHS. A two-path collision with one persistent stale row reported 3 (one attempt plus the same hash found twice), and a transient failure that a later rewrite had repaired reported 1 when the honest answer was 0.

Staging matters: `producer || exit 1 | sort -u` is masked, because without `pipefail` `sort` exits 0 on empty input, so a failing producer produced an empty successful assignment and the metric read 0, the false zero this branch exists to avoid.

### Decision

`SIDECAR_STALE_ROWS` is computed once, after all rewrites: the dropped hashes are staged in `$FINDINGS_DIR/.stale-hashes.$$`, then `sort -u`'d, then each unique hash is looked up in the final sidecar (`grep -q`, 0 stale, 1 absent). A `grep` status above 1 sets `SIDECAR_STALE_ROWS=unknown` (an error is not "absent", the same refusal of a false-clean reading as `overlap_measured`); a staging or sort failure sets it to `unknown` too, with a WARNING ("reporting it as unknown rather than zero"). `SESSIONS_BY_SOURCE` is likewise counted from the final sidecar with `awk | sort | uniq -c`, not during the walk, and is `none` when empty. The metric is reported in run-stats as `sidecar_stale_rows` and `sessions_by_source`.

### Consequences

A measured count that cannot be measured must say `unknown`; this is the repo's rule for degraded measurements (see docs/adr/0010-rollup-and-run-stats.md#background-degraded-measurements-must-say-so-not-read-as-zero, "Degraded measurements must say so, not read as zero"). Do not move either count back into the loop.

## The mechanical skill fields are enforced from the sidecars with jq, outside the optional-python3 block

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `SKILLS_ENFORCED` loop)

### Context
The prompt asks the worker to copy `skills_invoked`, `skills_invoked_count`, `skills_invoked_counts` and `skills_authored` from the precomputed stats, but asking is not enforcing. Gating enforcement on an optional interpreter meant that on a host without `python3` the pipeline quietly returned to believing whatever the model wrote, the exact failure this replaced. `jq` is already a hard dependency of the script, so this cannot silently degrade. See docs/adr/0010-rollup-and-run-stats.md#background-skill-fields-are-measured-not-guessed-omp-autodream-2026-09-04, 'Skill fields are measured, not guessed'.

`compute_session_stats` regenerates every sidecar each run, so a sidecar that is missing, unreadable, or lacks any of the four skill keys means `session-stats.sh` did not measure this session's skills, and whatever skill fields the findings JSON carries are the worker's own guess. Checking one key was not enough: copying the keys that exist would leave the worker's guesses for the rest. A sidecar with missing keys passes generation's type check and only breaks here. Codex reviews of 0129fc0, cd309b6 and 33bf9b1.

### Decision
- The loop runs on every valid findings JSON (`L1_FINDINGS_OK` under `jq -s`). If the sidecar lacks any of the four keys, all four are deleted from the findings JSON and counted in `SKILLS_DROPPED`; otherwise the four are overwritten from the sidecar (`SKILLS_ENFORCED`).
- Rewrites that fail (full disk, unwritable dir), whether the delete or the overwrite, are counted in `SKILLS_FAILED`: the worker's own skill fields survive in those files, so the count has to be visible or L2 ranks guesses as measurements. `SKILLS_DROPPED` and `SKILLS_FAILED` reach run-stats as `skills_unmeasured` and `skills_enforcement_failed`.

### Consequences
- Keep this step independent of python3.
- Never keep a subset of the worker's fields when the sidecar is incomplete.

## source provenance lives in a sidecar keyed by artifact hash, and sessions.txt stays one bare path per line

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`build_source_sidecar`; `session_hash` is in `bin/lib-project.sh`)

### Context

The hash assignments in `l1_missing_count()` and `dispatch_l1()` key each artifact by the sha1 of the WHOLE `sessions.txt` line, `oversized-gate.sh` recomputes the same hash from it, and every archived findings dir depends on that shape. Adding a source field to `sessions.txt`, or including the source in the hash formula, would silently invalidate all of them. See docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (`sessions.txt`, `<hash>.json`).

Two sources can still land on one artifact in two ways: the same path claimed twice, and two different paths truncating to one 12-character hash. The original header comment called the first a misconfiguration of two adapters; a later comment in the same function corrected that. `sessions.txt.src` is not deduplicated while `.raw` is `sort -u`'d, so every duplicate seen is one transcript reached through two entries of `SESSION_ROOTS`, which is ordinary on a host where `root-probe` autodetects each `$HOME/.claude*/projects` and one is a symlink of another.

### Decision

`sessions-source.txt` maps `<12-char hash><TAB><source>`; the hash formula is unchanged. `build_source_sidecar` detects the two cases: the same path claimed twice (`DUPLICATE_PATHS`, keep the first, log "duplicate: ... was reached more than once") and two DIFFERENT paths truncating to one hash (`HASH_COLLISIONS`, no sensible winner, drop both, see `collided-sessions-dropped-both-and-verified`). The duplicate message deliberately does not say "claimed by more than one adapter": naming adapters sends the reader after a misconfiguration that does not exist.

### Consequences

The comment's claim that "only `claude` is ever enabled" is stale (the log line now says "two session roots, or two adapters"), but the symlinked-roots explanation is still the common cause. Do not change the hash formula or the `sessions.txt` shape without migrating every archived findings dir.

## A session's stats are computed by its own adapter, over the live linearized conversation

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_session_stats`)

### Context
omp records are not claude records. Stats describe the live conversation the worker will read, not the append-only tree it came from: abandoned branches would otherwise add user turns and stretch the duration, and the noise gate reads these numbers.

### Decision
For a source other than claude whose adapter script exists, the session's own adapter computes the stats (`adapter_run "$src" stats`). `AUTODREAM_STATS_BIN` still wins, and a session with no recorded source keeps the claude script (`$STATS`), so an install that predates the source sidecar degrades instead of failing. An adapter whose manifest has `normalize: true` is linearized first, into `<hash>.statsin.jsonl`, and the stats read that copy (falling back to the raw file if normalize fails). The result is then cut to the report day before the stats run, and a cut that errors logs a WARNING that the stats cover the whole transcript. A stats run that fails or writes a non-object removes the sidecar and logs `stats failed ... continuing without precomputed stats`.

See docs/adr/0003-adapters-and-engines.md#background-several-harnesses-in-one-run-enabled-is-a-host-decision-and-every-session-goes-through-its-own-adapter, "Several harnesses in one run".

### Consequences
The order with the day cut is in `day-slice-normalize-before-cut`. The temp copies (`.statsin.jsonl`, `.statsday.jsonl`) are removed after each session.

## `compute_session_stats` does not count sidecar failures: `STATS_SIDECARS_UNPARSEABLE` is initialised later, in the oversized-gate loop

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_session_stats`, the oversized-gate loop that initialises `STATS_SIDECARS_UNPARSEABLE`)

### Context
`compute_session_stats` runs before the oversized-gate loop. `STATS_SIDECARS_UNPARSEABLE` is initialised to 0 in that loop, so an increment inside `compute_session_stats` would be wiped, and referencing the variable before that assignment trips `set -u` outright.

### Decision
When `session_hash` fails, `compute_session_stats` only logs a WARNING naming the session and writes no sidecar. The oversized-gate loop walks the same `sessions.txt`, which is why the #27 fix reads the session list rather than the sidecar glob. That loop's own `session_hash` failure branch counts the session in `OVERSIZED_UNMEASURABLE` (run-stats `oversized_unmeasurable`) and skips it. `STATS_SIDECARS_UNPARSEABLE` is incremented only for a session that has a hash and whose sidecar is missing or has no numeric `transcript_bytes`. The original comment said the loop counts a hashless session as an unparseable sidecar, which the code does not do.

See docs/adr/0010-rollup-and-run-stats.md#background-self-audit, "Self-audit" (Degraded measurements must say so, not read as zero).

### Consequences
Do not add the counter to `compute_session_stats`.
