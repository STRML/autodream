# 0017: Operator notes and the vault inbox

Status: accepted · Governs: `bin/vault-notes.sh`, `bin/run.sh`

This record holds 13 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Operator notes: one file for the prompt, many surfaces for the human](#background-operator-notes-one-file-for-the-prompt-many-surfaces-for-the-human)
- [Background: What the consume gate actually has to check (PR #37 review)](#background-what-the-consume-gate-actually-has-to-check-pr-37-review)
- [Background: Bash traps this feature hit, all of them silent](#background-bash-traps-this-feature-hit-all-of-them-silent)
- [note expiry is judged against the report date, and expired notes are still archived](#note-expiry-is-judged-against-the-report-date-and-expired-notes-are-still-archived)
- [counts use `grep -c ... || true`, never `|| echo 0`](#counts-use-grep--c---true-never--echo-0)
- [iCloud-evicted notes are materialized with two tools, waited for under a cap, and reported when still missing](#icloud-evicted-notes-are-materialized-with-two-tools-waited-for-under-a-cap-and-reported-when-still-missing)
- [vault-notes resolves its install dir and sources the config the way run.sh does](#vault-notes-resolves-its-install-dir-and-sources-the-config-the-way-runsh-does)
- [archive moves only the inbox files that collect recorded in its manifest](#archive-moves-only-the-inbox-files-that-collect-recorded-in-its-manifest)
- [every capture surface is merged into one operator-notes.md, and the prompt reads only that](#every-capture-surface-is-merged-into-one-operator-notesmd-and-the-prompt-reads-only-that)
- [status counts tag lines with grep so it works without jq](#status-counts-tag-lines-with-grep-so-it-works-without-jq)
- [archive and mark-read consume input only after a complete report and only for the normal nightly date](#archive-and-mark-read-consume-input-only-after-a-complete-report-and-only-for-the-normal-nightly-date)
- [A question-free report from an empty night still updates the question streaks](#a-question-free-report-from-an-empty-night-still-updates-the-question-streaks)
- [operator notes reach L2 through one merged file, collected best-effort](#operator-notes-reach-l2-through-one-merged-file-collected-best-effort)

## Background: Operator notes: one file for the prompt, many surfaces for the human

This section was moved here from the former CLAUDE.md. Its original title: "Operator notes: one file for the prompt, many surfaces for the human".

`PROMPT.md` reads exactly one notes path, `findings/<date>/operator-notes.md`, and `bin/vault-notes.sh` writes it by merging every capture surface. Adding a surface is a change to that script and never to the prompt. Today there are two:

- `~/.claude/autodream/notes.md`, appended by `autodream-note.sh`. Terminal-only, unchanged, still the right thing for an agent leaving itself a note mid-session.
- `$AUTODREAM_VAULT_DIR/inbox/*.md`, one file per note. This is the surface that gets used away from the keyboard — Obsidian mobile, Shortcuts, a share sheet, anything that writes a file into a synced folder. Optional YAML frontmatter `expires: YYYY-MM-DD`; expired notes are dropped at collect time so the prompt keeps exactly one expiry format to parse (the `- [added] (expires DATE)` lines).

Consumed inbox files move to `processed/<date>/` and the report is copied to `reports/<date>.md` for phone reading. Both steps are gated on a **non-empty** report, deliberately stricter than the `-f` check that encloses them: archiving a note the aggregator never read destroys the only copy, silently and unrecoverably. The manifest exists for the same reason — `collect` records which files it read and `archive` moves only those, so a note written during the ten minutes a run takes is not swallowed unread.

The vault lives in iCloud, which evicts file contents under storage pressure and leaves a `.<name>.icloud` placeholder. 03:15 is exactly when nothing has touched the vault for hours, so `materialize()` calls `brctl download` and waits for the placeholders to clear (`AUTODREAM_ICLOUD_WAIT`, default 30s). A note still dataless after the wait is written into `operator-notes.md` as `UNREADABLE` and left in the inbox rather than skipped — a note the user wrote and we could not read is worth saying out loud.

## Background: What the consume gate actually has to check (PR #37 review)

This section was moved here from the former CLAUDE.md. Its original title: "What the consume gate actually has to check (PR #37 review)".

"Only consume after a real report" turned out to need three conditions, not one. A review found the first version satisfied by things that are not a real report at all:

- **`-s "$REPORT_PATH"` is not proof this run wrote it.** Under `AUTODREAM_FORCE=1` the idempotency guard is bypassed while the *previous* run's report is still on disk, and nothing ever truncates that path. A sleep-killed L2 then left the old file standing, which both broke the retry loop out after one attempt and let the consume step archive an unread note. The fix is to move an existing report aside *before* the L2 loop, so the path being non-empty means what the code always assumed it meant. The copy is kept and logged on failure, discarded on success so `--force` doesn't litter `.stale-<epoch>` files forever.
- **The date matters.** Both collectors are date-agnostic — they read the *current* inbox and the *currently* unread bookmarks regardless of which date's findings dir they write into. Reprocessing an old date therefore consumed today's pending input. Consuming is now gated on `TARGET_DATE` matching the date a normal nightly run would process. `AUTODREAM_CONSUME_DATE` overrides that authoritatively, because the suite pins a fixed historical date and without the override every archive assertion would pass while testing nothing.
- **Publishing is not consuming.** Copying the report into the vault stays outside the date gate; only `archive` and `mark-read` destroy the user's only copy.
- **A failed move-aside must disarm consuming, not warn.** The first version logged a warning and carried on when the `mv` failed, which puts you back in exactly the state the move exists to prevent: a stale report at `$REPORT_PATH` that a failed L2 lets both the retry loop and the consume gate mistake for fresh output. `CONSUME_SAFE=0` turns the whole consume phase off for that run. A guard whose failure path continues is not a guard.

The copies those moves leave behind are retired by one block that sits *outside* the `-f "$REPORT_PATH"` test, and it has to (#40). A successful `.partial-*` move deletes that path, so anything nested under that test was skipped in exactly the outcome where the user most needs to be told where their last good report went. A complete report supersedes every `.partial-*` for its date, including ones from earlier nights, since a partial is a prefix of a report that now exists in full.

Credentials never go in `argv`. `-H "cookie: auth_token=…"` puts a full account-takeover token in the process list for the life of the request, readable by anything running as the same user, and the nightly run makes several of these unattended. `x-bookmarks.sh` writes them to a 0600 `curl --config` file inside the per-run `$TMP` that the EXIT trap removes.

`materialize()` calls **both** `brctl download` and `fileproviderctl materialize`. `brctl` predates the FileProvider migration and on current macOS often succeeds while doing nothing, which would silently reduce the iCloud wait to a passive timeout dressed up as a fetch.

## Background: Bash traps this feature hit, all of them silent

This section was moved here from the former CLAUDE.md. Its original title: "Bash traps this feature hit, all of them silent".

Each of these passed a smoke test and failed in a way that produced no error:

- **`$(grep -c ... || echo 0)` yields `"0\n0"`.** `grep -c` prints `0` *and* exits 1 on no match, so the fallback fires too. The arithmetic that follows then dies under `set -e`. Triggered by a `notes.md` holding only its header — exactly what the user is left with after deleting notes a report said were addressed.
- **A variable set inside `$(...)` never comes back.** `fail()` assigned `FAIL_REASON` from inside nested command substitutions (`qid=$(get_query_id)` → `qid=$(detect_query_id)`), so the cookie-expiry remediation text died with the subshell and the report said a fetch failed for no reason. The reason now goes to a file, which crosses the boundary.
- **An iCloud-evicted file is not a zero-byte file.** macOS replaces it outright with a dot-prefixed `.<name>.icloud` placeholder, so a `-name '*.md'` walk matches *nothing* and the unreadable-note branch was unreachable for the only case it existed for. Placeholders get their own pass and are never manifested, so the note stays in the inbox to retry.
- **Sourcing a user-edited config under `set -u` kills the shell.** Not the source — the shell, so `|| echo WARNING` cannot fire. `run.sh` now probes the config in a throwaway subshell purely to capture bash's own error naming the bad variable, then sources for real with nounset off. Both helper scripts need the same guard; fixing only `run.sh` left them dying instead.
- **`mv` across filesystems is a copy, not a rename.** State staged in `$TMPDIR` and moved onto `$STATE_DIR` was never the atomic swap its comment claimed. Stage in the destination directory and gate the `mv` on the staging copy having succeeded.
- **State that has to change together goes in one file, written with one rename.** Two files cannot be updated atomically, so every write order leaves a failure point between them. `question-streaks.sh` kept its watermark in a second file, and three Codex rounds on omp-autodream PR #25 in a row each found a new order in which the two disagreed. Moving the watermark into the state file's first line ended it (see "Open questions that never get answered"). When a fix starts choosing which of two files to write first, merge the files instead.

## note expiry is judged against the report date, and expired notes are still archived

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`report_date_of`, `note_expiry`, `collect`)

### Context

Rebuilding an old date, or a launchd catch-up running a missed night days later, would drop and archive every note whose expiry fell between that date and today. Those notes were active for the window being reported.

### Decision

- `report_date_of` takes the date from the findings dir name. A name that is not `YYYY-MM-DD` (tests, an ad-hoc dir) falls back to today. `archive_tags` uses the same function.
- A vault note with frontmatter `expires: YYYY-MM-DD` is dropped at collect time when that date is before the report date, so `PROMPT.md` keeps exactly one expiry format to reason about (the `- [date] (expires DATE)` lines in `notes.md`).
- An expired note is still written to the manifest, so it leaves the inbox. It has done its job.

### Consequences

Using `date +%F` for the comparison would drop live notes on every rebuild. The `notes.md` surface is not filtered here at all; its expiry stays in the prompt.

## counts use `grep -c ... || true`, never `|| echo 0`

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`count_matches`)

### Context

With zero matches, `grep -c` prints `0` and exits 1. A fallback `|| echo 0` then fires too, and the substitution captures the two-line string `0\n0`. The arithmetic that follows dies, and under `set -e` that took the whole `collect` down, writing no `operator-notes.md`. The input is not hypothetical: it is `notes.md` after the user deletes the notes a report said were addressed, leaving only the header `autodream-note.sh` writes. `status` printed nonsense on the same file.

### Decision

`count_matches` takes grep's stdout, ignores its status with `|| true`, and defaults an empty result (a missing file prints nothing) to `0`. `collect` and `status` both count through it.

### Consequences

Do not inline a new count as `$(grep -c ... || echo 0)`. docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent, "Bash traps this feature hit", lists this first.

`vault_subdir` has the same trap in a different shape. A function that ends on a failed `[ -n "$VAULT_DIR" ]` returns that status, and `dir=$(vault_subdir inbox)` then aborts the script under `set -euo pipefail`, which is the no-vault case and the most common one. It is written `[ -z "$VAULT_DIR" ] || printf ...` so it returns 0 on both paths; do not rewrite it as `[ -n ... ] && printf ...`.

## iCloud-evicted notes are materialized with two tools, waited for under a cap, and reported when still missing

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`materialize`, the placeholder pass in `collect`)

### Context

The vault lives in iCloud Drive. macOS evicts file contents under storage pressure and replaces the file outright with a dot-prefixed `.<name>.icloud` placeholder. launchd fires at 03:15, when nothing has touched the vault for hours and eviction has had time to happen.

### Decision

- `materialize` runs both `brctl download` and `fileproviderctl materialize`, then polls for `.*.icloud` placeholders every 2 seconds up to `AUTODREAM_ICLOUD_WAIT` (default 30). Neither tool alone is reliable. `brctl` predates the FileProvider migration (Monterey) and on a current system often succeeds while doing nothing, which would reduce the wait to a passive timeout dressed up as a fetch. A missing tool or a failure of either is not an error.
- The cap means a broken iCloud daemon costs seconds, not the run.
- An evicted note is not a zero-byte `foo.md`, so the `*.md` walk matches nothing and its UNREADABLE branch (written for zero-byte files) never fires. A note the user wrote on a phone would then show as `unreadable: 0`, which reads as "nothing was missed". Placeholders therefore get their own pass, which emits a `## note: <name> - UNREADABLE` block and counts it.
- A placeholder whose real file has also appeared is skipped, so one note is not counted twice.
- Placeholders are not manifested. The note has not been read, so it stays in the inbox for the next run to retry.

### Consequences

docs/adr/0017-operator-notes-and-vault.md#background-operator-notes-one-file-for-the-prompt-many-surfaces-for-the-human, "Operator notes", and the "Bash traps this feature hit" list record the same facts. `tests/run-all.sh` covers the placeholder case. The rule is the one `overlap_measured` follows: a degraded measurement says so and never reads as zero.

## vault-notes resolves its install dir and sources the config the way run.sh does

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (the `resolve_install_dir` call, the config-source block)

### Context

A hard-coded `$HOME/.claude/autodream` made the writer and the reader disagree whenever an install lived elsewhere. vault-notes takes `AUTODREAM_DIR` from the launchd plist, so every note landed in a file the nightly never opened, with no error and no missing-note report.

`status` is run by hand. A `status` that says "vault: not configured" about a vault the user configured is worse than no `status`.

### Decision

- The install dir comes from `resolve_install_dir`: the environment first, else the script's own directory when it carries an install marker, else the legacy default with a warning. `BASH_SOURCE` stays unresolved on purpose, because `install.sh` symlinks the scripts into `$TARGET`, so the link's directory is the install dir.
- `portable.sh` and `lib-install-dir.sh` are found next to the script first, then next to the symlink target, because a merge updates the installed links before `install.sh` links a new helper.
- The config is sourced here as well as in `run.sh`, under `set +u` (the same reason `run.sh` does it: a typo'd variable in the user-edited config would abort the script under `nounset` and cost a night's notes) with the caller's exports replayed from an `export -p` snapshot afterwards. Double-sourcing is harmless because `run.sh` has already exported these values. `run.sh` warns about the typo, and staying quiet here avoids the same complaint twice.

### Consequences

docs/adr/0001-runner-lifecycle.md#background-runsh-sources-the-config-now, "run.sh sources the config now", states the `set -a` and snapshot rules. A new variable this script reads from the config works for `status` run by hand only because of this block.

## archive moves only the inbox files that collect recorded in its manifest

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`collect`, `archive_notes`)

### Context

Inbox files move to `processed/` after a successful report, so the inbox stays a to-do list and not a growing pile. A run takes about 10 minutes. A note written in that window and archived unread would be lost without a trace, and it is the note the user cared enough to write mid-run.

### Decision

- `collect` writes `vault-notes-manifest.txt`, one path per file it read (an expired note is listed too, since it has done its job).
- `archive_notes` moves exactly the manifest's files into `processed/<date>/`. A file that is not in the manifest stays in the inbox for the next run.
- A placeholder that iCloud has not downloaded is never manifested (see `docs/adr/0017-operator-notes-and-vault.md#icloud-evicted-notes-are-materialized-with-two-tools-waited-for-under-a-cap-and-reported-when-still-missing`).

### Consequences

docs/adr/0017-operator-notes-and-vault.md#background-what-the-consume-gate-actually-has-to-check-pr-37-review, "What the consume gate actually has to check", covers when `archive` may run at all: only after a complete report written by this run, for the normal nightly date. Skipping the manifest and archiving the whole inbox is the shortcut this decision rules out.

## every capture surface is merged into one operator-notes.md, and the prompt reads only that

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`collect`)

### Context

`autodream-note.sh` appends to `$AUTODREAM_DIR/notes.md`, which works only from a terminal on this Mac. Notes worth leaving for the nightly run mostly come up away from the terminal: on a phone, mid-meeting, in bed. An Obsidian vault folder syncs to the phone and takes a note from anything that can write a file (Obsidian mobile, Shortcuts, Drafts, a share sheet).

docs/adr/0017-operator-notes-and-vault.md#background-operator-notes-one-file-for-the-prompt-many-surfaces-for-the-human, "Operator notes: one file for the prompt, many surfaces for the human", records the same design.

### Decision

- `collect` writes `findings/<date>/operator-notes.md` from every surface, and `PROMPT.md` reads that one path. A new surface is a change to this script and never to the prompt.
- The `notes.md` surface is passed through verbatim. Its `- [added] (expires DATE) text` lines are the format `PROMPT.md` already parses, and expiry filtering for them stays in the prompt.
- Every step is best-effort. A missing vault, an unreadable file or a failed move is reported in the output and never aborts the caller, because no note is worth losing a night's report over.

### Consequences

The two surfaces use different expiry mechanisms (see `docs/adr/0017-operator-notes-and-vault.md#note-expiry-is-judged-against-the-report-date-and-expired-notes-are-still-archived`). A new surface also needs a line in the file's header counts (`active`, `unreadable`, ...), since `PROMPT.md` skips the section when `active` is 0.

## status counts tag lines with grep so it works without jq

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`status`)

### Context

`status` is a quick look by hand, and it is the command a user runs when something does not work. That includes a host with no `jq`.

### Decision

`status` counts lines in the tags file and the ledger with `grep -c .`, not tags parsed by `jq`. A torn line counts here and is skipped by `collect`, so the figure can read high and never low.

### Consequences

The "tagged" figure can exceed what the next report will contain. Parsing with `jq` would give an exact number and make `status` fail where `collect` reports UNREADABLE.

## archive and mark-read consume input only after a complete report and only for the normal nightly date

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `NORMAL_TARGET_DATE`, `CONSUME_SAFE`, the `VAULT_NOTES archive`, `publish` and `XBOOKMARKS mark-read` steps)

### Context
- Gated on a complete report, deliberately stricter than the enclosing `-f` check (the original comment said "non-empty"; the code tests `report_complete`, which also requires the open-questions marker and, from the questions epoch on, the questions block): archiving a note or stamping a bookmark read after a run that produced nothing would throw away the only copy of input the user cared about, silently and unrecoverably.
- Also gated on `TARGET_DATE` being the date a normal nightly run would process (yesterday, right now, the same `pdate_yesterday` computation as the default at the top). `collect` is date-agnostic: it reads whatever is CURRENTLY in the vault inbox and CURRENTLY unread. That is right for tonight's date, but docs/adr/0023-install-and-scheduling.md#background-running--rerunning-a-date documents reprocessing an old one (`AUTODREAM_FORCE=1 run.sh 2026-05-29`), and archive/mark-read do not know the date is old: a rebuild of 2026-05-29 would archive a note written THIS morning into `processed/2026-05-29/` and stamp today's unread bookmarks read, and tonight's real run would find an empty inbox and nothing unread, so the note never reaches any report. Collection still runs unconditionally, so L2 still SEES today's notes and bookmarks as context; only the consuming side is skipped for an old-date reprocess.
- `AUTODREAM_CONSUME_DATE` overrides which date counts as normal, authoritatively and with no fallback, for the same reason `AUTODREAM_STATS_BIN` and `AUTODREAM_OVERLAP_BIN` do: the suite pins a fixed historical `TARGET_DATE`, so without an override every consume path would take the skip branch and the archive tests would pass while asserting nothing.
- Publishing is NOT consuming: it copies the report into the vault so it can be read on a phone, and a reprocessed date is as worth reading as a fresh one. It stays outside the date gate; only archive and mark-read, which destroy the user's only copy of input, are gated.

### Decision
`archive` and `mark-read` run only when `report_complete` holds, `CONSUME_SAFE` is 1 (see `stale-dream-moved-aside-before-l2-and-consume-safe`) and `TARGET_DATE` equals `NORMAL_TARGET_DATE` (`${AUTODREAM_CONSUME_DATE:-$(pdate_yesterday)}`). Each skip logs its own reason: no marker, a stale report that could not be moved aside, or an old-date reprocess. `publish` runs whenever the report is complete, before the `CONSUME_SAFE` and date checks. See docs/adr/0017-operator-notes-and-vault.md#background-what-the-consume-gate-actually-has-to-check-pr-37-review, "What the consume gate actually has to check (PR #37 review)".

### Consequences
Do not widen consuming to old dates, and do not tie `publish` to the date gate. Tests that exercise archiving must set `AUTODREAM_CONSUME_DATE`.

## A question-free report from an empty night still updates the question streaks

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `question-streaks.sh update` on the `COUNT -eq 0` path)

### Context
Without the update, the streak store would keep yesterday's questions alive across an empty night, and a question that reappeared two reports later would be called consecutive when it was not. The early return below the stub is why the call cannot live at the usual call site at the top of the report-present block. See docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, 'Open questions that never get answered' ("A zero-question report never cleared anything").

### Decision
After the stub is published, `run` calls `$AUTODREAM_DIR/question-streaks.sh update "$REPORT_PATH" "$FINDINGS_DIR"` (when executable, under `env AUTODREAM_DIR=...`), logging a non-zero return and continuing. A stub that could not be published is a fatal that returns before this call. The stub's open-questions count is zero unless a remote host's missed dates are asked as a question inside the block (`REMOTE_SHORT_QCOUNT`), so the updater sees that question and escalates it instead of reading the night as question-free.

### Consequences
- A change to the early-return path must keep this call, or streaks stop resetting on empty nights.

## operator notes reach L2 through one merged file, collected best-effort

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `VAULT_NOTES collect` step)

### Context
Every capture surface (the terminal-written `notes.md`, the vault inbox) is merged by `vault-notes.sh collect` into `operator-notes.md`, so PROMPT.md reads a single path. Adding a surface is a change to `vault-notes.sh`, never to the prompt. A broken vault must not cost the report.

### Decision
`collect` runs when `$VAULT_NOTES` is executable; failure logs `operator-note collection failed (continuing)` and the run goes on; a missing script logs and skips. See docs/adr/0017-operator-notes-and-vault.md#background-operator-notes-one-file-for-the-prompt-many-surfaces-for-the-human, "Operator notes: one file for the prompt, many surfaces for the human".

### Consequences
Do not make a capture failure fatal, and do not add a second notes path to PROMPT.md. Consuming (archive) is a separate, gated step; see `consume-gated-on-complete-dream-and-normal-date`.
