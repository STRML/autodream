# 0020: Open questions that never get answered

Status: accepted · Governs: `bin/question-streaks.sh`, `bin/lib-flock.sh`, `bin/session-window.sh`, `bin/run.sh`

This record holds 9 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Open questions that never get answered](#background-open-questions-that-never-get-answered)
- [the banner runs osascript with fd 9 closed and escapes the message for AppleScript](#the-banner-runs-osascript-with-fd-9-closed-and-escapes-the-message-for-applescript)
- [`clear` validates its key, takes the update lock first, and fails when it cannot forget](#clear-validates-its-key-takes-the-update-lock-first-and-fails-when-it-cannot-forget)
- [the state lock is a kernel flock, and failing to take it skips the update](#the-state-lock-is-a-kernel-flock-and-failing-to-take-it-skips-the-update)
- [the store and sibling helpers resolve through the script's own link, with the link target as fallback](#the-store-and-sibling-helpers-resolve-through-the-scripts-own-link-with-the-link-target-as-fallback)
- [the streak board and its watermark are one file written by one rename, and reruns hold counts](#the-streak-board-and-its-watermark-are-one-file-written-by-one-rename-and-reruns-hold-counts)
- [a question is its exact bolded title, and a report whose parsed count disagrees with its marker touches no state](#a-question-is-its-exact-bolded-title-and-a-report-whose-parsed-count-disagrees-with-its-marker-touches-no-state)
- [`update` always exits 0, and a broken precondition says so loudly instead of failing the pipeline](#update-always-exits-0-and-a-broken-precondition-says-so-loudly-instead-of-failing-the-pipeline)
- [the question-streak update runs first after a complete report, ahead of pins and notify](#the-question-streak-update-runs-first-after-a-complete-report-ahead-of-pins-and-notify)

## Background: Open questions that never get answered

This section was moved here from the former CLAUDE.md. Its original title: "Open questions that never get answered".

The nightly asks; nothing makes it louder when the asking stops working. Between
2026-09-05 and 09-14 the X bookmarks walk was broken, every report said
`x_queryid_source: failed`, and the Open questions section asked "Fix the X bookmarks
walker, or turn the feature off?" six times. Ten nights, six asks, one banner a night that
looked exactly like the night before. Nothing moved until the user noticed the *other*
install's reports had gone quiet.

Detection was never the problem. **A signal that repeats at constant volume is a signal you
learn to skim.**

`bin/question-streaks.sh` counts the repeats and makes the Nth ask look different from the
first. `run.sh` calls it first after a complete report, ahead of the pins and `notify.sh`, so a hung
`AUTODREAM_OPEN` or store cannot skip it (issue #77). The normal banner still goes out every
night and a second, differently-worded one fires only for questions that have gone stale.
Escalations also land in `findings/<date>/question-escalations.txt`.

Four decisions in it are load-bearing:

- **A question is keyed by its bolded title, exactly.** Verified against five consecutive
  reports (2026-09-10..14): the body prose is rewritten nightly, but the title is
  BYTE-identical across all of them. So no fuzzy scoring is needed, and heavier
  normalization would risk collapsing two genuinely different questions onto one key and
  silently merging their streaks.
- **The count is mechanical, not the model's.** L2 already writes "Sixth ask" into its own
  prose, but that is the model counting its own history out of context — exactly the kind
  of number that drifts. This one is derived from the reports on disk.
- **A streak counts consecutive REPORTS, not calendar days.** A night that produced no
  report must not reset one; surviving the failing nights is the entire point. A question
  absent from a report that *was* produced is treated as resolved and forgotten, so nothing
  has to be cleared by hand.
- **A marker promising questions while none parse is a warning, not a zero.** If PROMPT.md
  ever stops emitting bold titles, the quiet failure would freeze every streak at its last
  value and the escalation would never fire again — the same class of bug as a broken
  sidecar reading as a real measurement. A report with no marker at all is incomplete and
  is refused too: a truncated L2 report parses as zero questions and would clear the board.

Details from the Codex reviews of omp-autodream PR #25, ported here in #71, each with a test:

- **The store is the install's.** A bare run of the helper (`status`, `clear`) resolves
  its install dir from its own symlink when that dir carries a `config` or
  `l1-no-advisor.yml`, and `run.sh` passes `AUTODREAM_DIR` at both call sites.
- **One file holds the board and its watermark.** The newest counted date is the first
  line of `question-streaks.tsv` (`#last<TAB>YYYY-MM-DD`), so a question-free report
  leaves that line and an older rebuild is still refused. Every write is a temp file in
  the same directory and one rename, so a failure at any step leaves the old file whole.
  The watermark first lived in a second file, and three Codex rounds in a row found a way
  for the two files to disagree that let history back in. A state file that exists but
  cannot be read refuses the update, because reading it as empty restarts every streak.
  `clear` keeps the watermark.
- **`clear` takes the same lock as `update`**, before its "nothing to clear" check, and
  fails loudly when it cannot. It also fails on a key no streak carries (omp-autodream
  #32): printing "cleared" for a mistyped key left the real streak escalating.
- **The state directory exists before the lock.** The lock lives beside the state, so on a
  new state path the lock could never be taken.

Threshold is `AUTODREAM_QUESTION_ESCALATE_AT` (default 3). `question-streaks.sh status`
prints the current streaks; `clear all|<key>` forgets one after you have acted on it.

`/debate:run tight` found seven defects in the first draft, all in the new code and all
after the suite was green. Four are why the file reads as it does now:

- **Reruns forged escalations.** `AUTODREAM_FORCE=1 run.sh <today>` re-counted a report
  already counted, and rebuilding an OLDER date rewrote live state with history. Updates
  are now idempotent per report date and refuse to go backwards.
- **A zero-question report never cleared anything**, because `run.sh` returns early on the
  nothing-was-triaged path, before the usual call site. That path calls the updater too
  now — otherwise a question reappearing two reports later was called consecutive.
- **Concurrency could lose an increment.** The scheduled nightly and `autodream-now.sh`
  carry different launchd labels, so one-instance-per-label does not keep them apart. The
  read-modify-write takes an `flock(2)` on `$STATE.flock` (`bin/lib-flock.sh`, the lock `threads.sh`
  uses), and SKIPS rather than blocks when it cannot get it. It was a mkdir lock that contenders
  reclaimed by age and then by pid, and a shell cannot make "judge the holder gone, then take its
  lock" atomic: a holder that stalled past 120 s lost the lock to a second writer and its release
  removed the second writer's (#192), and four gate rounds on the fix each found another interleaving
  (`docs/plans/2026-11-21-fix_question-streaks-lock-owner-redesign.md`). The kernel drops an flock when
  its holder ends, so nothing is judged, reclaimed or put back, and a live holder keeps it however long
  it takes. Distinct outcomes: held (skip, exit 0 for `update`, exit 1 for `clear`), cannot lock and no
  python3 (permanent: `update` skips with the reason and posts a banner, because skipping every night
  looks like a quiet week), a double acquire in one process (refused: a second `exec 9>>` would drop the
  first lock). An older version's mkdir lock at `$STATE.lock` is honored while younger than 300 s, checked
  inside the same deadline loop, and never removed (one whose state cannot be read, such as a symlink loop, is
  cannot-lock: permanent, banner): the one age judgment left. Children that can outlive
  the holder run with fd 9 closed (the banner's `osascript` does), or they would keep the lock alive after
  a kill.
- **A parser breakage only wrote to the run log.** That is this feature's own failure mode
  one level up: every streak silently frozen, no escalation ever again, indistinguishable
  from a quiet week. A mismatch now posts a banner saying the escalation is down.

Replayed against the real 09-10..14 reports it escalates on **09-12** — two nights before
the user actually caught the bookmarks failure.

## the banner runs osascript with fd 9 closed and escapes the message for AppleScript

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`show_notification`, `post_banner`)

### Context

The banner is the one surface that looks different from last night's, so it is best-effort and never fatal, the same posture as `notify.sh`.

### Decision

- `osascript` runs with fd 9 closed. A child that outlives this script would otherwise keep the flock alive after the script is killed.
- Backslashes and double quotes in the message are escaped. Otherwise a quote in a question title ends the AppleScript string and the whole `-e` becomes a syntax error, which `osascript` reports on a stderr this drops, so the banner would vanish for exactly the questions with punctuation in them.
- `AUTODREAM_NOTIFY_DRYRUN=1` prints "dry run, no banner" before anything else, including the `osascript` lookup.

### Consequences

Any new child process started while the lock is held needs `9>&-` too.

## `clear` validates its key, takes the update lock first, and fails when it cannot forget

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`cmd_clear`)

### Context

An operator told a streak is forgotten must not find it still escalating tomorrow. Each rule below closed a way that happened or nearly did.

### Decision

- A key is exactly what `key_of` prints: 12 lowercase hex characters, refused otherwise before awk sees it. awk would compare numeric-looking keys as numbers (`89709551468` matching `089709551468`) and `awk -v` decodes backslash escapes (Codex reviews of 5f7ddaa and b67c2f1). The key comparisons in `streak_field` and `cmd_clear` use `$1"" == k""` for the same reason.
- `clear` takes the same lock as `update`, before its empty check. An update that already read the old state would write it back and the cleared streak would return (Codex review of 232c94c), and an update holding the lock may be about to write the first streak onto an empty board (Codex review of 4eea84d). With no state directory there is nothing to lock or clear, so that stays a no-op.
- A key no streak carries is a failure (#32), not a no-op. Printing "cleared" for a mistyped key left the real streak escalating.
- It keeps the watermark.

### Consequences

`update` exits 0 whatever happens; `clear` is the command that reports failure. Do not loosen the key pattern without keeping the string comparisons.

## the state lock is a kernel flock, and failing to take it skips the update

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`take_lock`, `drop_lock`), `bin/lib-flock.sh`

### Context

`STATE` is one file per install. The scheduled nightly and an `autodream-now.sh` run carry different launchd labels, so launchd's one-instance-per-label rule does not keep them apart. Two overlapping read-modify-write runs would lose the first one's increment.

The lock was a `mkdir` lock that contenders reclaimed by age and then by pid. A shell cannot make "judge the holder gone, then take its lock" atomic, and four review rounds on #192 each found another interleaving (`docs/plans/2026-11-21-fix_question-streaks-lock-owner-redesign.md`).

### Decision

- The lock is `flock(2)` on `$STATE.flock` through `lib-flock.sh`, the mechanism `threads.sh` uses. The kernel drops it when its holder ends, so nothing is judged, reclaimed or put back.
- Failing to take it skips the update. A missed increment costs one night of escalation latency, while a helper that hangs holds up the pipeline behind it.
- An older version's `$STATE.lock` directory is honored while younger than 300 seconds and never removed.

### Consequences

Children that can outlive the holder run with fd 9 closed (see `docs/adr/0020-question-streaks.md#the-banner-runs-osascript-with-fd-9-closed-and-escapes-the-message-for-applescript`), or they keep the lock alive after the holder is killed. docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, "Open questions that never get answered", lists the distinct outcomes (held, cannot lock, no python3, double acquire).

## the store and sibling helpers resolve through the script's own link, with the link target as fallback

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`sibling`, `resolve_install_dir`), `bin/session-window.sh`

### Context

`install.sh` links each script into the install's own `AUTODREAM_DIR`. A merge updates the links at once, but a newly added helper only gets its link when `install.sh` runs again.

A bare invocation (`status`, `clear`, or the early empty-night path in `run.sh`) has no `AUTODREAM_DIR`, and the legacy `~/.claude/autodream` would read the wrong store on an install elsewhere (Codex review of 232c94c).

### Decision

- `sibling` looks beside the invoked path, then beside the target of its symlink. Same rule as `docs/adr/0022-review-and-triage.md#reviewsh-looks-for-a-sibling-helper-beside-itself-then-beside-its-symlink-target-and-defaults-reports-to-the-install-dirs-sibling`; `session-window.sh` applies it to `portable.sh`.
- The store is found by `resolve_install_dir` (`lib-install-dir.sh`): the install the script was linked into when that directory carries a `config` or `l1-no-advisor.yml`, with the legacy directory as the last resort. `run.sh` passes `AUTODREAM_DIR` at its call sites.

### Consequences

`tests/install-dir.sh` runs `question-streaks.sh` from a link directory with no helper links. `tests/report-format.sh` requires the `. "$_rf"` source lines to keep that shape.

## the streak board and its watermark are one file written by one rename, and reruns hold counts

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`write_state`, `newest_of`, `cmd_update`)

### Context

The newest counted report date used to live in a second file. Three review rounds in a row (Codex on 232c94c, 4eea84d and 600e6dd) each found a write order, or a failure between the two files, that let an older rebuild recreate a streak.

`AUTODREAM_FORCE=1 run.sh <today>` rebuilds a report already counted, and rebuilding an older date would rewrite live state with history.

### Decision

- The watermark is the first line of the state file, `#last<TAB>YYYY-MM-DD`, above the rows. A question-free report leaves only that line.
- Every write is a temp file in the state directory and one rename, so a failed temp creation, a full disk, a failed rename or a kill between write and rename leaves the old file whole (a kill can strand a `STATE.XXXXXX` temp).
- A date older than the watermark is refused. The same date holds each existing count and refreshes membership, and a question new on that rebuild starts at 1. A rebuild re-posts no banner but still writes `question-escalations.txt`.
- A state file that exists but cannot be read is not an empty board: reading it as empty would drop the watermark and restart every streak, so `update` refuses.

### Consequences

State that must change together goes in one file. When a fix starts choosing which of two files to write first, merge them (docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent, "Bash traps this feature hit"). `clear` keeps the watermark, so an older rebuild after a clear is still history.

## a question is its exact bolded title, and a report whose parsed count disagrees with its marker touches no state

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`key_of`, `titles_of`, `cmd_update`)

### Context

The X bookmarks walk broke on 2026-09-05. Every report to 09-14 said `x_queryid_source: failed`, and the Open questions section asked "Fix the X bookmarks walker, or turn the feature off?" six times, ten nights, with one banner a night that looked like every other. A signal that repeats at constant volume is skimmed. L2 writes "Sixth ask" into its prose, but that is the model counting its own history, and it drifts.

Across five consecutive reports (2026-09-10..14) the body prose was rewritten nightly while the bolded title was byte-identical.

### Decision

- The key is the first 12 hex characters of the sha1 of the title, lowercased with whitespace collapsed and nothing else normalized. Heavier normalization could merge two different questions into one streak, silently.
- `titles_of` reads only the questions block (`report_questions`, the sentinel-bounded section shared with `review.sh` and `notify.sh`) and only numbered items (`1.` or `1)`) with a bold lead-in. PROMPT.md mandates the numbering and `review.sh` walks questions in order, so a bulleted question is broken already. A pattern loose enough to match anything would match sub-bullets. The bold lead-in is required for the same reason; when it was optional, a plain question parsed as nothing while its siblings parsed.
- A streak counts consecutive reports, not calendar days, so a night with no report does not reset one. A question missing from a report that was produced is resolved, including a report with zero questions (which is why `run.sh` calls this on the nothing-triaged path too).
- The report's `autodream:open-questions=N` marker is the report's own count. No marker means the report is incomplete, which is stricter than `run.sh`'s `report_complete`: a truncated L2 report parses as zero questions, and counting it would clear every streak and advance the watermark. A marker that disagrees with the parsed count means the title format moved. State is left alone and a banner says escalation is down.

### Consequences

Freezing every streak at its last value is the failure that would switch the feature off with no sign, the same class as `overlap_measured` and `stats_sidecars_unparseable`, which is why the mismatch is a banner and not only a log line. docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, "Open questions that never get answered", states the same rules.

## `update` always exits 0, and a broken precondition says so loudly instead of failing the pipeline

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`cmd_update`, `take_lock`, `lock_message`)

### Context

This runs at the end of the nightly pipeline. A bookkeeping helper must not be the thing that costs a night its report. But a helper that skips silently every night freezes every streak and reads as a quiet week.

### Decision

- `update` exits 0 on every path. A missing `report-format.sh` or `lib-flock.sh` prints why to stderr and exits 0 for `update` (1 for other commands): without the lib every report reads as "no marker" and streaks would freeze behind a message about the report.
- A held lock is routine (another run is mid-update) and skips quietly. The permanent refusals (cannot open or lock the file, no python3, a legacy lock path that cannot be read) post a banner through `show_notification` as well.
- The state directory is created before the lock is taken, since the lock lives beside the state; on a new state path the first update otherwise read as a held lock and never created the state (Codex review of b72f0e4).
- One `trap ... RETURN` releases the lock and removes the scratch directory. A second `trap RETURN` in the same function replaces the first and leaks whichever cleanup registered earlier.
- `AUTODREAM_QUESTION_LOCK_WAIT` falls back to 15 on a non-number or more than four digits (an effectively endless wait); `10#` keeps `08` decimal.

### Consequences

`clear` is the exception and returns 1 on failure (see `docs/adr/0020-question-streaks.md#clear-validates-its-key-takes-the-update-lock-first-and-fails-when-it-cannot-forget`). The lock design is `docs/adr/0020-question-streaks.md#the-state-lock-is-a-kernel-flock-and-failing-to-take-it-skips-the-update`.

## the question-streak update runs first after a complete report, ahead of pins and notify

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: the `question-streaks.sh update` call)

### Context
It only reads the report and writes one local file, while the steps after it call out (`notify.sh` runs the user's `AUTODREAM_OPEN` synchronously, `apply-pins.sh` calls the Mnemopi store). If either hangs, a kill there leaves a report on disk that the next trigger skips, and a streak update placed after them would never run for it, so a stale question would miss its escalation (https://github.com/STRML/autodream/issues/77). The failure it answers is not a missing signal but an unchanging one: the X bookmarks question was asked six times across ten failing nights, each night's banner identical to the last, and nothing moved until the user noticed by accident.

### Decision
The update runs whenever the report file exists after the L2 phase (the script itself refuses a marker-less report), before the pins and `notify.sh`; a non-zero exit logs and the run continues (never fatal; it is bookkeeping). See docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, "Open questions that never get answered".

### Consequences
Do not move it below `notify.sh` or `apply-pins.sh`.
