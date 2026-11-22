# 0009: L2: the aggregator, the report and its delivery

Status: accepted · Governs: `bin/citation-check.sh`, `bin/dream-grounding.sh`, `bin/report-format.sh`, `bin/run.sh`

This record holds 20 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: L2 is read-only: the report and the pins arrive on stdout (omp-autodream 2026-09-13, plan 2026-09-15)](#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15)
- [a citation is any standalone 12-hex token, so a stray token is a false alarm and never a false all-clear](#a-citation-is-any-standalone-12-hex-token-so-a-stray-token-is-a-false-alarm-and-never-a-false-all-clear)
- [citation-check reports counts, never a verdict, and treats anything it cannot confirm as a defect](#citation-check-reports-counts-never-a-verdict-and-treats-anything-it-cannot-confirm-as-a-defect)
- [a cited 12-hex token with no findings file still resolves when it matches a triaged session path](#a-cited-12-hex-token-with-no-findings-file-still-resolves-when-it-matches-a-triaged-session-path)
- [report claims are grounded by fixed, read-only checks in code, and a check that cannot run says unknown](#report-claims-are-grounded-by-fixed-read-only-checks-in-code-and-a-check-that-cannot-run-says-unknown)
- [the installed-skill search follows symlinks and stops at depth 7](#the-installed-skill-search-follows-symlinks-and-stops-at-depth-7)
- [L2's report is everything before the LAST `AUTODREAM_REPORT_END`, and pins come only from a closed block after it](#l2s-report-is-everything-before-the-last-autodream_report_end-and-pins-come-only-from-a-closed-block-after-it)
- [the open-questions count is read strictly, completeness loosely, and anything unrecognised is "unknown"](#the-open-questions-count-is-read-strictly-completeness-loosely-and-anything-unrecognised-is-unknown)
- [the open-questions section is found by sentinel lines, with a fenced-heading fallback only for legacy dates](#the-open-questions-section-is-found-by-sentinel-lines-with-a-fenced-heading-fallback-only-for-legacy-dates)
- [citation integrity is appended to run-stats after L2, and is never fatal](#citation-integrity-is-appended-to-run-stats-after-l2-and-is-never-fatal)
- [Superseded report copies are deleted, except ones holding the user's triage decisions](#superseded-report-copies-are-deleted-except-ones-holding-the-users-triage-decisions)
- [L2 attempt diagnostics are bounded evidence gathered off the critical path, and nothing depends on them](#l2-attempt-diagnostics-are-bounded-evidence-gathered-off-the-critical-path-and-nothing-depends-on-them)
- [only a sentinel-validated, marker-bearing L2 capture counts as a delivered report](#only-a-sentinel-validated-marker-bearing-l2-capture-counts-as-a-delivered-report)
- [the L2 prompt is a brace group with literal paths, run in a subshell](#the-l2-prompt-is-a-brace-group-with-literal-paths-run-in-a-subshell)
- [the L2 aggregator is retried until a validated delivery lands](#the-l2-aggregator-is-retried-until-a-validated-delivery-lands)
- [pins are taken only from a closed block after the last sentinel](#pins-are-taken-only-from-a-closed-block-after-the-last-sentinel)
- [The no-sessions stub is staged, status-checked and published in one rename; a failed publish fails the run](#the-no-sessions-stub-is-staged-status-checked-and-published-in-one-rename-a-failed-publish-fails-the-run)
- [superseded stale and partial copies are retired outside the `-f "$REPORT_PATH"` test](#superseded-stale-and-partial-copies-are-retired-outside-the--f-report_path-test)
- [repos worth triaging are counted by the runner from its own session rows](#repos-worth-triaging-are-counted-by-the-runner-from-its-own-session-rows)
- [a truncated report is moved aside as `.partial-<epoch>` so it cannot become the permanent one](#a-truncated-report-is-moved-aside-as-partial-epoch-so-it-cannot-become-the-permanent-one)

## Background: L2 is read-only: the report and the pins arrive on stdout (omp-autodream 2026-09-13, plan 2026-09-15)

This section was moved here from the former CLAUDE.md. Its original title: "L2 is read-only: the report and the pins arrive on stdout (omp-autodream 2026-09-13, plan 2026-09-15)".

L2 holds Glob and Read. It cannot write the report, `pins.jsonl`, or anything under the findings directory, so the runner is the only writer and an injected L2 cannot rewrite `sessions-source.txt` or forge a pin. The grammar of its stdout:

```
<report body>
AUTODREAM_REPORT_END
AUTODREAM_PINS_BEGIN        (optional)
{"project":...,"title":...,"body":...,"kind":...}     one JSON object per line
AUTODREAM_PINS_END
report: <path>
<3-line summary>
```

- Delivery means a capture with the sentinel. The report is everything before the LAST sentinel; a capture without one is kept as a degraded report, moved aside as `.partial-<epoch>`, and retried. The open-questions marker alone is not proof of completion.
- Pins come only from a closed block after the last sentinel, so a report that quotes the markers cannot inject one, and a block cut off before its END line proposes nothing. `apply-pins.sh` still validates every line against the authorization list fixed before any model ran.
- The run exits 0 only for a validated delivery (sentinel plus marker); otherwise the aggregator's own non-zero status, else 1, so the launchd job sees a night that produced nothing.

## a citation is any standalone 12-hex token, so a stray token is a false alarm and never a false all-clear

Status: accepted · Date: 2026-11-21 · Code: `bin/citation-check.sh` (`hashes` pipeline)

### Context

L2 formats citations in two shapes that vary run to run: backticked (`` `47eba605cf1e` ``) and bare in a comma list (`(c7b79782412d, 98e07eeaad42, ...)`). Matching only the backticked form scored the 2026-08-18 pre-fix report at `citations_total: 0`, a false all-clear, which is the one output this check exists to prevent.

### Decision

A citation is any 12-hex run whose neighbours are not hex. A 40-character commit SHA is not split into citations, and a 7-character short SHA is too short to match.

The bias is deliberate and one-directional: a stray hex token surfaces as unresolved, a false alarm a human dismisses in seconds, and never as a clean report. The substantive-session filter makes the same judgement when it keeps an unparseable session rather than dropping it.

The pipeline replaces every non-hex character with a space, splits to one token per line, and keeps tokens that are exactly 12 hex characters. That gives the boundary rule without `\K`, which BSD `grep` lacks.

### Consequences

Tightening the pattern to the backticked form brings back the false all-clear. `dream-grounding.sh` excludes the same 12-hex spans from its sha claims so the two checks do not overlap (see `bin-a-dream-grounding-fixed-checks-in-code`).

## citation-check reports counts, never a verdict, and treats anything it cannot confirm as a defect

Status: accepted · Date: 2026-11-21 · Code: `bin/citation-check.sh` (verdict loop, exit codes)

### Context

L2 cites sessions by their 12-hex findings hash. On 2026-08-18 the top-ranked pattern quoted `47eba605cf1e` at "line 439/456/471" with a detailed `kSecUseAuthenticationUISkip` diagnosis. That session was noise-gated, so its findings record was a bare stub (`{"session_path":"...","skipped":"below_noise_gate","findings":[],"project":"-p"}`). The quote lived in `6f38f3cbed43`, a different session in the same project. The analysis was sound and the content real; only the ID was wrong, and an open question inherited it. A gated stub still carries `project`, which is what makes the wrong hash look plausible to the aggregator.

10 of 11 citations that night resolved correctly. That makes it a per-citation defect, the kind that survives review because spot-checking one or two citations passes.

### Decision

- The script counts and prints `KEY: VALUE` lines on stdout (`run.sh` appends them to `run-stats.txt`). It does no gating: the report still ships, and the morning review learns which citations not to trust.
- A cited hash whose findings record is a `below_noise_gate` stub is counted as `citations_to_gated`, the specific failure worth naming: the aggregator cited a session whose content it never received.
- Malformed JSON counts as unresolved, never clean. The point is to avoid a false all-clear.
- Exit 0 whenever the check ran, whatever it found. Exit 2 only when it could not run at all (missing report, missing findings dir, no `jq`), so a silent 0/0/0 cannot be mistaken for a clean report.

### Consequences

Making this check fail the run, or reading a missing `jq` as zero citations, turns a measurement into either a blocker or a false all-clear. `run.sh` records `unmeasured` for the three counters when the script exits non-zero.

## a cited 12-hex token with no findings file still resolves when it matches a triaged session path

Status: accepted · Date: 2026-11-21 · Code: `bin/citation-check.sh` (`session_paths`, `by_path`)

### Context

A cited 12-hex token is not always a findings hash. Session filenames are UUIDs and their last group is 12 hex characters, so an aggregator that cites a session by filename tail produces a token that resolves to nothing under the hash rule. Observed on 2026-08-18 with `87b5b1392572`, the tail of a real, triaged session.

Those are genuine citations to genuine sessions. Counting them as unresolved would train the reader to ignore the counter, the failure the check exists to avoid.

### Decision

The script builds one index per run: every `session_path` any findings record claims. A token with no `<hash>.json` is checked by substring against that index. A match counts as `citations_resolved_by_path`; no match counts as unresolved.

### Consequences

The index is built once, before the loop, so cost does not grow with the number of citations. The substring match is permissive on purpose, in line with `bin-a-citation-check-any-12-hex-token`: a path match can only turn an alarm into a resolution when a triaged session really holds that token.

## report claims are grounded by fixed, read-only checks in code, and a check that cannot run says unknown

Status: accepted · Date: 2026-11-21 · Code: `bin/dream-grounding.sh` (`classify`, `check_skill`, `check_allow`, `check_sha`)

### Context

The report is written by a model reading findings, and its claims about the filesystem go stale or wrong. Examples: "skill X does not exist" when it lives under `~/.claude/skills` and the report only looked in the plugins dir; an allowlist key whose exact text was never compared with `settings.json`; a commit SHA that was never resolved.

The triage pass (`triage-dream.sh`) hands the model this script's JSON as data, so the model never needs a shell. A prompt that says "do not run anything that writes" is weaker than checks fixed in code.

### Decision

- The runner runs a fixed set of read-only, model-free checks and writes one JSON file. Claims come from backticked spans in the report: `skill` (a span on a line mentioning "skill", matched by installed name with any `plugin:` prefix dropped), `allowlist` (a `Tool(...)` rule or an `mcp__` name, matched against the exact string in `permissions.allow`), and `sha` (a 7 to 40 hex span with a digit and a letter, resolved with `git cat-file` as a commit in a known repo).
- A 12-hex span is a findings hash, which `citation-check.sh` owns, so it is never a sha claim.
- Status is `present`, `absent` or `unknown`. `unknown` means the check could not run (no settings file, no repo, no skill listed), never `absent`. The output records `truncated: true` when there were more claims than `AUTODREAM_GROUNDING_MAX` (default 100); the rest were not checked.
- Exit 0 whenever the check ran. Exit 2 when it could not (usage, unreadable report, no `jq`).

### Consequences

An `absent` result is evidence only inside what was searched, and its `evidence` text says so (built-in and project-local skills are not searched; a broader rule or project setting may still allow an allowlist key). Collapsing `unknown` into `absent` would reproduce the wrong "does not exist" claims this exists to catch.

## the installed-skill search follows symlinks and stops at depth 7

Status: accepted · Date: 2026-11-21 · Code: `bin/dream-grounding.sh` (skill listing `find -L ... -maxdepth 7`)

### Context

A skill linked in from elsewhere is still installed, so a search that does not follow links reports it as absent. A plugin cache holding many versions can make an unbounded walk a crawl.

### Decision

The skill listing uses `find -L` over each directory in `AUTODREAM_SKILL_DIRS`, with `-maxdepth 7`, matching `SKILL.md` files under a `skills/` path.

### Consequences

A skill nested deeper than seven levels is not listed and would be reported as `absent`. Raise the bound only with a measurement of the cost on a real plugin cache.

## L2's report is everything before the LAST `AUTODREAM_REPORT_END`, and pins come only from a closed block after it

Status: accepted · Date: 2026-11-21 · Code: `bin/report-format.sh` (`report_body`, `report_after_sentinel`, `report_pin_lines`, `report_has_sentinel`)

### Context

L2 holds no Write tool, so the runner is the only writer and reads the report and the pin block off L2's stdout (docs/adr/0009-l2-aggregation.md#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15, "L2 is read-only: the report and the pins arrive on stdout"). A report can quote the sentinel or the pin markers in prose.

### Decision

- The sentinel is exactly `AUTODREAM_REPORT_END` on a line of its own. Indented, CRLF or quoted text is not one.
- The report is what precedes the LAST sentinel, so a quoted sentinel inside the report does not truncate it.
- Pins are the JSON-object lines of a CLOSED `AUTODREAM_PINS_BEGIN`/`AUTODREAM_PINS_END` block that follows the last sentinel. A block quoted in the body cannot inject a pin, and a capture cut off before `PINS_END` proposes nothing rather than half a pin.
- Every function takes the report or capture as `$1` and returns the status of its last command, so `report_body f > f.tmp && mv f.tmp f` stops when the read fails.

### Consequences

`apply-pins.sh` still validates every pin against the authorization list fixed before any model ran. This parser only narrows what reaches it. Changing the grammar means changing `prompts/L2_SYSTEM.txt` with it.

## the open-questions count is read strictly, completeness loosely, and anything unrecognised is "unknown"

Status: accepted · Date: 2026-11-21 · Code: `bin/report-format.sh` (`report_marker_count`, `report_has_marker`, `report_open_questions`)

### Context

`<!-- autodream:open-questions=N -->` is the last thing `prompts/PROMPT.md` emits. It says how many questions need a human call and that the write reached its end. Callers need different guarantees from it, and reports from before the marker have only prose.

### Decision

- `report_marker_count` is strict: the comment must be well formed and the first one wins. `question-streaks.sh` and `notify.sh` trust nothing looser.
- `report_has_marker` is loose on purpose. `run.sh` asks only whether the write reached its end, so a truncated report that still carries the key counts. A malformed marker passes it and fails the count, which is how `question-streaks.sh` refuses to clear a streak on it.
- `report_open_questions` falls back, for marker-less reports, to the empty-day stub text and to a `## Open questions` section whose first non-blank line starts with "none". Every other shape is `unknown`, and the caller launches the session. A false "nothing to do" swallows real questions, while a false launch only costs tokens.

### Consequences

Do not merge the strict and loose readers. Add a recognised prose shape only when a real legacy report shows one.

## the open-questions section is found by sentinel lines, with a fenced-heading fallback only for legacy dates

Status: accepted · Date: 2026-11-21 · Code: `bin/report-format.sh` (`report_questions`, `report_has_questions_block`, `report_finishes`)

### Context

The section was found by matching a markdown heading, and four consumers (`notify.sh`, `review.sh`, `question-streaks.sh`, `triage-dream.sh`) each approximated that differently. A heading can sit in a code fence, in prose or inside another heading, so the consumers disagreed about where the section ended. See docs/adr/0022-review-and-triage.md#background-the-triage-prompt-is-questions-only-and-that-is-load-bearing, "The triage prompt is questions-only, and that is load-bearing".

### Decision

- `AUTODREAM_QUESTIONS_BEGIN` and `AUTODREAM_QUESTIONS_END` bracket the section, each on a line of its own. The reader takes the text after the FIRST begin up to the LAST end, so a question that quotes the sentinel in a code example does not end the block early. A block counts as closed only when an END follows a BEGIN.
- Reports dated before `AUTODREAM_QUESTIONS_EPOCH` (default `2026-10-27`) predate the block and are read the old way: from `## Open questions` to the next `## ` or horizontal rule. That path keeps fence tracking, because a heading quoted inside a code example is not the end of the section (a review finding when the fallback was written).
- `report_finishes` requires the closed block only for dates on or after the epoch. Dates are compared as strings, which is chronological for ISO dates.

### Consequences

The fallback serves history only. A new report without the block is not finished, so a bad block costs one rebuild instead of a silent wrong read. A consumer must call `report_questions` and never parse markdown itself. Changing a sentinel string means changing `prompts/PROMPT.md` and `bin/report-format.sh` together.

## citation integrity is appended to run-stats after L2, and is never fatal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `CITECHECK`, `citations_*`)

### Context
The run-stats keys are written BEFORE L2 runs, and this check needs the finished report. Appending keeps one self-audit artifact to read in the morning instead of a second sidecar. A citation defect is a measurement, and the report still ships.

### Decision
When `citation-check.sh` is executable, its output is appended to `run-stats.txt` after the pins step and before `notify.sh`; unresolved or to-gated citations log a WARNING (all resolved logs a plain line); a checker that could not run (missing jq, unreadable inputs) records `citations_total`, `citations_unresolved` and `citations_to_gated` as `unmeasured`, because absent keys would read as an older runner that predates the stat (see `runstats-keys-never-read-as-clean-zero`).

### Consequences
Do not move the check into the pre-L2 stats block, and do not make a citation defect fail the run.

## Superseded report copies are deleted, except ones holding the user's triage decisions

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`drop_stale_report_copies`)

### Context
A forced rebuild moves the old report aside as `<report>.stale-<epoch>`. Once a report is delivered in its place, those copies must leave the `.stale-*` glob so the record lookup (`remote-short-dates-record-in-report`) cannot resurface an old label. A copy with a `## Triage decisions` heading holds the user's own writing.

### Decision
After delivery, every `.stale-*` copy still in the glob is deleted. The report this run moved aside itself (`STALE_REPORT`) is deleted when the rebuild succeeds, before this helper runs, so a `## Triage decisions` section in the report a successful forced rebuild replaces is not preserved (docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts": a rebuild replaces the report, including any `## Triage decisions` the user wrote). A copy with a `## Triage decisions` heading is instead renamed to `<report>.triaged-<epoch>` (with a `.$$` suffix if that name exists), which the record lookup never reads. A copy that cannot be read is kept, not deleted: `grep -q` exit status other than 1 means "found or unreadable", and only status 1 (no match) permits deletion, so an unreadable copy takes the same rename to `.triaged-<epoch>` and leaves the glob. It runs after a stub report is published (`mv` of the `.tmp`) and after an L2 delivery that passes `report_complete`.

### Consequences
Never widen the delete path to copies the grep could not read. A failed `rm` or `mv` logs a WARNING and leaves the copy in place.

## L2 attempt diagnostics are bounded evidence gathered off the critical path, and nothing depends on them

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l2_diag_probe`, `l2_diag_start`, `l2_diag_start_body`, `l2_diag_collect`, `l2_diag_end`)

### Context

Issue 42. L2 attempt 1 has died with exit 143 (SIGTERM) and a bare "Execution error" on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02, and nothing in the log says who sent the signal. `run.sh` applies no timeout of its own to L2, so the TERM comes from outside.

### Decision

When an attempt exits 143, 137 or 124, `l2_diag_end` writes `findings/<date>/l2-attempt-N.diag`: timestamps, the exit code, the worker's pid and parent chain, the launchd job's state, load, memory pressure, the kernel's last sleep and wake times, and the other autodream or claude processes. Every probe runs bounded (3 s) in its own background job and cannot fail the run: a hung `launchctl` costs three seconds, a missing tool costs one line. `l2_diag_probe` output is cut by line (`cut -c1-600 | head -n 80`), so a huge command line cannot cut the output mid-line and glue the next heading to it. The start half is gathered by a background job (`l2_diag_start`, `l2_diag_start_body`), so an attempt that goes on to succeed, nearly all of them and every one in the test suite, pays nothing for it; `l2_diag_end` collects it through `l2_diag_collect` (waiting up to 3 s for the job), and on any other exit code discards it. Both calls in the L2 loop are `|| true`.

### Consequences

No behaviour may depend on any of it. Do not make a probe unbounded, and do not run the start half in the foreground. The source of the SIGTERM is still unnamed.

## only a sentinel-validated, marker-bearing L2 capture counts as a delivered report

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_ATTEMPTED`, `L2_DELIVERED`, `L2_SENTINEL`, `report_has_sentinel`, `report_body`, `report_complete`, the final `return`)

### Context
- `L2_ATTEMPTED` separates a fresh run that actually spawned the aggregator from the legacy short-circuits (the idempotency guard and the COUNT=0 stub both return before L2). `L2_DELIVERED` flips to 1 only when an attempt's capture carried the `AUTODREAM_REPORT_END` sentinel. Both default to 0 so the move-aside can tell "this run confirmed delivery" from "this run never reached L2": a marker-bearing report left by an earlier night must not be read as this run's output.
- The sentinel is the completion gate: everything before the LAST occurrence is the report body, and a capture without one is a degraded report whether or not it has the open-questions marker, because the marker alone cannot prove the output reached the end. Both writes are staged to a `.tmp` and renamed so a half-staged file never lands at `$REPORT_PATH`. Lines after the sentinel (pin block, report path, summary) are appended to the run log so a stripped capture never loses them.
- The loop breaks only on a sentinel-validated capture that also carries the marker; a degraded capture never satisfies it.
- Only a sentinel-validated report counts as delivered; a degraded capture that could not be moved aside also leaves a file at the path and must not be reported as ready.
- The exit status uses the same pair as the partial move-aside, the run-outcome write, the stale-copy drop and dream triage (`L2_DELIVERED` and `report_complete`). The pins and consume gates test `report_complete` plus `CONSUME_SAFE` / `PINS_SAFE` and not `L2_DELIVERED`: they depend on the move-aside having removed a degraded capture. A degraded night can leave the aggregator's own exit code at 0, which would tell the launchd job (the only watcher an unattended run has) that the night produced a usable report when it produced none. Anything short of validated keeps the aggregator's non-zero status, else 1.

### Decision
Each L2 attempt captures stdout. The runner writes the report: everything before the LAST `AUTODREAM_REPORT_END` line (`report_body`), staged to `$REPORT_PATH.body` then `$REPORT_PATH.tmp` and renamed, with `L2_COMPLETE` set only when that succeeded; `L2_DELIVERED` takes that value. A capture with no sentinel is kept whole as a degraded report (written to `.tmp`, renamed), logged as incomplete, and the attempt retried. The attempt loop breaks only when `L2_DELIVERED = 1` and `report_complete`. After the loop a file at `$REPORT_PATH` is moved to `.partial-<epoch>` unless `L2_ATTEMPTED = 1`, `L2_DELIVERED = 1` and `report_complete`. That pair is also what `write_run_outcome delivered` (the signal `autodream-now.sh --watch` reads), `drop_stale_report_copies`, dream triage and the return of `run()` test; anything short of it returns the aggregator's non-zero status, else 1. See docs/adr/0009-l2-aggregation.md#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15, "L2 is read-only: the report and the pins arrive on stdout" (grammar, "Delivery means a capture with the sentinel").

### Consequences
Weakening any one of these to `-s "$REPORT_PATH"` or marker-only re-opens silent data loss. `AUTODREAM_REPORT_END` is part of `L2_SYSTEM.txt` and `bin/report-format.sh`; change them together. The consume and pins gates do not test `L2_DELIVERED`: if the partial move-aside's `mv` fails (the log says later triggers will treat the date as done), a marker-bearing degraded capture stays at `$REPORT_PATH` and `report_complete` is true. Adding `L2_DELIVERED` to those two gates would close it; not done today.

## the L2 prompt is a brace group with literal paths, run in a subshell

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the L2 call: the `{ printf ...; cat PROMPT.md; } | env ...` pipeline in a `( cd "$WORK_DIR" ... )` subshell)

### Context
Same literal-path framing and brace-group assembly as the L1 worker (the worker writes `Session transcript to analyze (literal absolute path)` and similar): the paths stay literal data the aggregator reads with Glob/Read, and the blank-line separator before PROMPT.md is preserved instead of letting a `prompt=$(...)` capture strip it and glue the doc onto the report-path line.

### Decision
A subshell scopes the cwd change (isolating the AI-title stub into `$WORK_BUCKET`, same as L1) to this call; `$?` after the subshell is the pipeline's exit, which is the engine's (the original comment said claude's; the engine is whichever adapter L2 runs on). The brace group writes three literal-path lines (findings directory, `dropped-threads.md`, report destination), a blank line, then `PROMPT.md`. See docs/adr/0011-self-pollution.md#background-the-ai-title-stub-vector-second-order-self-pollution, "The AI-title stub vector".

### Consequences
Do not capture the prompt with `$(...)`. The "Findings directory to aggregate (literal absolute path)" line is also one of `prune-self-sessions.sh`'s markers for recognizing autodream's own sessions.

## the L2 aggregator is retried until a validated delivery lands

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `for attempt in $(seq 1 "$L2_ATTEMPTS")` loop)

### Context
The aggregator call can die to a mid-run sleep; this is what left exit 1 and no report overnight. The retry is idempotent: a re-run overwrites the report harmlessly. The comment says to retry "until `$REPORT_PATH` is non-empty"; that is stale. Non-empty was proven insufficient (a truncated or degraded capture is non-empty), and the loop now breaks only on a sentinel-validated capture that also carries the open-questions marker (see `l2-delivery-requires-sentinel`). The heading above it also names "opus", but no model is pinned (see `l2-model-unpinned-by-default`).

### Decision
Up to `AUTODREAM_L2_ATTEMPTS` (default 3) attempts, waiting for the network and sleeping `AUTODREAM_RETRY_WAIT` (default 60s) between them. If the network does not come back within the wait, the loop stops, sets `NET_DEFERRED` and defers the date instead of burning the remaining attempts. See docs/adr/0001-runner-lifecycle.md#background-sleep-resilience, "Sleep resilience" (L2 retry loop).

### Consequences
Do not restore a bare `-s "$REPORT_PATH"` break condition: that is the failure mode the delivery gate was built to remove.

## pins are taken only from a closed block after the last sentinel

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `report_pin_lines`, `pins.jsonl.tmp`)

### Context
Only a delivered report carries pins, and only the block that follows the LAST sentinel counts, so a report that quotes the markers in its body cannot inject one. The block needs its END line: a capture cut off inside it proposes nothing, rather than half a pin. Only lines that open a JSON object (`^{`) are kept; `apply-pins.sh` validates each one against the authorization list that was fixed before any model ran.

### Decision
When `L2_SENTINEL = 1` and `PINS_SAFE = 1`, `report_pin_lines` (defined in `bin/report-format.sh`) output is staged to `pins.jsonl.tmp` and renamed to `pins.jsonl` only when non-empty. See docs/adr/0009-l2-aggregation.md#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15, "L2 is read-only" (pins grammar).

### Consequences
Do not read pins from the report body, and do not write them on a degraded capture.

## The no-sessions stub is staged, status-checked and published in one rename; a failed publish fails the run

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the stub heredoc and the publish step on the `COUNT -eq 0` path)

### Context
- A stub written straight to the report path, stopped after the questions block but before the record line (or anywhere else), would leave a half stub that `report_complete` would accept without its record. See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, 'What a report did not fully read' ("The record is a line inside the report").
- A stub that could not be opened for writing leaves the previous report in place, and that old file is complete, so `report_complete` alone would call it this run's delivery.
- A run that could not publish its report has not done what it was asked. The exit code is what the launchd job and a forced rebuild's caller see.

### Decision
- The stub is written to `$REPORT_PATH.tmp`; the heredoc's status is kept in `STUB_WRITTEN` for both the publish step and the outcome.
- Dropped-thread input is spliced in before `AUTODREAM_QUESTIONS_BEGIN` through `$REPORT_PATH.threads`, then renamed over the tmp.
- The dates a remote host missed (#230) are an open question inside the stub's questions block on this path: the-dates question is counted in the open-questions marker, so the streak store sees it and escalates it instead of reading the night as question-free.
- The report is published with `mv -f` only when `STUB_WRITTEN` is 0. On failure the temp files are removed, `log_fatal` and `fatal_exit` run, and the run returns 1; a report already at the path stays the old one.
- `write_run_outcome delivered` is written only when `STUB_WRITTEN` is 0 and `report_complete` holds; otherwise a WARNING says the stub was not written and it is not reported as delivered.

### Consequences
- Do not test `report_complete` alone to decide delivery on this path.
- Do not write the stub in place.

## superseded stale and partial copies are retired outside the `-f "$REPORT_PATH"` test

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `STALE_REPORT` removal, `drop_stale_report_copies`, the `.partial-*` loop)

### Context
- The retirement has to sit outside the `-f "$REPORT_PATH"` test (#40). A successful partial move leaves that path gone, so a stale copy went unmentioned in the one outcome where the user most needs to be told where their last good report went.
- The moved-aside copy was insurance against this rebuild producing nothing. A complete report means the insurance has expired, and dropping it stops every `--force` rebuild from leaving another `.stale-<epoch>` file in the dreams dir forever. Only a COMPLETE report supersedes the old one; a truncated file is not a rebuild.
- A delivered report also supersedes the moved-aside copies of earlier failed rebuilds, which the block above never reaches (it only knows the copy this run made). The remote-short record is read from a copy only while no report has been delivered since, so leaving them would let a label a later retry read come back.
- Partials are prefixes of a report that now exists in full, so a complete report supersedes every one for this date, including partials from earlier nights, which the `.stale-*` rule can never reach. Without this they pile up with nothing to remove them.

### Decision
`rm` the run's `STALE_REPORT` when `report_complete`; call `drop_stale_report_copies` on a delivered, complete report; delete every `$REPORT_PATH.partial-*` when complete, else name the readable partial. See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (`drop_stale_report_copies`) and "What the consume gate actually has to check (PR #37 review)" (the `.partial-*` paragraph). `drop_stale_report_copies` deletes a copy, except one holding a `## Triage decisions` heading, which is renamed to `<report>.triaged-<epoch>` because it holds the user's own writing.

### Consequences
Do not nest this under the `-f` check. A copy left in the `.stale-*` glob means nothing has been delivered since, which the remote-short lookup relies on.

## repos worth triaging are counted by the runner from its own session rows

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `TRIAGE_CANDIDATES` step; `SESSION_ROWS`)

### Context
`triage-candidates.sh` counts untriaged open issues in the repos tonight's sessions ran in and writes `triage-candidates.md` for L2 to copy into the report. L2 has no shell or `gh`, so the runner does the counting. `SESSION_ROWS` was built before any model ran, so it is the runner's own list of working directories and not something a model could have rewritten.

### Decision
The runner pipes `SESSION_ROWS` into the script; a failure logs and the report is unaffected. `AUTODREAM_TRIAGE_SUGGEST=0` turns the step off, and either way `triage_candidates: <summary>` goes into run-stats (`triage: off`, `triage: failed` or `triage: helper missing` included). See docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (`triage-candidates.{md,tsv}`).

### Consequences
Never feed the script cwds from a findings JSON or L1/L2 output. A stale list from an earlier run is removed before the step so L2 cannot copy it.

## a truncated report is moved aside as `.partial-<epoch>` so it cannot become the permanent one

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `PARTIAL_REPORT`, the move after the L2 loop)

### Context
Every attempt can leave a marker-less file behind (killed mid-write, each time), and nothing else removes it. The idempotency guard at the top of `run()` tested `-s` alone, so the very next launchd catch-up trigger would see a non-empty report, log "nothing to do" and return: the multi-trigger retry design silently disarmed by the file it exists to replace, with a half-written report standing as the day's output forever. This is the same "non-empty is not complete" error as the other three consumers, at a fourth site, and it is the one that makes the mistake permanent rather than one-night.

### Decision
When L2 was attempted and either delivery was not validated or `report_complete` is false, the file is moved to `$REPORT_PATH.partial-<epoch>`. It is moved rather than deleted: it may hold most of a report, and a partial report is worth reading even though it must not block a retry. The stub written when COUNT=0 returns long before this line, so it is never affected. A failed move is logged: later triggers will treat the date as done. See docs/adr/0001-runner-lifecycle.md#background-sleep-resilience, "Sleep resilience" (idempotency guard, "Finished means the open-questions marker is present").

### Consequences
Never make the guard accept a marker-less report. See `superseded-dream-copies-retired-outside-existence-test` for how partials are retired.
