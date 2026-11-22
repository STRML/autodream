# 0002: Sessions: roots, enumeration, the report day and accounting

Status: accepted · Governs: `bin/adapters.sh`, `bin/lib-project.sh`, `bin/preflight.sh`, `bin/oversized-gate.sh`, `bin/session-window.sh`, `bin/run.sh`

This record holds 23 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Session roots: one dir is not the corpus](#background-session-roots-one-dir-is-not-the-corpus)
- [Background: Which day a session belongs to (the report-day window, #113)](#background-which-day-a-session-belongs-to-the-report-day-window-113)
- [the adapters root is found for both the repo layout and the flat install layout, flat first](#the-adapters-root-is-found-for-both-the-repo-layout-and-the-flat-install-layout-flat-first)
- [a project key is the physical path with every byte outside `[A-Za-z0-9-]` mapped to a dash, derived once in `lib-project.sh`](#a-project-key-is-the-physical-path-with-every-byte-outside-a-za-z0-9--mapped-to-a-dash-derived-once-in-lib-projectsh)
- [the artifact key is a validated 12-character hex prefix of sha1, and nothing derives it any other way](#the-artifact-key-is-a-validated-12-character-hex-prefix-of-sha1-and-nothing-derives-it-any-other-way)
- [`day-file` renames a unique temp into place, copies the mtime, and treats an empty slice as an error](#day-file-renames-a-unique-temp-into-place-copies-the-mtime-and-treats-an-empty-slice-as-an-error)
- [a session belongs to the day its records say, by top-level `.timestamp`, compared as epoch seconds](#a-session-belongs-to-the-day-its-records-say-by-top-level-timestamp-compared-as-epoch-seconds)
- [a day slice is the raw in-window lines, with the OMP meta header kept and orphaned parentIds nulled](#a-day-slice-is-the-raw-in-window-lines-with-the-omp-meta-header-kept-and-orphaned-parentids-nulled)
- [two paths on one hash are both dropped from the worklist, the drop is verified, and the telemetry says what was enumerated](#two-paths-on-one-hash-are-both-dropped-from-the-worklist-the-drop-is-verified-and-the-telemetry-says-what-was-enumerated)
- [Cut a transcript to the report day after normalizing it, and a failed cut costs a larger read, not the session](#cut-a-transcript-to-the-report-day-after-normalizing-it-and-a-failed-cut-costs-a-larger-read-not-the-session)
- [the report-day window gate keeps a session on helper failure, and enumeration's upper date is a far one with the window on](#the-report-day-window-gate-keeps-a-session-on-helper-failure-and-enumerations-upper-date-is-a-far-one-with-the-window-on)
- [the empty-session filter drops only provably empty sessions and keeps anything it cannot parse](#the-empty-session-filter-drops-only-provably-empty-sessions-and-keeps-anything-it-cannot-parse)
- [enumerate_for delegates only to an accepted adapter, resolved once per scan, and keeps a claude-only inline find as the skew fallback](#enumerate_for-delegates-only-to-an-accepted-adapter-resolved-once-per-scan-and-keeps-a-claude-only-inline-find-as-the-skew-fallback)
- [root enumeration is judged by what it returned, per root, and never by its exit status alone](#root-enumeration-is-judged-by-what-it-returned-per-root-and-never-by-its-exit-status-alone)
- [root scanning fails loudly where a shortfall would read as a quiet night, and stays a caveat where it would not](#root-scanning-fails-loudly-where-a-shortfall-would-read-as-a-quiet-night-and-stays-a-caveat-where-it-would-not)
- [Session-loss counters are computed against RAW with collision drops subtracted and reported separately](#session-loss-counters-are-computed-against-raw-with-collision-drops-subtracted-and-reported-separately)
- [a session belongs to a report day by the timestamps inside it, with the enumeration's mtime test reduced to a lower bound](#a-session-belongs-to-a-report-day-by-the-timestamps-inside-it-with-the-enumerations-mtime-test-reduced-to-a-lower-bound)
- [a session path holding a newline or a tab is rejected at enumeration, and nothing else is](#a-session-path-holding-a-newline-or-a-tab-is-rejected-at-enumeration-and-nothing-else-is)
- [the fan-out uses NUL transport, and a session path containing a newline is rejected rather than transported](#the-fan-out-uses-nul-transport-and-a-session-path-containing-a-newline-is-rejected-rather-than-transported)
- [A session's project is the directory under the longest root that holds it](#a-sessions-project-is-the-directory-under-the-longest-root-that-holds-it)
- [session roots resolve SESSION_ROOTS, then an explicit PROJECTS_DIR, then root-probe, and an unasked folder is held out](#session-roots-resolve-session_roots-then-an-explicit-projects_dir-then-root-probe-and-an-unasked-folder-is-held-out)
- [Session rows come from the runner's own worklist and are held in memory before any model runs](#session-rows-come-from-the-runners-own-worklist-and-are-held-in-memory-before-any-model-runs)
- [in the tab-separated session lists the adapter name comes first and the path last](#in-the-tab-separated-session-lists-the-adapter-name-comes-first-and-the-path-last)

## Background: Session roots: one dir is not the corpus

This section was moved here from the former CLAUDE.md. Its original title: "Session roots: one dir is not the corpus".

The user runs several Claude config dirs at once (`~/.claude-nous`, `~/.claude-ds4`,
`~/.claude-sigint`, ...), each with its own `projects/` bucket. autodream used to scan
only `$HOME/.claude/projects`, so the nightly report silently stopped seeing the real
work — triage collapsed 132 → 7 → 8 → 1 sessions/night on 2026-08-03…06 purely because
the sessions had moved to the other buckets. The fix is multi-root scanning:

- `SESSION_ROOTS` (colon-separated) wins; else `PROJECTS_DIR` (single root, kept for
  compat); else autodetect every `$HOME/.claude*/projects` via `bin/root-probe.sh`,
  primary first. `run.sh` logs the resolved list every run.
- `WORK_BUCKET` stays keyed off the PRIMARY dir: lean workers run under the default
  config, so their AI-title stubs land in the default bucket — scanning extra roots
  does not change the isolation/wipe story.
- `root-choices.conf` remembers the per-folder index decision. install.sh runs
  root-probe with `--ask` on a TTY, `--default-index` otherwise, and writes the managed
  `SESSION_ROOTS` section to `config` (the awk in install.sh converges re-installs by
  dropping the old managed section first). The nightly run passes neither flag, so it
  never writes choices — unindexed roots are *reported* (`findings/<date>/unindexed-roots.txt`)
  instead, which is the "found a folder, ask the user" surface.
- Semantics: a folder is scanned iff it's `index` or the always-on primary. An *unasked*
  folder is held out of the report until the user decides — that's what the flag
  "found a folder we're not indexing" means, and scanning it would make the flag a lie.
  `--default-index` on install flips every unasked folder to `index` so a fresh install
  covers everything silently.
- Compatibility (verified 2026-08-07 against real files): claude-code-router wraps
  sessions in a `{"type":"queue-operation",...}` envelope before the normal records —
  `session-stats.sh`, `prune-self-sessions.sh`, and L1's prompt all key off
  `.type == "user"`, so the envelope is invisible to them. cc-ds4's transcripts are
  standard shapes under `projects/` (its `history.jsonl`/`spend-ledger.jsonl` live
  outside `projects/`, so the glob never trips on them). ccam keeps an accounts file,
  no transcript store. The `projects/`-bucket glob IS the compatibility layer.
- run-stats carries `session_roots` (count) + `session_roots_list` so a regression to
  single-root scanning is visible from the artifact.

## Background: Which day a session belongs to (the report-day window, #113)

This section was moved here from the former CLAUDE.md. Its original title: "Which day a session belongs to (the report-day window, #113)".

A session is placed in a report day by the timestamps INSIDE its transcript, not by its file mtime. Enumeration was `find -newermt DAY ! -newermt NEXT`, so a session written to again after its day closed (a resumed session, or OMP rewriting its title line) dropped out of every later rebuild of that day. On 2026-09-01 a rebuild of 2026-08-21 kept the two advisor sidecars and lost the two parents they described, then reported `l1_missing_after_retries: 0` over the short corpus. Two decisions carry it:

- **The adapter contract did not change.** `enumerate` still takes `(root, from, to)` and still filters on mtime. `run.sh` passes it a far `to` (the report day plus five years, as `ENUM_END`), so the mtime test becomes a lower bound: a file last written before the day began cannot hold a record from it. `bin/session-window.sh in-window` then keeps a file when at least one record has a top-level `.timestamp` string inside `[local midnight, next local midnight)`. The bounds come from BSD `date`, so a DST day is 23 or 25 hours. The five-year date is not a year-9999 sentinel because BSD `find` on some macOS releases fails with "Can't parse date/time" on a distant date; `run.sh` also probes the date with the same `find` before using it.
- **Both harnesses write the same field, and it is the only one read.** Measured on this host's OMP store (1,348 sessions): every record except the `title` slot carries a top-level `timestamp` in the form `2026-10-01T16:12:38.483Z`. `message.timestamp` on an OMP message is an epoch-millisecond NUMBER on a record that already has the string, and is deliberately ignored. A record whose timestamp is missing, null, numeric or in another shape has no clock: it neither selects a file nor lands in a slice.

What the verdict is, per file: records with clocks and one inside the day -> in. Records with clocks and none inside -> out, counted in `sessions_out_of_window` (this includes a file touched inside the day whose records are all older, which an mtime-only run triaged under the wrong day). No clock at all -> placed by mtime exactly as the bounded find placed it, so a no-clock file touched after its day still drops out of that day's rebuild; there is nothing else to place it by. A helper failure (exit 2) keeps the session: extra work, never a dropped session.

**The slice.** The stats and the L1 worker read the day's records of a transcript that spills outside the day. `session-window.sh day-file` writes the slice only when some timestamped record lies outside the day (so a single-day transcript is read byte for byte as before), carries the original's mtime (so `transcript_mtime` in the sidecar still describes the session), and treats an empty slice as an error, so the caller reads the whole transcript rather than nothing. The order is the part that bites: **normalize first, cut second.** OMP sessions are linearized to the live chain and the chain is cut. Cutting the raw tree leaves entries whose parent was cut away, and `linearize.sh` fails closed on a dangling `parentId`, which would refuse every OMP session that spans a day boundary. The slice keeps the `autodream_meta` header (it has no clock, and `stats.sh` and `project` read it) and writes the first kept entry with `parentId` null, so the slice is a closed chain. An OMP session whose only entries inside the day are on an abandoned branch has a meta-only slice, no user turns, and is noise-gated, not read whole. `compute_session_stats` and the worker both do it, in that order, and both clean up `<hash>.statsday.jsonl` / `<hash>.day.jsonl`. A worker handed a slice is told so (a `## Report day` paragraph in its prompt).

What the cut changes in the numbers: `duration_minutes`, user-turn and tool counts, the noise gate, the overlap pass and the oversized gate now describe the day. `transcript_bytes` is the size of the file the worker reads, so for a multi-day session it is the slice's. `oversized-gate.sh`'s fallback still `wc -c`'s the whole transcript when a sidecar is missing.

**Both halves of #113.** (a) The session is back in the corpus. (b) Because it is back in `sessions.txt`, the existing retry loop dispatches it (no findings JSON), `l1_missing_count` counts it, and a successful worker deletes its stale `.err`. That is the case the issue observed, and `test_rebuild_keeps_a_session_touched_after_its_day_and_retries_its_stale_err` reproduces it (no report, a pre-seeded `.err`, a session touched three days later) and fails on `origin/main` on exactly those assertions. What re-enumeration cannot fix is an `.err` whose session is no longer in the worklist at all (the file was deleted, or `AUTODREAM_WINDOW=0`). That one is counted as `l1_err_files_orphaned` and named in the log, not retried: the `.err` is the only record of which session it was, and a worker with the Write tool could have put any path in it. `l1_err_files` still counts every `.err` in the directory. The same scan runs on a night with nothing to triage (the early stub exit), so a stale failure is not reported as zero there either.

**Findings left by an earlier run (#56).** A rebuild of a date first run on file mtime keeps whatever findings JSONs that run wrote, including those for a session the window no longer places in the day, and L2 reads every findings JSON in the directory. Before L1, `reconcile_findings_with_worklist` moves each JSON outside this run's worklist into `findings/<date>/outside-worklist/` (counted as `l1_findings_outside_worklist`, named in the log) so L2's glob cannot reach it. Moved, not deleted; it is restored when its session is back in a later worklist. A clean rebuild still means removing the date's findings directory first if the stale files should go for good, as "Running / rerunning a date" says.

`AUTODREAM_WINDOW=0` restores mtime-only placement. The window is also off, and run-stats say `session_window: off`, when `session-window.sh` cannot be found (found through `find_lib`, so the checkout counts before `install.sh` re-links), the day will not convert to epoch bounds, or this `find` rejects the far date. The five-year reach is a limit, not an accident: a session last written more than five years after a report day is not found by a rebuild of that day.

Things that cost time here: the L1 worker is a single-quoted `bash -c` and the new code in it must have no apostrophes; the L1 fan-out used to hit `xargs -I {}`'s 255-byte argument limit (a long `TMPDIR` plus a nested OMP child path); it is NUL-delimited with `xargs -0 -n 1` now (#54), so that limit is gone; fixtures with timestamps must put them inside `DATE`, because a record outside the day now outranks the mtime that `touch -t` gave the file; and under the Claude Code sandbox `git init` fails on `.git/hooks` inside the worktree, after which the changelog tests run their `git` calls against the ENCLOSING repo (one run rewrote the branch under test), so point `TMPDIR` for `tests/run-all.sh` outside any checkout.

## the adapters root is found for both the repo layout and the flat install layout, flat first

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`adapters_root`)

### Context

Two layouts have to work. In the repo, `bin/` and `adapters/` are siblings. Under the install, `install.sh` symlinks everything flat into `~/.claude/autodream`, so `adapters/` sits beside `adapters.sh` rather than one level up. Assuming only one of them is how the first version of this change shipped a silently broken install.

### Decision

`ADAPTERS_ROOT` wins when set. Otherwise `adapters_root` checks `<dir of adapters.sh>/adapters` first and falls back to `<dir of adapters.sh>/../adapters`. The flat layout is checked first because the nightly runs from the installed copy, which is the expensive one to get wrong.

### Consequences

A change to where `install.sh` links the adapters tree has to keep one of these two shapes (see `docs/adr/0023-install-and-scheduling.md#installsh-links-the-adapters-tree-whole-and-restores-each-adapters-exec-bit`). Check the installed copy after touching `adapters_root`, since the nightly runs from it.

## a project key is the physical path with every byte outside `[A-Za-z0-9-]` mapped to a dash, derived once in `lib-project.sh`

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-project.sh` (`encode_project`, `canonical_project`)

### Context

Claude derives a project bucket name from the session's cwd by mapping everything outside `[A-Za-z0-9-]` to a dash, on the symlink-resolved physical path. Verified against real buckets on the host:

```
/Users/<u>/.claude                      -> -Users-<u>--claude
/private/var/folders/c2/29g..z_4tv..gn  -> -private-var-folders-c2-29g..z-4tv..gn
/Users/<u>/Documents/Personal Items/..  -> -Users-<u>-Documents-Personal-Items-..
/Users/<u>/../Personal House (39 Loring)/Improvements
                                        -> ..-Personal-House--39-Loring--Improvements
```

An encoder that maps only `/` breaks on all of them, and silently: the record still carries a cwd, so nothing counts it as unreconciled and the project just splits in two.

The first encoder was `tr '/._' '---'`, which is what an eyeball survey of dash-shaped bucket names suggests, and what a survey of this repo's own paths confirms, because none of them contain a space. Measured instead: of the 96 path-derived buckets under `~/.claude/projects` on the host, the three-character form gets 89 and the complement form gets all 96. Every miss is a space or a parenthesis. The host also carries the artifact of that bug: a stale `-Users-…-Personal Items-…-RAW` bucket holding an empty `memory/` beside the live `-Personal-Items-` one that holds the sessions. That is a project split in two, already on disk.

Non-ASCII, verified 2026-10-04 by running `claude -p` in a directory named `café-日本-😀`: Claude emits one dash per UTF-16 code unit. A BMP character (2- or 3-byte UTF-8) is one dash, and an astral character (4-byte UTF-8, a surrogate pair) is two.

### Decision

- `encode_project` ends in `tr -c 'A-Za-z0-9-' '-'`, the complement form. `LC_ALL=C` is load-bearing: `tr -c` complements the set, and under a UTF-8 collation `A-Za-z` is a wider set than the 52 ASCII letters. The complement then shrinks, and characters that must be mapped silently are not.
- `tr` is byte-oriented and would give one dash per byte, so `sed` first collapses each multi-byte sequence to the dashes Claude emits. Lead byte F0-F7 starts a 4-byte sequence (two dashes), E0-EF a 3-byte one and C0-DF a 2-byte one (one dash each). The 4-byte rule goes first, so a 4-byte sequence is not consumed as a 3-byte one plus a stray byte. The byte ranges are raw bytes through `$'..'`, because BSD `sed` has no octal escapes inside a bracket.
- The key is derived once, here, because every adapter must produce the same key for the same real directory. That makes one project out of two harnesses' work, and it is why the design has no reconciliation pass: deriving the key once at triage time removes the failure rather than fixing it.
- Claude records the physical path, so a session in `/tmp/foo` is stored under `-private-tmp-foo`. A harness that reported an unresolved cwd would produce `-tmp-foo` and group as a different project, so `canonical_project` resolves with `realpath` first. It exits 1 and prints nothing rather than encode something unresolved, because a wrong key splits a group and a silent split is what the function exists to prevent.
- `canonical_project` tests `[ -e "$1" ]` before `realpath`. GNU `realpath` resolves a missing leaf and BSD `realpath` refuses it, so the explicit test makes a missing path fail on both.

### Consequences

A change to the character set or to the multi-byte handling re-keys every project. Re-measure against the real buckets, and against a non-ASCII directory, before touching it. `tests/lib-project.sh` pins the cases above.

## the artifact key is a validated 12-character hex prefix of sha1, and nothing derives it any other way

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-project.sh` (`session_hash`), `bin/preflight.sh` (`need shasum`), `bin/oversized-gate.sh`

### Context

`h=$(printf %s "$p" | shasum -a 1 | cut -c1-12)` has two silent failure modes that end in the same place. `cut` masks `shasum`'s exit status, so a `shasum` that exists (satisfying preflight) but fails at runtime yields an empty hash, and every session then targets the same artifact. A short or non-hex result does the same. A missing `shasum` has the same effect: every session in the night writes to one findings filename, the run ends with one record where it should have had a hundred, and nothing in the existing code notices.

`bin/oversized-gate.sh` had the same hole on the reading side. With `shasum | cut` there, a runtime-failing `shasum` yielded an empty key, so the gate consulted `.stats.json` and `.json` for every session and could undercount errored oversized sessions. It reported GATE CLOSED off a measurement that never happened.

The character set is enumerated, not a range. Verified on the host: under bash 3.2 with an en_US.UTF-8 collation, `A` matches `[0-9a-f]`, and under bash 5.3 it does not. The nightly runs `#!/bin/bash`, which is 3.2, so the range form accepted uppercase exactly where it matters. It is the same collation behavior that made an uppercase adapter basename pass on CI and fail locally.

### Decision

`session_hash` captures the `shasum` output without a pipe so its status is seen, takes the first 12 characters, and prints them only when the prefix is 12 characters long and holds nothing outside `0123456789abcdef` (a negated `case` pattern). Otherwise it returns 1 with nothing on stdout. A caller treats a failure as "this session cannot be keyed": `oversized-gate.sh` counts it as unmeasurable and leaves it out of the ratio. `preflight.sh` makes a missing `shasum` a hard stop, because it is the one dependency whose absence produces no error at all.

### Consequences

Call `session_hash` instead of deriving a hash inline. The hex digits are listed out on purpose; do not replace the list with a range such as `[0-9a-f]` without re-running the bash 3.2 collation check.

## `day-file` renames a unique temp into place, copies the mtime, and treats an empty slice as an error

Status: accepted · Date: 2026-11-21 · Code: `bin/session-window.sh` (`day-file`)

### Context

`day-file` is the one call the runner makes: write the day slice of a transcript to a path when it spills outside the day.

### Decision

- Exit 1 leaves OUT alone, so a transcript wholly inside the day is read exactly as before.
- The slice goes to a unique temp beside OUT and is renamed, so a killed run never leaves a half slice that a later step reads as whole.
- The temp takes the original's mtime (`touch -r`), so `transcript_mtime` in the stats sidecar still describes the session and not the moment of slicing.
- An empty slice is exit 2. It means the file changed since enumeration, or no record survived the cut and there was no `autodream_meta` header to keep. That is no verdict on the session, so the caller reads the whole transcript instead of nothing.

### Consequences

An OMP session whose only in-day entries are on an abandoned branch gets a meta-only slice from the normalized copy and is noise-gated by the runner, not read whole. See `docs/adr/0002-session-enumeration.md#a-day-slice-is-the-raw-in-window-lines-with-the-omp-meta-header-kept-and-orphaned-parentids-nulled`.

## a session belongs to the day its records say, by top-level `.timestamp`, compared as epoch seconds

Status: accepted · Date: 2026-11-21 · Code: `bin/session-window.sh` (`in-window`, `bounds`)

### Context

Enumeration selected a session by file mtime inside the report day, so a session written again after its day closed (a resumed one, or OMP rewriting its title line) vanished from every later rebuild of that day, and a transcript spanning several days was read whole for each of them (#113).

### Decision

- The window is `[START, END)`: local midnight to the next local midnight from BSD `date` (`bounds`), so a DST day is 23 or 25 hours.
- A record's clock is its top-level `.timestamp` string (`2026-10-01T16:12:38.483Z`), which both harnesses write. An OMP `.message.timestamp` is an epoch-millisecond number on a record that already has the string, and is deliberately not read. A record whose timestamp is missing, not a string or not ISO-8601 UTC has no clock: it neither selects a file nor lands in a slice.
- Timestamps compare as epoch seconds with the fraction dropped, not as strings: `00.5Z` sorts before `00Z` lexicographically, which misplaces the boundary second.
- `in-window` is yes when any record is inside, no when records have clocks and none is inside, and when no record has a clock the file's mtime decides (before the day ended: yes, so it is biased to triage). Without that, the find that no longer has an upper bound would enumerate a clockless file on every later date and triage it twice under the wrong day.
- An unreadable file or a failing jq is exit 2, never 1. The caller keeps the session on an error, so a broken helper costs extra work and never reads as a quiet night.

### Consequences

docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to (the report-day window, #113)", carries the runner side. `tests/session-window.sh` pins DST bounds with literal expected values.

## a day slice is the raw in-window lines, with the OMP meta header kept and orphaned parentIds nulled

Status: accepted · Date: 2026-11-21 · Code: `bin/session-window.sh` (`needs-slice`, `slice`, `TS_DEF`)

### Context

A transcript that spills outside the report day must be read as its day's records only, but the slimmer and the stats should see the bytes that were written. A linearized OMP chain links each entry to the one before by `parentId`, and `linearize.sh` refuses a parent with no entry behind it.

### Decision

- `needs-slice` is yes when any timestamped record lies outside the window, found with an early exit. The first-and-last-record shortcut assumes a chronological file, and one that is not would be read whole and leak other days in. A file wholly inside the day costs one full read, the same order as the stats pass.
- `slice` emits raw lines, not re-serialised. A torn line or a record with no clock is dropped: with a window set, a record that cannot be placed is not evidence for the day.
- `autodream_meta` stays in every slice. It names the session (cwd, advisor, nested) and the stats and project lookup read it.
- Every kept entry whose parent was not kept is written with `parentId` null, so every `parentId` left resolves inside the slice. Nothing reads it after linearizing, but a closed chain cannot become a refusal in a later reader.
- The jq programs sit in single-quoted shell strings, so none may contain an apostrophe.

### Consequences

Those `parentId` rewrites are the only records that are not byte for byte. Normalize before cutting: cutting the raw OMP tree leaves dangling parents that `linearize.sh` refuses. See `docs/adr/0002-session-enumeration.md#day-file-renames-a-unique-temp-into-place-copies-the-mtime-and-treats-an-empty-slice-as-an-error` for the file the runner calls.

## two paths on one hash are both dropped from the worklist, the drop is verified, and the telemetry says what was enumerated

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`build_source_sidecar`)

### Context

Two different session paths can truncate to one 12-character hash and would race for one `<hash>.json`. There is no sensible winner. An earlier version logged "skipping both" while skipping neither: it removed the sidecar row and left both paths in `sessions.txt.raw`, so two workers still raced and silently overwrote each other. The log said one thing and the code did another, which is worse than not checking at all.

Other earlier faults, each fixed: `grep -v` exits 1 when it removes the only line, so a guarded `&& mv` left the stale mapping behind in the single-entry case; the earlier path is appended again for every later collision on one hash (three paths sharing a hash gave A,B,A,C, four lines for three drops) and the duplicate propagated into the telemetry; overwriting RAW with the post-drop worklist size made a forced two-session collision report `sessions_found_raw: 0` and "0 session file(s) were enumerated".

### Decision

On a collision (two different paths on one hash; the same path reached twice is only a counted duplicate and the first is kept) the helper appends both paths to `.collided`, logs `COLLISION` and removes the hash's sidecar row, and a failed append is fatal (`log_fatal`, return 1). After the walk, if the drop set is non-empty:

- it is deduplicated with `sort_unique_inplace`; both the worklist filter and the post-filter verification read it, so a damaged one would let a collided path through while everything reports success;
- the worklist (`sessions.txt.raw`) is rewritten with `rewrite_filtered -vxF -f` and that rewrite FAILS CLOSED (`log_fatal`, return 1), because leaving it unchanged means two workers on one artifact;
- the drop is verified rather than trusted: `grep -qxF -f` must exit exactly 1; anything above 1 is an I/O error and refuses, because grep's "not found" is the wanted answer and the same code path would otherwise take success on an error;
- `RAW` stays the ENUMERATED count; `COLLIDED_DROPPED` counts the dropped paths separately;
- the provenance rows of the dropped hashes are removed, but only for COLLISION drops: the sidecar is built before the self-prune and the empty-session filter, so it still carries rows for worker transcripts and 0-turn shells that are later excluded. The original comment said nothing consumes the sidecar yet; that is stale (`AUTODREAM_SOURCE_MAP`, `rollup.sh` and `threads.sh` read it), so any consumer that joins it against `<hash>.json` must expect hashes with no findings record;
- sidecar row rewrites are DELIBERATELY survivable (`|| :`): a stale row overstates `sessions_by_source` by one and the helper has already logged why. The row rewrite is not counted at the attempt, see `sidecar-stale-row-count-measured-from-final-sidecar`.

### Consequences

Never make the worklist rewrite survivable, and never make the provenance row rewrite fatal without also deciding what a non-collided night should do. The worklist counts feed the `found ... excluded ... skipped` log line, so keep RAW as the enumerated total.

## Cut a transcript to the report day after normalizing it, and a failed cut costs a larger read, not the session

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`day_slice`, `compute_session_stats`)

### Context
Issue #113 (report-day window). A tree-shaped transcript (omp) is linearized by its adapter. Cutting the raw tree would leave entries whose parent was cut away, and the linearizer fails closed on a dangling parent, which would refuse every omp session that spans a day boundary.

### Decision
The order is normalize first, cut second, the same one the worker uses: a tree is linearized FIRST and the live chain is what gets cut. `day_slice` returns 0 when the slice was written, 1 when there is nothing to cut (the window is off, or every timestamped record is already inside the day; the destination is untouched), 2 when the helper failed. On 2 the caller reads the whole transcript: `compute_session_stats` logs a WARNING that its stats cover the whole transcript. A failed cut costs a larger read; it never costs the session.

See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to (the report-day window, #113)" (The slice).

### Consequences
Do not reorder the steps. A new caller must handle all three return codes.

## the report-day window gate keeps a session on helper failure, and enumeration's upper date is a far one with the window on

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots`, `enumerate_for`, `ENUM_END`), `bin/session-window.sh`

### Context

See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to (the report-day window, #113)". The adapter's `enumerate` still filters on mtime, so with the window on the find bounds mtime from below only. A file modified after the day closed is kept when it holds a record inside the day, and a file modified since the day began that holds none is left out.

### Decision

With `WINDOW_ON=1`, `scan_roots` runs `session-window.sh in-window <path> <start epoch> <end epoch>`. Exit 1 is the verdict: records with clocks and none in the day, or no clock at all and modified after the day (its mtime decides, as the bounded find decided). That session is counted in `OUT_OF_WINDOW` and skipped, so it cannot read as a quiet night. Any other status is the helper failing and the session is kept. `enumerate_for` passes `ENUM_END` as the upper date: the day after the report day with the window off, the report day plus five years with it on (`pdate_shift ... 5 y`, so the mtime test is only a lower bound), where the in-transcript timestamps decide instead.

### Consequences

A failing helper must cost extra work, never drop a session; do not turn a non-1 status into a skip. `OUT_OF_WINDOW` shows in the run log's "found N session files" line. See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113 for the five-year reach limit and for `AUTODREAM_WINDOW=0`.

## the empty-session filter drops only provably empty sessions and keeps anything it cannot parse

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`filter_empty_sessions`, `session_is_substantive`)

### Context

Most of a quiet night's corpus is auto-opened or aborted sessions with no user input: observed ~150 of 163 files on 2026-05-30 were single-line `ai-title` shells. Each costs an L1 worker for zero signal. But dropping a real session silently is worse than one wasted call.

### Decision

A session is SUBSTANTIVE if it holds at least one `user` turn that is not `isMeta:true`. `session_is_substantive` returns 1 (skip) only when `jq -s` parses the file and finds none; an unreadable or unparseable file is kept (returns 0). The predicate reads both transcript shapes, because the worklist holds every enabled harness: a Claude user record that is not meta, or an OMP `message` record with role user holding a text item. OMP UI-only `custom_message` records never count. `filter_empty_sessions` reads a worklist on stdin and prints the substantive subset; `AUTODREAM_SKIP_EMPTY=0` turns the filter off.

### Consequences

The bias is to triage: the cost of a miss is one wasted model call. A new transcript shape needs its own clause in the `jq` expression or its sessions will all be dropped as empty. The filter is independent of the self-prune, so their telemetry counts do not overlap (`SKIPPED_EMPTY` is derived from the count after the prune).

## enumerate_for delegates only to an accepted adapter, resolved once per scan, and keeps a claude-only inline find as the skew fallback

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`enumerate_for`, `scan_roots`)

### Context

An install whose `adapters/` tree predates the adapter loader (a stale link after a partial upgrade) must degrade, not lose the night, so an inline `find` stays as the fallback. That fallback hardcodes `*.jsonl`, and nothing reads `session_glob` from a manifest, so walking another harness's roots with the Claude glob would return nothing and read as a quiet night: a silent wrong answer rather than a loud one.

Checking only that `adapter.sh` is executable would run a directory that failed containment. Rebuilding the accepted set through `adapters_list` for every root costs two realpaths and a `jq` per adapter directory, and the answer cannot change mid-run because nothing writes to `adapters/` while a scan is in flight.

### Decision

`enumerate_for` calls `adapter_run <adapter> enumerate <root> $TARGET_DATE $ENUM_END` and returns its status unchanged (`return $?`, never a constant; see `enumeration-judged-by-output-not-status`) only when all three hold: the `adapter_run` function is defined (`declare -F adapter_run`, false on an install whose `adapters/` tree predates the loader), the adapter is in `ACCEPTED_ADAPTERS`, and its `adapter.sh` is executable. `scan_roots` assigns `ACCEPTED_ADAPTERS` once, from `adapters_list`. Anything else falls to the inline `find`, which is claude-only: for any other adapter name it logs "no adapter for ... no fallback that knows its session format" and returns 1, so the root counts as failed (see `enumeration-judged-by-output-not-status`).

### Consequences

The comment on the fallback called it unreachable "because only claude is ever enabled" and said it becomes live once a second adapter ships beside a stale `adapters/` link. The omp adapter is now accepted and can be enabled through `AUTODREAM_ADAPTERS`, so that skew is reachable (this is the ADR's reading, not the comment's). Do not give the fallback a non-claude glob. Do not move the `adapters_list` call back inside the per-root loop.

## root enumeration is judged by what it returned, per root, and never by its exit status alone

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots`, `enumerate_for`)

### Context

BSD `find` exits 1 when a single subdirectory is unreadable or vanishes mid-walk, and still prints every other match. Verified on this host: 3 files, one locked directory, exit 1, two paths printed. It exits 1 for any unreadable subdirectory anywhere in the walk, with or without matches; without one, exit 0. Treating a nonzero status as fatal threw away a usable corpus and produced no report on a night that previously produced a full one, which is worse than the silent zero the check exists to catch.

Multi-root scanning is the tool's premise: a secondary root (`~/.claude-nous/projects`, `~/.claude-sigint/projects`) legitimately matches nothing on a given date. One permission-denied directory under a quiet secondary root used to kill a night on which the primary root had a full corpus, and kill it invisibly, because `run()` returned 1 before `notify.sh` ran and no findings JSONs existed for `unassembled_dates()` to notice.

`enumerate_for` once ended in a literal `return 0`, which silently defeated the caller's status check: enumeration was staged to a file and the exit code examined, and the wrapper handed it a success every time. The suite passed 306 assertions over that, because none ran an adapter whose enumerate fails. `tests/run-all.sh` has one now.

### Decision

Each root's NUL-delimited output is staged to `$FINDINGS_DIR/.enum.XXXXXX` and the status is read after. Nonzero status with output is a partial walk: `PARTIAL_ROOTS` counts it, the log says the corpus is possibly incomplete, and the run goes on. Nonzero status with no output counts `ROOTS_FAILED`, logs that the root contributes no sessions and moves to the next root; a failed root is never fatal on its own. The comment in the code said an all-roots-failed case after the loop still refuses to report; that comment is stale. What the code does is the run-level fatal `all N configured session root(s) are unavailable`, which fires only when every configured root was not a directory (`ROOTS_SCANNED` stays 0). When every root was reached and failed to enumerate, the run completes, and the zero-session stub says the store was not fully read (`roots_failed` and `roots_unavailable` in run-stats) instead of claiming no session files were modified. `enumerate_for` returns the adapter's own status (`return $?`), never a constant. The staging file is removed on every exit, including the fatal one when a session list write fails: under `AUTODREAM_FORCE=1` the findings dir is reused across reruns, so repeated failures would pile `.enum.*` files into the directory the aggregator globs.

### Consequences

A shrinking corpus must stay visible in the log and in the `PARTIAL_ROOTS` / `ROOTS_FAILED` counters; do not fold either into "quiet night". Do not make a lone nonzero status fatal again (`test_one_failed_root_does_not_kill_the_night`, `test_partial_enumeration_keeps_what_it_read` and `test_failing_enumerator_aborts_the_run`, whose name predates the change and which now asserts the run completes, pin this), and do not replace `return $?` in `enumerate_for` with a success. Remote-sync's `remote_short_labels` also reads these counters (a failed root cannot be told from a mirror), see docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts".

## root scanning fails loudly where a shortfall would read as a quiet night, and stays a caveat where it would not

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots`, `scan_one_adapter`)

### Context
A report written from a corpus the run never saw looks complete and cannot say so itself. Several distinct causes need distinct treatment:
- Two colliding paths in the raw worklist while `.src` lost a row would send both to dispatch (the same fail-open overwrite as the collision index, one stage earlier).
- No usable adapter is a TOTAL outage with a mundane trigger: `adapters/claude/adapter.sh` losing its exec bit to a tarball copy, a restrictive umask or `core.fileMode=false`, since `_adapter_ok` requires `-x`. A host that produced a full report last night then produces nothing, every night.
- BSD find exits 1 when a single subdirectory is unreadable or vanishes mid-walk while still printing every other match (verified: 3 files, one locked directory, exit 1, two paths printed). Treating that as fatal threw away a usable corpus and produced no report on a night that previously produced a full one.
- Reading the adapter through process substitution hid the producer's exit code, so a root that failed on permissions or I/O emitted nothing and the run finalised a cheerful "no sessions" report over a corpus it never saw.

### Decision
- Both `sessions.txt.raw` and `.src` are truncated and checked; failure to write either is a fatal (`cannot write the session lists`).
- When no adapter is enabled, the two causes get different messages (the loader accepted nothing, versus it accepted adapters but none is enabled), because the first sends the reader hunting a containment or manifest failure that never happened for the second. The marker and banner come from `fatal_exit` (see `fatal-exit-marker-and-banner`); `log_fatal` carries the reason to it.
- Enumeration is staged to a file and its status is CHECKED. The distinction is output, not status: nothing read from a root AND a failure counts `ROOTS_FAILED`, logs that the root contributes NO sessions and moves on to the next root (the run does not stop; an old comment in the code said it did, and was stale); something read with a failure is a partial walk, counted in `PARTIAL_ROOTS` and logged as a possibly INCOMPLETE corpus.
- The "all configured roots unavailable" fatal is about roots never REACHED (`ROOTS_SCANNED` is 0 with `ROOTS_CONFIGURED` above 0, and the roots are not the bare fallback). It deliberately does NOT subtract `ROOTS_FAILED`: that looked symmetric and was a regression, because on a single-root host (the default install) "enumerator exited nonzero and returned nothing" is the exact shape of a quiet date plus any transient find error, and that host would then get no report on a night whose honest answer is the empty-night stub. A failed root is not silent regardless: it warns in the log, increments `roots_failed`, reaches `run-stats.txt` on both the zero-session and full paths, and PROMPT.md's Corpus integrity bullet names it in the morning report. That is the right weight for "we read less than we meant to": a caveat on the night, not the loss of it.

### Consequences
Do not "fix" the asymmetry: the fatal at the end of `scan_roots` tests `ROOTS_SCANNED` (roots never reached) and deliberately does not subtract `ROOTS_FAILED` (roots reached whose enumerator failed with no output). A host with no roots configured (`ROOTS_CONFIGURED` 0) stays legitimate and is not fatal; without that guard `RAW` and every shortfall counter would be 0 and the stub would say no files were modified. Do not switch the enumeration back to `<( ... )`. See docs/adr/0010-rollup-and-run-stats.md#background-self-audit, "Self-audit" for the degraded-measurement rule.

## Session-loss counters are computed against RAW with collision drops subtracted and reported separately

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `EXCLUDED`, the zero-session stub text, `DROPPED_AFTER_FAILURES`)

### Context
- Hash-collision drops leave the worklist before the self-prune runs. Charging them to `EXCLUDED` made a forced two-session collision report `self_sessions_excluded: 2`, the report calling files "autodream-own" that were nothing of the kind.
- `RAW` stays the ENUMERATED count and is never overwritten with the post-drop worklist size: doing that made a forced two-session collision report `sessions_found_raw: 0` and "0 session file(s) were enumerated", telling the reader nothing was there when two files were, dropped for cause (see `collided-sessions-dropped-both-and-verified`).
- `HASH_COLLISIONS` counts collision events and each drops at least two paths, so adding it to a path total understates the loss. Refused paths never reach `sessions.txt.raw`, so they are not part of `RAW` either. Folding them into "N session file(s) were modified" produced sentences like "0 session file(s) were modified ... 3 with an unrepresentable path".
- The 2026-06-11 self-audit caught sessions enumerated by `find` but unaccounted for at run end: 12 `.err` files existed while stats showed `l1_missing_after_retries=0`, because both denominators counted from the POST-prune `sessions.txt`.

### Decision
- `EXCLUDED = RAW - COLLIDED_DROPPED - COUNT_AFTER_PRUNE`, floored at 0.
- `SKIPPED_EMPTY = COUNT_AFTER_PRUNE - COUNT` is taken after the self-prune, so it never overlaps `EXCLUDED`: the two telemetry counts are disjoint.
- The zero-session stub sentence reports `RAW`, `EXCLUDED`, `SKIPPED_EMPTY`, `REJECTED_PATHS` and `HASH_COLLISIONS` as separate numbers. The local `refused = REJECTED_PATHS + HASH_COLLISIONS` is only a zero test selecting which sentence prints.
- `DROPPED_AFTER_FAILURES = RAW - COLLIDED_DROPPED - L1_OK - EXCLUDED - SKIPPED_EMPTY`, floored at 0 against a counting bug in the prunes. Computing against RAW and subtracting the legitimate prunes means a session lost to a filter mis-classification or a silent worker death surfaces here. Collision drops are deliberate, not failures, and have their own key (`sessions_dropped_to_collision`).

### Consequences
- Keep the two facts as two numbers: a combined figure is wrong either way.
- Counting from the post-prune list again hides lost sessions.
- A new legitimate drop between RAW and L1 needs its own subtraction here, or it reads as a failure.

## a session belongs to a report day by the timestamps inside it, with the enumeration's mtime test reduced to a lower bound

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`SESSION_WINDOW`, `ENUM_END`, `WINDOW_ON`, `WIN_START_EPOCH`, `WIN_END_EPOCH` block)

### Context
A session written to again after its day closed (resumed, or still running) used to drop out of every later rebuild of that day, and a transcript spanning several days was read whole for each of them (issue #113). See docs/adr/0002-session-enumeration.md#background-which-day-a-session-belongs-to-the-report-day-window-113, "Which day a session belongs to (the report-day window, #113)".

### Decision
- The adapter contract is unchanged: `enumerate` keeps its `(root, from, to)` arguments and still filters on mtime. The runner passes it a far upper date (`ENUM_END` = report day plus five years), so the mtime test is a LOWER bound only (a file last written before the day began cannot hold a record from it). `bin/session-window.sh` then keeps the files with a record inside the day and cuts the stats and the worker's read to that day's records.
- "Far" is five years, not a year-9999 sentinel: BSD find on some macOS releases cannot parse a distant date and fails with "Can't parse date/time", so the date is also probed here with the same `find` the adapters run (`find / -maxdepth 0 ! -newermt ...`).
- The window is ON only when every piece works: the helper is found (via `find_lib`, for the partial-install reason in `helper-lookup-survives-partial-install`, and run through `bash`, not gated on `-x`, for the reason preflight.sh is: a distribution path that loses the exec bit, such as a zip or a restrictive umask, would make an `[ -x ]` gate skip the check silently), it turns the report day into epoch bounds, and the far date computes and is accepted by this host's find. Any one missing leaves the original bounded enumeration (`ENUM_END` = next day), so a degraded install reads exactly what it read before and never fails a night over this. `AUTODREAM_WINDOW=0` forces it off.

### Consequences
A session last written more than five years after its report day is not found by a rebuild of that day. Fixtures with timestamps must put them inside the date, since a record outside the day outranks the file's mtime.

## a session path holding a newline or a tab is rejected at enumeration, and nothing else is

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter`, the `case "$sp"` check)

### Context

The line-based artifacts cannot carry two characters. `sessions.txt` is line-delimited: `find` writes a path with a newline as two lines, and the runner then triages a session that does not exist. `pin-projects.tsv` and the source map are tab-separated, so a tab in a project directory or session path shifts their columns. Both were verified on this host against the real consumers rather than assumed.

Backslash and quotes used to be refused too, because the L1 fan-out read `sessions.txt` through `xargs -I {}`, which deleted a backslash and died on a quote (#54).

### Decision

`scan_one_adapter` (called from `scan_roots`) skips a path containing `$NL` or `$TAB`, counts it in `REJECTED_PATHS` (run-stats `sessions_rejected_path`) and logs it with `printf '%q'`. `dispatch_l1` now hands each worker its path NUL-delimited and the worker writes JSON through `jq`, so backslashes and quotes are carried like any other character and are not refused.

### Consequences

Do not widen the reject set without a consumer that actually breaks on the character.

## the fan-out uses NUL transport, and a session path containing a newline is rejected rather than transported

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter`, `REJECTED_PATHS`, the `xargs -0` fan-out)

### Context
`sessions.txt` is line-delimited and stays that way: the hash assignments in `l1_missing_count()` and `dispatch_l1()` key each artifact by the sha1 of the whole line, `oversized-gate.sh` recomputes that same hash from the file, and every archived findings dir depends on the shape. A path with a newline is written as two lines and the runner then invents a session that does not exist.

### Decision
Enumeration is NUL-delimited (`read -r -d ''` over the staged adapter output) and the fan-out hands each worker its path NUL-delimited (`tr '\n' '\0' < sessions.txt | xargs -0 -n 1`), so a path with a space, a glob character, a backslash or a quote reaches the worker intact. NUL transport does not save a newline path, so such a path is rejected (counted in `REJECTED_PATHS`) before either representation is built, rather than transported. A tab is rejected at the same check for a different reason (`pin-projects.tsv` and the source map are tab-separated); see `session-path-newline-tab-rejected`. The original comment says NUL transport carries a tab intact; the code beside it refuses tabs, so that sentence is not true of this check.

### Consequences
Changing `sessions.txt` away from one path per line (to carry newline paths, say) would change the sha1 each artifact is keyed by and orphan every archived findings dir. Related: docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (findings keyed by a sha1 of the session path).

## A session's project is the directory under the longest root that holds it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`session_project`)

### Context
Claude nests transcripts at several depths under one bucket (`<bucket>/<session>.jsonl`, `<bucket>/<session>/subagents/agent-*.jsonl`, `<bucket>/<session>/subagents/workflows/wf_*/agent-*.jsonl`), and a bucket can itself be named `subagents`, so no rule based on directory names finds the bucket at every depth. Roots can also nest (`/c` and `/c/projects`).

### Decision
Of the adapter's roots (`adapter_roots`), the longest one that holds the session as `root/<bucket>/<something>` (a trailing `/` on a root is ignored) wins, and the project is the first path component below it. A session under none of the adapter's roots falls back to its parent directory's name.

### Consequences
Do not replace this with a directory-name heuristic. A session under a nested root names `<bucket>`, not `projects`.

## session roots resolve SESSION_ROOTS, then an explicit PROJECTS_DIR, then root-probe, and an unasked folder is held out

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`probe_roots`, `write_unindexed_flag`, `scan_roots`, `scan_one_adapter`)

### Context
The nightly once scanned only `$HOME/.claude/projects` and silently stopped seeing the real work (132 -> 7 -> 8 -> 1 sessions/night on 2026-08-03..06). See docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, "Session roots: one dir is not the corpus" for the full decision; what the code adds:

### Decision
- Order: (1) `SESSION_ROOTS` (colon-separated, env or config), authoritative; (2) `PROJECTS_DIR`, only when the caller set it explicitly (`projects-dir-explicitness-recorded`), kept for backward compatibility; (3) neither: autodetect every `$HOME/.claude*/projects` through `root-probe.sh --consolidated`, primary first. If the probe is missing or fails, fall back to the primary dir alone rather than scanning nothing.
- The probe is asked for the DECIDED roots only: the primary plus those `root-choices.conf` says index. An unasked root is held out of the report until the user decides, because that is the point of the flag file (`write_unindexed_flag` -> `unindexed-roots.txt`) the report reads, "found a folder we're not indexing"; scanning an undecided folder would make that flag a lie. Folders the user explicitly ignored are likewise skipped. The flag file is the report surface; the unattended run never prompts.
- A last-resort default is NOT a configured root. When discovery and the probe fall back to the primary `$HOME/.claude/projects`, the cause is a fresh host with no store yet, and that has to stay a legitimate quiet night, so `SESSION_ROOTS_ARE_FALLBACK=1` marks the fallback and the all-roots-unavailable fatal (see `scan-roots-fails-loudly-not-quietly`) must not fire on it.
- SESSION_ROOTS is colon-separated, so a root path containing `:` is unrepresentable: the split already fragmented it. `scan_one_adapter` catches the symptom (a fragment that is not a directory), counts it in `ROOTS_UNAVAILABLE` and logs a WARNING naming the cause, rather than silently scanning nothing.
- A transcript reachable from two roots (one dir a symlink of another) must be triaged exactly once, and the first source to claim a path keeps it: `sort_unique_inplace` (`sort -u`) dedupes the raw worklist and the run is fatal if the dedupe itself fails; the provenance pass counts a repeated path in `DUPLICATE_PATHS` and keeps the first claim.

### Consequences
Do not make the probe scan every `~/.claude*` folder: the "unindexed root" flag would become a lie. `WORK_BUCKET` stays keyed off the primary dir (see `worker-cwd-isolated-work-bucket`).

## Session rows come from the runner's own worklist and are held in memory before any model runs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`session_rows`)

### Context
L1 and L2 both run with the Write tool and `bypassPermissions`, so every file `session_rows` reads (`sessions.txt`, `sessions-source.txt` included) is one they could rewrite before the pins are applied. Outside the slim case a findings `session_path` is whatever the L1 model wrote, so reading it would let a transcript name another project's session and authorize memory there.

### Decision
`session_rows` emits one `hash<TAB>project<TAB>cwd` row per session in `sessions.txt`, the runner's own worklist, and never reads a findings JSON. `run.sh` calls it before the first model call and holds the result in memory. The rows feed `pin_projects_from_rows` (the pin authorization list) and the findings project normalization, which looks each findings file up by hash. The project comes from `session_project` on the session path and source (`sessions-source.txt`, read before any model runs); a session whose project holds a tab or newline gets no row. A missing worklist returns failure, because it would otherwise read as "no projects" and refuse every pin silently.

A cwd is unusable, recorded as `?`, when the adapter cannot resolve it (usually a removed worktree), when it holds a tab or newline, or when its bucket is an encoded path (starts with `-`) that the cwd does not encode to. Slug buckets from `CLAUDE_CODE_PROJECT_DIR_NAME` (`owner-repo`) skip that encoding check, because no cwd ever encodes to a slug. An adapter cwd is always absolute, so it can never be `?` itself.

See docs/adr/0001-runner-lifecycle.md#background-where-state-lives, "Where state lives" (`pin-projects.tsv`, `session-cwds.tsv`).

### Consequences
Never source project or cwd from a findings JSON. A new consumer of project or cwd reads these in-memory rows.

## in the tab-separated session lists the adapter name comes first and the path last

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter` writing `sessions.txt.src`, `build_source_sidecar` reading it)

### Context

The adapter name is a validated safe identifier with no tab, but a session path can hold any remaining oddity. With `read -r src sp`, the last variable absorbs the whole remainder of the line. The reverse order (path first) truncated any path holding a tab and silently lost its provenance.

### Decision

`scan_one_adapter` writes `<src><TAB><path>` to `sessions.txt.src` and `build_source_sidecar` reads it with `IFS=$'\t' read -r src sp`, so the path is absorbed whole by the last variable.

### Consequences

Do not reorder the columns, and do not add a field after the path. A new field goes before the path. Tab-bearing paths are also rejected at enumeration, see `session-path-newline-tab-rejected`, so this is a second guard rather than the only one.
