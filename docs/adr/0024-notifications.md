# 0024: Notifications and banners

Status: accepted · Governs: `bin/make-notifier.sh`, `bin/notify.sh`

This record holds 7 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [notifications are branded by cloning, renaming and re-signing a copy of terminal-notifier.app](#notifications-are-branded-by-cloning-renaming-and-re-signing-a-copy-of-terminal-notifierapp)
- [the open-questions banner is posted through two senders, and the nightly run does not rely on a window opening](#the-open-questions-banner-is-posted-through-two-senders-and-the-nightly-run-does-not-rely-on-a-window-opening)
- [the banner's question count comes from the report's marker, with a tiered fallback only for reports that predate it](#the-banners-question-count-comes-from-the-reports-marker-with-a-tiered-fallback-only-for-reports-that-predate-it)
- [`AUTODREAM_NOTIFY_DRYRUN=1` stops before any banner, inbox file or opener, in every form of notify.sh](#autodream_notify_dryrun1-stops-before-any-banner-inbox-file-or-opener-in-every-form-of-notifysh)
- [notify.sh has a `--failure` and a `--warning` form for runs that cannot write, or only partly write, a report](#notifysh-has-a---failure-and-a---warning-form-for-runs-that-cannot-write-or-only-partly-write-a-report)
- [the command that opens the inbox file is a shell snippet, defaulting to plain `open`](#the-command-that-opens-the-inbox-file-is-a-shell-snippet-defaulting-to-plain-open)
- [the failure banner escapes the reason before putting it in an AppleScript string](#the-failure-banner-escapes-the-reason-before-putting-it-in-an-applescript-string)

## notifications are branded by cloning, renaming and re-signing a copy of terminal-notifier.app

Status: accepted · Date: 2026-11-21 · Code: `bin/make-notifier.sh`, `bin/notify.sh` (`BRANDED`, `NOTIFIER`)

### Context

`terminal-notifier` attributes each notification to its own app bundle: the sender name and icon come from the bundle's `Info.plist`. There is no flag that sets an arbitrary sender name. `-sender` only borrows another existing app's identity.

### Decision

- `make-notifier.sh` copies `terminal-notifier.app` into `$AUTODREAM_DIR/cc-autodream.app`, renames it in the plist (`CFBundleName`, `CFBundleIdentifier`, `CFBundleDisplayName`), ad-hoc re-signs it (editing the plist invalidates the inherited signature, and macOS will not run the bundle without one) and registers it with LaunchServices so it appears under its own name.
- It is idempotent (a no-op when the bundle exists, `--force` rebuilds) and degrades gracefully: without `terminal-notifier` there is nothing to copy, so it prints a note and exits 0.
- `notify.sh` resolves the notifier in this order: the branded bundle's binary, bootstrapped once through `make-notifier.sh` when it is missing and `terminal-notifier` is installed; then plain `terminal-notifier`; then an `osascript` banner, which is not clickable. It looks for `make-notifier.sh` next to itself (the repo and the `~/.claude/autodream` symlink both work), then in the install dir.

### Consequences

The branded bundle is a new sender to macOS, with notifications off by default until the user enables it once under System Settings > Notifications > cc-autodream (style: Alerts). See `docs/adr/0024-notifications.md#the-open-questions-banner-is-posted-through-two-senders-and-the-nightly-run-does-not-rely-on-a-window-opening` for what happened the first time.

## the open-questions banner is posted through two senders, and the nightly run does not rely on a window opening

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (the `$NOTIFIER` and `osascript` blocks)

### Context

The nightly run fires about 3am under launchd, when opening a GUI window silently fails to surface. `display notification` posts to Notification Center, which keeps the alert until it is dismissed, so it is waiting whenever the Mac is next used.

A banner's exit code does not prove it was shown (learned 2026-06). If the sender's notification permission is off, or a Focus or Do-Not-Disturb mode suppresses it, macOS drops the banner to Notification Center and the command still exits 0. The branded `cc-autodream.app` bundle is its own sender, so when the branding was introduced macOS treated it as a new app with notifications off by default. Every nightly banner vanished for a week while the log read "posted". That authorization state is TCC-protected and unreadable from a script, so the drop cannot be detected.

### Decision

- The banner is the reliable signal. The direct open of the inbox file stays as a best-effort extra on top (see `docs/adr/0024-notifications.md#the-command-that-opens-the-inbox-file-is-a-shell-snippet-defaulting-to-plain-open`).
- Both senders fire. `terminal-notifier` gives the clickable, branded banner (`-execute` opens the inbox file, `-group` collapses repeats). `osascript` posts through the system's already-trusted sender as a backup floor, so one blacked-out sender cannot black out the whole alert.
- The `osascript` backup is silent (no sound) so two landing banners do not chime twice. `AUTODREAM_NOTIFY_OSA_BACKUP=0` suppresses the backup. With no `terminal-notifier`, `osascript` is the primary sender and carries the sound.
- Posting is best-effort: a notification failure never breaks the run.

### Consequences

For click-to-open the cc-autodream sender's style must be "Alerts" (not "Banners", which auto-dismiss) in System Settings > Notifications, and it must be allowed through any Focus. Do not collapse the two senders into one on the grounds that a posted banner means a shown banner.

## the banner's question count comes from the report's marker, with a tiered fallback only for reports that predate it

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (`MARKER`, `COUNT`, `count_matching`)

### Context

PROMPT.md requires L2 to close the Open questions section with `<!-- autodream:open-questions=N -->`, where N is the count that survived its triviality gate. `review.sh` reads the same marker to decide whether the morning triage session is worth opening. The marker is the only source that knows which candidates L2 considered and dropped. Counting list markers and hoping they line up with questions does not work: measured against the 14 reports on disk when this was written, the old single-pass `grep` disagreed with the marker on 4 of the 9 reports that carry one. The 2026-07-24 report had 1 real question and was counted as 6, because the "Other findings dropped by the gate" bullets below it each scored. A banner claiming six questions over one teaches people to stop reading banners.

L2 has emitted the section as a numbered list, as bullets under bold subheadings, as plain bullets and as bare prose. Counting every format at once double-counts the sub-bullets under an item.

### Decision

- The marker wins when present.
- Without one, take the first format tier that matches: numbered items, then bold titles, then bullets, then 1 for bare prose.
- A first line starting with "None" is zero and stays silent. Without that case the prose tier turns every quiet night into a false pop.
- The section's boundaries come from `report_questions` in `report-format.sh` (the questions block sentinels, the markdown heading only as the legacy fallback), so this script and `review.sh` cannot disagree about where the section stops.

### Consequences

docs/adr/0022-review-and-triage.md#background-the-triage-prompt-is-questions-only-and-that-is-load-bearing, "The triage prompt is questions-only", explains the sentinels. Changing the marker format in PROMPT.md means changing `report_marker_count` and this fallback together, and `tests/review-skip.sh` covers the marker contract.

## `AUTODREAM_NOTIFY_DRYRUN=1` stops before any banner, inbox file or opener, in every form of notify.sh

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (the two `AUTODREAM_NOTIFY_DRYRUN` checks)

### Context

Counting the questions of a report is pure computation, and people legitimately want to replay the counter over a pile of old reports. That is how the marker logic was validated. Doing it with the real script posts a real banner per report. On 2026-07-28 a verification sweep fired banners for reports up to eleven days old, and because the sweep had pointed the open command at a stub, clicking them did nothing.

Pointing `AUTODREAM_DIR` at a temp dir is not enough to make a sweep safe. The branded bundle is absent there, so the notifier resolution falls through to a system `terminal-notifier` and posts for real.

The failure and warning branch used to return before reaching the dry-run check. Its documented promise is that nothing is written, posted or opened, and anyone exercising that branch with the variable set got a live banner and a stray inbox file.

### Decision

`AUTODREAM_NOTIFY_DRYRUN=1` reports the question count (or the banner it would post) and exits 0. It writes no inbox file, posts no banner and opens nothing. The check sits after the count in the report form and before the notifier in the failure and warning form. The inbox directory is still created, and the branded notifier bundle may still be built, because both run above either check.

### Consequences

Anything that posts, opens or writes an inbox file belongs below the dry-run check in both forms. The inbox directory and the notifier bundle are the two things created above it. `tests/run-all.sh` exercises the dry-run output.

## notify.sh has a `--failure` and a `--warning` form for runs that cannot write, or only partly write, a report

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (the `FAILURE_MODE` branch)

### Context

A run that dies never writes a report. Until the failure form existed, a failed night was completely silent: no report, no banner, and nothing in `run-stats.txt` for a later run to read. For a persistent cause (a lost exec bit, a dependency off the launchd PATH) no later run ever succeeds to read it.

A run can also carry on and still write its report while having lost a part of its input that the operator should hear about now, not in tomorrow's report. The example is every upstream changelog source failing.

### Decision

- `notify.sh --failure <date> <reason>` reuses the notifier resolved above it and stops before everything that reads a report. It posts the banner and writes `<date>-FAILED.txt` to the inbox.
- `notify.sh --warning <date> <reason> [<key>]` takes the same path, labelled WARNING, and writes no `<date>-FAILED.txt`, because the run did not fail.
- A key gives the warning its own notification group (`autodream-warn-<key>-<date>`), so two warnings for one date do not replace each other. Without a key every warning shares one group.
- Both forms always exit 0: a notification that cannot be posted must not become a second failure on top of the first.

### Consequences

docs/adr/0014-changelog-watch.md#background-upstream-changelog-window ("A failure quotes git, and a total failure posts a banner" and the remote-sync reporting) names the callers. A new caller that wants its banner to coexist with another for the same date needs its own key. The dry-run contract applies to both forms (`docs/adr/0024-notifications.md#autodream_notify_dryrun1-stops-before-any-banner-inbox-file-or-opener-in-every-form-of-notifysh`).

## the command that opens the inbox file is a shell snippet, defaulting to plain `open`

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (`OPEN_CMD`, the final `sh -c`, the inbox heredoc)

### Context

The tool ships with a LICENSE and an install script, so the out-of-the-box path cannot assume one particular editor is installed. An editor that needs flags ("code -g", "open -a Obsidian") should work without a wrapper script. `SUBL` was the earlier knob, and setups that predate `AUTODREAM_OPEN` must keep working untouched.

The inbox file is `.md` and the default opener hands it to a markdown app, so a `#`-prefixed comment block at the top reads fine in a plain-text editor but renders as a stack of H1s with stray `#` lines.

### Decision

- `OPEN_CMD` is `${AUTODREAM_OPEN:-${SUBL:-open}}`. `SUBL` is a deprecated alias that is still honored. The default `open` hands the file to whatever the Mac already opens `.md` with.
- It runs through `sh -c "$OPEN_CMD \"\$1\""` with the file passed as a positional argument. `sh -c` word-splits a multi-word command while the path stays one argument whatever it contains. The banner's `-execute` string uses the same command.
- The inbox file's header is real markdown: one title, plain lines, a rule.

### Consequences

Do not quote `$OPEN_CMD` as a single word, and do not interpolate the path into the `sh -c` string. A failed open is reported and never fails the run.

## the failure banner escapes the reason before putting it in an AppleScript string

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (`osa_reason`)

### Context

A failure reason that contains a `"` made `osascript` fail with a syntax error. Several reasons do contain one, since they quote paths and adapter lists. The failure branch drops `osascript`'s stderr, so the one surface a dead run has failed silently on exactly those runs.

### Decision

The reason is passed through `sed 's/\\/\\\\/g; s/"/\\"/g'` (backslashes first, then quotes) before it is interpolated into the `display notification` string literal.

### Consequences

Any new text interpolated into that string needs the same escape, because the stderr is discarded and a bad string shows up only as a missing banner. The `terminal-notifier` path takes the message as an argument and needs no escape.
