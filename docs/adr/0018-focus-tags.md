# 0018: Focus tags: marking a turn for the next run

Status: accepted · Governs: `mods/autodream-focus/hooks/register.tsx`, `mods/autodream-focus/hooks/focus-lib.ts`, `mods/autodream-focus/tests/focus.test.tsx`, `bin/vault-notes.sh`, `bin/autodream-focus.sh`, `extensions/omp/autodream-focus.ts`, `extensions/omp/focus-core.ts`, `extensions/omp/autodream-focus.test.ts`

This record holds 18 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: The focus mod (`mods/autodream-focus`): the one place the user writes into the nightly run from a transcript](#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript)
- [the focus button is a text label, absolutely placed at the row's top right, hover-only until tagged](#the-focus-button-is-a-text-label-absolutely-placed-at-the-rows-top-right-hover-only-until-tagged)
- [only a person's own user turns, and any assistant reply, get a focus button](#only-a-persons-own-user-turns-and-any-assistant-reply-get-a-focus-button)
- [the focus mod only reads tags.jsonl; every write goes through autodream-focus.sh](#the-focus-mod-only-reads-tagsjsonl-every-write-goes-through-autodream-focussh)
- [the focus mod asks the writer where tags.jsonl is, and uses its own environment only as a fallback](#the-focus-mod-asks-the-writer-where-tagsjsonl-is-and-uses-its-own-environment-only-as-a-fallback)
- [the mod hands the writer one code point past its cap, counted in code points](#the-mod-hands-the-writer-one-code-point-past-its-cap-counted-in-code-points)
- [per-tag fields are split on the unit separator, and the turn text is read on its own](#per-tag-fields-are-split-on-the-unit-separator-and-the-turn-text-is-read-on-its-own)
- [a tagged transcript path is trusted only as an absolute, readable .jsonl, and session ids are never put in a find pattern raw](#a-tagged-transcript-path-is-trusted-only-as-an-absolute-readable-jsonl-and-session-ids-are-never-put-in-a-find-pattern-raw)
- [tags are consumed by appending to a ledger, never by editing tags.jsonl](#tags-are-consumed-by-appending-to-a-ledger-never-by-editing-tagsjsonl)
- [a tag is due for the report of the local day it was made on, decided here from taggedAt](#a-tag-is-due-for-the-report-of-the-local-day-it-was-made-on-decided-here-from-taggedat)
- [a tags file that cannot be read is reported as UNREADABLE, never as "no tags"](#a-tags-file-that-cannot-be-read-is-reported-as-unreadable-never-as-no-tags)
- [one global EXIT cleanup for the scratch files, naming globals and never a function's locals](#one-global-exit-cleanup-for-the-scratch-files-naming-globals-and-never-a-functions-locals)
- [the focus writer resolves its install dir, config and helpers the way the collector does](#the-focus-writer-resolves-its-install-dir-config-and-helpers-the-way-the-collector-does)
- [`tag` takes a kernel flock through a python3 wrapper that re-runs the script](#tag-takes-a-kernel-flock-through-a-python3-wrapper-that-re-runs-the-script)
- [`last` finds the directory's newest session without a count limit and reads only a person's live turn](#last-finds-the-directorys-newest-session-without-a-count-limit-and-reads-only-a-persons-live-turn)
- [a tags file that will not read is a refusal, an add is one append, and only a take-back replaces the file](#a-tags-file-that-will-not-read-is-a-refusal-an-add-is-one-append-and-only-a-take-back-replaces-the-file)
- [a tag carries `harness` and an absolute `transcript` path](#a-tag-carries-harness-and-an-absolute-transcript-path)
- [the OMP focus extension is a command that gathers a turn and hands it to the shared writer](#the-omp-focus-extension-is-a-command-that-gathers-a-turn-and-hands-it-to-the-shared-writer)

## Background: The focus mod (`mods/autodream-focus`): the one place the user writes into the nightly run from a transcript

This section was moved here from the former CLAUDE.md. Its original title: "The focus mod (`mods/autodream-focus`): the one place the user writes into the nightly run from a transcript".

A second, opt-in mod: a `+ autodream focus` button at the top right of every prompt and reply that tags the turn for the next run to take a close look at. It is its own plugin so that `autodream-band` stays read-only, and `install.sh` deliberately does not install or load it (`claude --plugin-dir`, or add it to `CLAUDE_CODE_PLUGIN_DIRS`). Decisions that are easy to undo by accident:

- **The button is on the right, drawn `position: absolute`.** A left column cost every row two cells in a narrow split, and a row below cost a line per message. Absolute is also what makes hover-only work: `display: none` with `hover: { display: 'flex' }` reflows nothing. Tagged, it stays lit.
- **Two files, one writer each.** `bin/autodream-focus.sh` writes `$AUTODREAM_DIR/tags.jsonl` for every harness, the Claude button included: the mod runs the script (`$.process.run`) and only reads the file to light the buttons. The mod used to rewrite the file itself, and `$.fs.write` is not an atomic rename and cannot take the script's lock, so a button press and an OMP or Codex tag could overwrite each other (the gate's P0 on the first version of the OMP and Codex writer). `bin/vault-notes.sh` appends to `tags-consumed.txt`, `<id><TAB><report date><TAB><taggedAt>`. A tag is its id AND its `taggedAt` (untagging and tagging a turn again reuses the id), and the ledger rows of the report being built do not count, so a forced rebuild of a consumed date keeps its tags. Pending is the difference. A session open at 03:15 cannot race a run because neither side edits the other's file.
- **A read that fails must never lead to a write.** The script rewrites the whole file, so "could not read" treated as "empty" replaces every tag with the one being added. Only a file that does not exist is empty; one that exists and will not read makes the script refuse with `nothing was changed`, which the button shows as a toast. The mod's own read (`$.fs.read` refuses over 4 MiB, which a file that only grows reaches) says so and lights no button rather than show every turn as untagged. A rewrite hands back every line it did not understand, and the unknown fields of a line it did.
- **Three things the mod tests cannot catch, all found live.** The test engine's row is not an engine node, so (1) a wrapper `Box` with a `width` prop around `next(e)` is refused at runtime ("engine node under a Box with prop width") and the plain row is drawn, with nothing but a dim transcript line to say so; (2) a plain `Button` pads its label, so a box narrower than label plus padding truncates it to an ellipsis, hence the box is the label's length plus 5; (3) the label is text, not an icon, on purpose: the first version was an eye emoji, and with the emoji selector (U+FE0F) the engine measures it wider than Ghostty draws it and truncated it, while the bare one drew too small. Words cannot be measured wrong. When the button is missing, read the session transcript for `ui.render (UserMessage) refused:` before guessing; there is no debug log unless the session started with `--debug`.
- **The surface is `vault-notes.sh`, not the prompt.** A pending tag becomes a `## note: focus-…` block in `operator-notes.md` carrying its own instruction, the quoted turn and the transcript path, which L2 can Read. It counts toward `active:` in the header, so PROMPT.md's "skip if `active: 0`" rule needed no change. The header gains `tagged: N`.
- **Consumed by `archive`, never `collect`.** Same gates as an inbox note (a complete report, this run's own, the normal nightly date), so a failed L2 or a rebuild of an old date leaves tags pending. A tag is held for the report of the local day it was made on, and `vault-notes.sh` decides that day from the UTC `taggedAt` with BSD `date` (cutoff = the first instant after the reported day, so a DST day is 23 or 25 hours). The mod writes no day on purpose: its environment has no timezone, and a UTC date would hold back, by a night, exactly the tags made in the evening while reviewing the day. A timestamp that does not parse counts as already due, so a tag arrives late rather than never.
- **Tag text is data.** It is quoted line by line (`> `) so a turn containing `## note: …` cannot open a block of its own, and the block says the quote is content to analyze, not instructions. Assistant text can echo anything a tool fetched.
- **No jq is a missed note, not a clean zero.** The same rule as the iCloud placeholder and `overlap_measured`: `focus-tags — UNREADABLE`, counted in `unreadable:`, nothing manifested. A `tags.jsonl` that exists and will not read (permissions, a jq error) is reported the same way: `tag_pending` runs into a temp file, not a process substitution, so its exit status is seen. macOS 15 ships `jq` in `/usr/bin`, so the test builds a PATH without it.
- **`read` and tabs.** The per-tag fields are split on the unit separator, not a tab: tab is IFS whitespace, `read` collapses a run of them, and an empty `cwd` or timestamp in the middle would shift every field after it.

**OMP and Codex tag through `bin/autodream-focus.sh`, not a copy of the mod's code.** Neither can decorate a row (OMP lets an extension register commands, shortcuts and footer status, and render only its own custom messages; Codex has no UI extension, only hooks, plugins and MCP), so the OMP extension (`extensions/omp/`) is a thin `/focus` command that hands the turn it found to the script, and Codex gets `autodream-focus.sh last --harness codex` run from a second terminal. That script is the one writer for the non-Claude harnesses and it holds the invariants the mod holds, in shell, with tests in `tests/run-all.sh`: a tags file that exists and cannot be read is a refusal; lines it does not understand come back as they stood; adding a tag is one append and taking a tag back is a temp file and one rename, both under flock(2) on `tags.jsonl.lock`, which a small `python3` wrapper takes before it re-runs the script (the kernel drops the lock when the process exits or dies, so nothing can be stale; `python3` is already needed by the web dashboard, and without it the script exits 3 and says so). Three harnesses write the file, so the lock matters, and the Claude mod takes it by running this script rather than writing the file itself. `autodream-focus.sh path` prints the file the script writes, and the mod and the OMP picker ask it, so they read the file that is written even when only the install's config names it. The script reads `$AUTODREAM_DIR/config` the way the collector does (the caller's exports win), so a tags file named only there is the one both read; the mod cannot source a shell file, so it asks the script (`path`) which file that is. A copy is never built from a `{ cat; printf; } > tmp || die` group: bash ignores errexit inside a group on the left of `||` and the group's status is its last command's, so a `cat` that failed part-way was hidden by the `printf` after it and the rename replaced every tag with a partial copy (the gate's P0 on the first version). Adding a tag now needs no copy at all. A take-back compares the file's checksum again just before the rename, so a writer that takes no lock (a copy of the old mod that rewrites the file itself) makes the script refuse rather than lose that writer's tag; the one race nothing in this script can close is that old unlocked writer against a take-back. The lock used to be a directory holding its owner's pid, with a `.reclaim` claim for waiters, and every version of that had a window (an age rule let a suspended writer's lock be taken, an empty pid file read as stale, two waiters could both remove a stale claim), which is why the kernel holds it now. The transcript copy `last --harness omp` makes is removed by the EXIT trap, whichever step ends the script. The tag gains `harness` and `transcript`; `vault-notes.sh` trusts a recorded transcript only if it is an absolute path to an existing `.jsonl`, because the tags file is a plain file and L2 will Read what the note names; the script makes a relative `--transcript` or `--file` absolute when it records it, since the nightly run reads from another directory. A Codex user turn is an `item_completed` UserMessage event (older builds: an `event_msg` user_message); the `response_item` messages with role user are what Codex injects, whatever their text starts with, so `last --role user` never reads them. Turn text is cut in code points, as the writer counts it (the mod and the OMP extension hand it one character past its cap so the writer marks the cut with an ellipsis): a cut in UTF-16 units left an emoji turn under the cap with no ellipsis and half a surrogate pair. `last` reads sessions newest first with no count limit before the match, because a limit across the whole root hid a recent session of the asked directory behind other directories' newer ones. Things learned building it: an EXIT trap that names a function's local fails under `set -u` and, because it aborts before the lock is released, wedges every later tag (the cleanup is one global function); OMP's agent-directory variable is `PI_CODING_AGENT_DIR` (not the `OMP_AGENT_DIR` first guessed); and a headless OMP cannot be run from the Claude Code sandbox, because it registers a client under `~/.omp/run/daemons/`, the live daemon's state, so the extension is tested against a fake OMP API whose `exec` runs the real script and the first run in a real OMP is the check for the loader and the key. Codex was scoped by usage, not by what is possible: in the 30 days measured, 11 interactive sessions against 396 headless `codex exec` runs, and there is no Codex adapter, so Codex sessions are not triaged at all (a tag on one still reaches L2 as a note).

What is not verified: that a row's `requestId` in `ui.render` is the transcript's own `uuid` (the mod API does not promise it), which is why the note quotes the turn and names the session rather than relying on the id to locate it. The mod's tests run under Claude Code (`claude plugin validate|test mods/autodream-focus`); the `vault-notes.sh` side is `test_focus_tag_*` in `tests/run-all.sh`.

## the focus button is a text label, absolutely placed at the row's top right, hover-only until tagged

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/register.tsx` (`LABEL`, `BUTTON_WIDTH`, `withFocus`)

### Context

docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript "The focus mod" records the live findings: the engine measures an emoji with a selector wider than the terminal draws it and truncated it, a bare one drew too small, a plain `Button` pads its label so a narrower box shows an ellipsis, a `width` on a wrapper `Box` around `next(e)` is refused at runtime, and a left-hand column cost every row two cells in a narrow split.

### Decision

- The label is the words `autodream focus` with a `+` or a check mark prefix. Words cannot be measured wrong, and the check mark is one cell in every terminal.
- `BUTTON_WIDTH` is the untagged label's length plus 5: the padding a plain `Button` adds, with room to spare.
- The button's `Box` is `position="absolute"` at `top=0 right=0`, so showing it reflows nothing. Untagged it is `display: none` and `hover: { display: 'flex' }`; tagged it stays displayed, so a glance down the transcript finds what was marked.
- `beneath` (the engine's own row) is rendered unwrapped, with the button as a sibling in a column `Box`.

### Consequences

When the button is missing, search the session transcript for `ui.render (UserMessage) refused:` before guessing; the mod tests cannot catch these layout failures.

## only a person's own user turns, and any assistant reply, get a focus button

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/register.tsx` (`isTypedByPerson`, `register`)

### Context

A `UserMessage` row is also a task notification or a peer's message, which are not the person's words and not theirs to tag.

### Decision

A user row gets the button only when `props.origin.kind` is `composer` (typed here) or `bridge` (typed from the phone). Assistant rows always do. A row with no text has nothing to tag either way (`withFocus`).

### Consequences

A new origin kind that carries the person's words (another input surface) must be added to `isTypedByPerson`, or its turns can never be tagged.

## the focus mod only reads tags.jsonl; every write goes through autodream-focus.sh

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/focus-lib.ts` (`focusScript`, `readTags`), `mods/autodream-focus/hooks/register.tsx` (`load`, `press`), `mods/autodream-focus/tests/focus.test.tsx` (`world`)

### Context

Three harnesses write `tags.jsonl`. The mod once rewrote the file itself, and `$.fs.write` is not an atomic rename and cannot take the script's flock, so a button press and an OMP or Codex tag could overwrite each other. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript "The focus mod" records this, and the rule that a read that fails must never lead to a write.

### Decision

- `focusScript` finds the writer (`AUTODREAM_FOCUS_BIN`, else the install dir). `press` runs it with `tag --harness claude ...`; the writer toggles, and the mod reads its stdout (`untagged ...` or `tagged ...`) to word the toast.
- `load` reads the file only. A file that is absent is empty. One that exists and will not read (over the 4 MiB a read allows, permissions, I/O error) throws, and `refresh` toasts that no turn shows as tagged instead of showing every turn as untagged.
- `readTags` skips a line it cannot parse (torn, hand-edited, from a later version); the writer leaves such lines on disk.
- The test stand-in toggles a line by id the way the writer does, and its `fs.write` handler records and denies every write, so a test fails if the mod ever writes.

### Consequences

A new field the writer adds is ignored by the mod. Do not add an `fs.write` path here without the script's lock.

## the focus mod asks the writer where tags.jsonl is, and uses its own environment only as a fallback

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/focus-lib.ts` (`tagsFileFromEnv`), `mods/autodream-focus/hooks/register.tsx` (`tagsFilePath`)

### Context

`bin/autodream-focus.sh` reads `$AUTODREAM_DIR/config`; the mod cannot source a shell file. A tags file named only in that config would be written by the script and invisible to the mod: no button would light, and pressing one again would take back a tag that was never shown. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript "The focus mod" notes `autodream-focus.sh path` exists for this reason.

### Decision

`tagsFilePath` runs `<script> path` (5 s timeout, with the `AUTODREAM_DIR` and `AUTODREAM_TAGS_FILE` the mod can see) and uses its stdout. When the script is not installed, exits non-zero, prints nothing, or throws, it falls back to `tagsFileFromEnv`, which resolves the way `bin/vault-notes.sh` does: an exported `AUTODREAM_TAGS_FILE` wins, else `AUTODREAM_DIR` (empty counts as unset) plus `tags.jsonl`.

### Consequences

The tests cover both branches (writer answers, writer cannot answer). The writer's `path` verb is part of this mod's contract.

## the mod hands the writer one code point past its cap, counted in code points

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/focus-lib.ts` (`TEXT_CAP`, `forWriter`)

### Context

`bin/autodream-focus.sh` cuts a turn at 2,000 characters and marks the cut with an ellipsis, so `TEXT_CAP` mirrors that number. The writer only marks a cut when it sees more than the cap. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript "The focus mod" records that the writer counts code points: a cut in UTF-16 units left an emoji turn under the cap with no ellipsis and could keep half a surrogate pair.

### Decision

`forWriter` returns `TEXT_CAP + 1` code points (`Array.from`) when the text is longer, else the text unchanged.

### Consequences

If the writer's cap changes, change `TEXT_CAP` in the same commit. The test `a long turn is handed over one character past the writer's cap` pins 2,001.

## per-tag fields are split on the unit separator, and the turn text is read on its own

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (the field extraction in the tag loop of `collect`)

### Context

`read` treats tab as IFS whitespace and collapses a run of tabs. A tag with an empty `cwd` or timestamp in the middle would shift every field after it. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", lists this under "`read` and tabs".

### Decision

`jq` joins the fields with `\u001f` (control characters inside a value are replaced with spaces first) and `IFS=$'\037' read` splits them. The turn text is fetched by a second `jq` call so it cannot disturb the columns. An empty `epoch` means the tag belongs to the report being built.

### Consequences

Do not switch the separator back to tab, even though the jq-side `clean` function also strips tabs from the key.

## a tagged transcript path is trusted only as an absolute, readable .jsonl, and session ids are never put in a find pattern raw

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`tag_transcript`, the transcript lookup in `collect`)

### Context

L2 holds Read and opens what the note names. `tags.jsonl` is a plain file anyone can edit. The Claude button records no transcript, and OMP and Codex keep theirs outside the Claude roots. A relative path would be read from this run's working directory and could name a different file than the one the tag was made against.

### Decision

- A transcript the harness recorded is used only when it is an absolute path to an existing, readable `.jsonl`.
- Otherwise `tag_transcript` looks for `<session>.jsonl` (depth 2) under the roots resolved the way `run.sh` resolves them: `SESSION_ROOTS`, then `PROJECTS_DIR`, then every `~/.claude*/projects`. The tag was made under whichever config dir that session ran in.
- The session id comes from the same editable file, so anything outside `[A-Za-z0-9._-]` is refused before it reaches a `find -name` pattern.
- A transcript that cannot be found prints nothing, and the note says it was not found under the session roots.

### Consequences

`bin/autodream-focus.sh` makes `--transcript` and `--file` absolute when it records them, because the nightly run reads from another directory. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", covers that side.

## tags are consumed by appending to a ledger, never by editing tags.jsonl

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`archive_tags`)

### Context

A tag is written by a session that can be open at any hour and consumed by a run that cannot see the session. The writers of `tags.jsonl` (the mod, `bin/autodream-focus.sh`) rewrite it, possibly from an open session at 03:15. A second writer editing the same file would race them. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", describes the two-file design.

### Decision

- `archive_tags` appends `<id><TAB><report date><TAB><taggedAt>` to `tags-consumed.txt`. This script is the only writer of that ledger. "Pending" is the tags file minus the ledger.
- It records only the keys that `collect` put in `vault-tags-manifest.txt`, so a tag made while the run was in flight is read by the next one.
- A rerun of the same date does not record a tag twice: a ledger row matches on id and `taggedAt`.
- A failed append leaves the tag pending and says so.
- Tags are consumed by `archive` under the same gates as an inbox note, and never by `collect`.

### Consequences

Deleting `tags-consumed.txt` makes every tag due again for the next report. The ledger only grows.

## a tag is due for the report of the local day it was made on, decided here from taggedAt

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`tag_pending`)

### Context

A tag is a turn the user marked in a session for the nightly run to look at. The mod that writes `tags.jsonl` has no timezone to speak of, and an evening tag is already tomorrow in UTC. Trusting a UTC day written by the mod would hold back, by a night, exactly the tags made while reviewing the day. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", states the rule.

### Decision

`tag_pending report-date` emits, oldest first, the tags still owed a look:

- Made before the first instant after the reported local day. That cutoff comes from BSD `date` through `pdate_epoch` and `pdate_shift`, like `session-window.sh`, so a DST day is 23 or 25 hours. If it cannot be computed, everything made so far is due.
- Not consumed by an earlier report. A tag's identity is its id and its `taggedAt` (`key` is `id<TAB>taggedAt`), because untagging and tagging a turn again reuses the id.
- Ledger rows of the report date being built do not count, so rebuilding a date that already consumed its tags keeps them.
- A `taggedAt` that does not parse counts as already due, so a tag arrives late and never gets lost. `atEpoch` is null for it.
- A torn or foreign line is skipped, not fatal: two sessions can rewrite the file within moments of each other.

### Consequences

The mod writes no day. A tag made after local midnight waits for the next report. Failure to read the file is handled separately (see `docs/adr/0018-focus-tags.md#a-tags-file-that-cannot-be-read-is-reported-as-unreadable-never-as-no-tags`).

## a tags file that cannot be read is reported as UNREADABLE, never as "no tags"

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`tag_pending` call and the tag branch of `collect`)

### Context

No tags file is the normal case and says nothing. A `tags.jsonl` that exists and will not read (permissions, a `jq` error), or a host with no `jq`, looks the same as no tags unless the failure is seen. The same rule as the iCloud placeholder and `overlap_measured` applies: a degraded measurement must say so. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", records it.

### Decision

- `collect` runs `tag_pending` into a temp file and tests its status. A process substitution would hide the exit status.
- On failure, or when `jq` is absent, it emits a `focus-tags - UNREADABLE` block, counts it under `unreadable:`, and manifests nothing, so the tags are tried again.
- `vault-tags-manifest.txt` is truncated on every run, tags file or not, so a stale one from an earlier run can never be archived.

### Consequences

macOS 15 ships `jq` in `/usr/bin`, so the no-`jq` test builds a PATH without it. `status` does not need `jq` (see `docs/adr/0017-operator-notes-and-vault.md#status-counts-tag-lines-with-grep-so-it-works-without-jq`).

## one global EXIT cleanup for the scratch files, naming globals and never a function's locals

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`cleanup`, `TMP`, `LIVE`, `cmd_last`)

### Context

An EXIT trap that names a function's `local` runs after the function has returned. Under `set -u` the reference is then a fatal error that aborts the trap before the rest of it runs. It also exits before the lock is released, which wedges every later tag. The first version hit this (docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod").

`last --harness omp` makes a 0600 copy of the linearized transcript, which is the person's conversation, and it has to go whichever later step ends the script.

### Decision

`TMP` (the take-back temp file) and `LIVE` (the linearized transcript copy) are globals, empty until set, and `cleanup` removes whichever is non-empty. It is registered once with `trap cleanup EXIT`.

### Consequences

A new scratch file gets a global and a line in `cleanup`. Never register an EXIT trap that names a local.

## the focus writer resolves its install dir, config and helpers the way the collector does

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (top-level resolution of `AUTODREAM_DIR`, `AUTODREAM_CONFIG`, `TAGS_FILE`, `_pp`, `LINEARIZE`; the `path` verb)

### Context

`bin/vault-notes.sh` reads pending tags from `$AUTODREAM_DIR/config`'s view of the world, so a tags file named only in that config is the file the nightly run reads. A writer that looked only at its own environment would write one file while the collector read another, and the tag would never reach a report. The Claude mod and the OMP picker cannot source a shell file, so they ask the script where the file is (`autodream-focus.sh path`) instead of resolving it themselves; see `docs/adr/0018-focus-tags.md#the-focus-mod-asks-the-writer-where-tagsjsonl-is-and-uses-its-own-environment-only-as-a-fallback`.

docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", records the rule that the script reads `$AUTODREAM_DIR/config` the way the collector does and that the caller's exports win.

Installed copies of the script are symlinks into the repo's `bin/`, so a sibling helper sits next to the link in an installed tree and next to the link's target in a repo checkout.

### Decision

- `AUTODREAM_DIR` is the environment's value, else the script's own directory when it carries an install marker (`config` or `PROMPT.md`), else `$HOME/.claude/autodream`.
- The config (`AUTODREAM_CONFIG`, default `$AUTODREAM_DIR/config`) is sourced with `set -a` so its keys are exported, with errexit and nounset off so a bad line cannot kill the script, and the `export -p` snapshot taken before is replayed after, so the caller's exports beat the file. Same two guards the collector and `run.sh` use.
- `TAGS_FILE` is `AUTODREAM_TAGS_FILE`, else `$AUTODREAM_DIR/tags.jsonl`. The `path` verb prints it.
- `portable.sh` and `adapters/omp/linearize.sh` are looked for next to the script path first (installed link tree), then next to `readlink` of it (checkout).
- Environment the script reads: `AUTODREAM_DIR`, `AUTODREAM_TAGS_FILE`, `CODEX_HOME` (default `$HOME/.codex`), `PI_CODING_AGENT_DIR` (OMP's agent directory, default `$HOME/.omp/agent`; `OMP_AGENT_DIR` was a first guess and is wrong).

### Consequences

A new key the collector learns to read from the config needs the same handling here, or the two disagree on which file is the tags file. The OMP extension (`extensions/omp/focus-core.ts`, `tagsPath`) mirrors this order as its fallback; see `docs/adr/0018-focus-tags.md#the-omp-focus-extension-is-a-command-that-gathers-a-turn-and-hands-it-to-the-shared-writer`.

## `tag` takes a kernel flock through a python3 wrapper that re-runs the script

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`LOCKER_PY`, `hold_lock_and_rerun`, `cmd_last`'s hand-off to `tag`)

### Context

Three harnesses (Claude mod, OMP, Codex) can tag at once, and the Claude mod now takes the lock too by running this script rather than writing the file. The lock used to be a directory holding its owner's pid, with a `.reclaim` claim for waiters. Every version of that had a window: an age rule let a suspended writer's lock be taken, an empty pid file read as stale, two waiters could both remove a stale claim. A shell cannot make "judge the holder gone, then take its lock" atomic, which is the same lesson as `question-streaks.sh` (docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, "Open questions that never get answered", and "The focus mod").

### Decision

- `tag` re-runs itself (`AUTODREAM_FOCUS_LOCKED=1`) under a small python3 program that opens `$TAGS_FILE.lock`, takes `flock(2)` `LOCK_EX|LOCK_NB`, marks the descriptor inheritable and `execv`s the script, so the lock is held for the script's whole life.
- The kernel owns the lock: it is dropped when that process exits or dies however it ends. There is no stale lock to detect, so no age rule, no owner pid and no reclaim claim, and a writer suspended for any length of time still holds it.
- A waiter polls without blocking every 50 ms and gives up after five seconds, saying `another tag is being written and did not finish; nothing was changed`.
- Without python3 the script exits 3 and says so rather than writing unlocked.
- A directory left at the lock path by the earlier build is cleared (its `pid` file removed, then `rmdir`), because it cannot be opened as a file. A directory holding anything else is somebody else's and is refused, not deleted.
- `last` only reads session files. It does not hold the lock: it runs `tag` as its own invocation of the script, which takes it.

### Consequences

`python3` is already needed by the web dashboard, so the dependency costs nothing new. Do not reintroduce a file or directory lock that a script judges. The tests (`test_focus_cli_*` in `tests/run-all.sh`) hold a flock from python to check both that a holder keeps it however long and that a waiter changes nothing.

## `last` finds the directory's newest session without a count limit and reads only a person's live turn

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`newest_session`, `cmd_last`)

### Context

Neither OMP nor Codex can draw a button, so `last` is what a person runs from a second terminal. Things learned building it, each fixed after a review or a live run:

- `last` read sessions newest first with a count limit across the whole root, which hid a recent session of the asked directory behind other directories' newer ones.
- A Codex user turn is its own record: an `item_completed` UserMessage event (older builds: an `event_msg` user_message). The `response_item` messages with role user are what Codex injects (instructions, environment context), whatever their text starts with. In the 30 days measured, Codex had 11 interactive sessions against 396 headless `codex exec` runs, so it was scoped by usage and there is no Codex adapter.
- An OMP session file is an append-only tree that keeps every branch the user backed out of. Reading the raw file credits the user with abandoned branches.
- An OMP user-role message with `attribution` of `agent` (steering, hook output, an advisor's prompt stream) is not a human turn. A message with no attribution field counts, as in files from before the field.

### Decision

- `newest_session` sorts the harness's session files by mtime (newest first, within the last 14 days, found by `find -mtime -14`) and reads them until one records the wanted directory (the given path or its physical `pwd -P`). There is no count limit before that match; the 14-day window is the bound.
- Codex: the assistant turn is a `response_item` message with role assistant; the user turn is only the `item_completed` UserMessage or `user_message` event.
- OMP: the file is run through `adapters/omp/linearize.sh` to the live chain; if it cannot be walked, `last` refuses rather than falling back to the raw file. The picked turn skips `attribution == "agent"`. The extension's TypeScript reader (`extensions/omp/focus-core.ts`, `turnOf`) skips agent turns the same way.

### Consequences

The scan can read many files when a directory has no recent session, which the 14-day window bounds. A new harness needs its own two branches here and in `cmd_last`. If Codex changes how it records a human turn, `last --role user` returns nothing or an injected message; test against a real rollout file.

## a tags file that will not read is a refusal, an add is one append, and only a take-back replaces the file

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`cmd_tag`, `fingerprint`)

### Context

Taking a tag back rewrites the whole file, so reading "could not read" as "empty" would replace every tag with the one being added. Only a file that does not exist is empty (docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod": "A read that fails must never lead to a write").

The first version built every write as a copy and a rename, with the copy made by a `{ cat; printf; } > tmp || die` group. Bash ignores errexit inside a group on the left of `||`, and the group's status is its last command's, so a `cat` that failed part-way was hidden by the `printf` after it and the rename replaced every tag with a partial copy. That was the P0 the gate raised on the first version of the OMP and Codex writer. Adding a tag now needs no copy at all.

The Claude mod used to rewrite the file itself, without the script's lock. A copy of that old mod can still be in use.

### Decision

- A tags file that exists and is not a readable regular file makes the script die with `nothing was changed`. Only an absent file counts as empty. A readable file with a line that does not parse is not a refusal: the line is kept as it stands.
- Lines the script does not understand are kept as they stood: untagging drops only the lines whose parsed `.id` matches, found by 1-based line number (any number of them, in case of a hand edit), and an add never touches existing lines.
- An add is one `O_APPEND` write of the line, preceded by a newline when the last byte of the file is not one (a torn last line), in the same write, so the new tag is not glued onto the torn one. It cannot drop another writer's line even if that writer takes no lock, and there is no copy to come out partial.
- A take-back is a temp file in the same directory and one `mv`. The cksum fingerprint is taken before the copy and checked again just before the rename, and a change makes the script refuse. The lock holds off every cooperating writer; the fingerprint is for a writer that takes no lock.
- Tagging the same turn again is the toggle: it takes the tag back, as the mod's button does.

### Consequences

The one race nothing here can close is an old unlocked writer against a take-back: the fingerprint narrows it, it does not remove it. Never build a copy as a brace group on the left of `||`. Any new write path must start from "a failed read refuses".

## a tag carries `harness` and an absolute `transcript` path

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`cmd_tag`), `bin/vault-notes.sh`

### Context

The line `autodream-focus.sh tag` writes is the Claude mod's line plus `harness` and, when known, `transcript` (the session file), so the nightly run can open a session that is not a Claude one. `bin/vault-notes.sh` turns pending tags into notes for L2, which will Read the file a note names. The tags file is a plain file anyone can edit, so the collector trusts a recorded transcript only if it is an absolute path to an existing `.jsonl` (docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod").

The nightly run reads from another working directory, so a relative `--transcript` recorded as given would point nowhere at 03:15.

### Decision

`cmd_tag` resolves a relative `--transcript` to an absolute path at write time (`cd` to its directory, `pwd -P`, plus the basename), and refuses the tag if it cannot. An empty transcript is omitted from the line; the `transcript` key is added only when set. The same applies to `--file` through `last`, which hands its file to `tag` as `--transcript`.

### Consequences

Do not record a path the collector would have to resolve against its own cwd. A new field on the line is ignored by the mod (which reads only what it knows) and must be taught to `vault-notes.sh` separately.

## the OMP focus extension is a command that gathers a turn and hands it to the shared writer

Status: accepted · Date: 2026-11-21 · Code: `extensions/omp/autodream-focus.ts` (`tagsFileNow`, `toggle`, the shortcut and `agent_start` hooks), `extensions/omp/focus-core.ts` (`turnOf`, `tagArgv`, `cutAt`, `WRITER_CAP`, `tagsPath`, `taggedIds`, `pickList`), `extensions/omp/autodream-focus.test.ts`

### Context

OMP draws its own prompt and reply rows and gives an extension no way to put a button on them (only its own custom messages, the footer and widgets). So the extension is a `/focus` command, as close to the Claude Code button as OMP allows. docs/adr/0018-focus-tags.md#background-the-focus-mod-modsautodream-focus-the-one-place-the-user-writes-into-the-nightly-run-from-a-transcript, "The focus mod", records why OMP and Codex tag through `bin/autodream-focus.sh` and not a copy of the mod's code, and `extensions/omp/README.md` has the setup.

Facts that shaped the code:

- The tags file has several writers. The script holds the lock, the unreadable-file refusal and the line format, so the extension does none of the writing (`docs/adr/0018-focus-tags.md#tag-takes-a-kernel-flock-through-a-python3-wrapper-that-re-runs-the-script`, `docs/adr/0018-focus-tags.md#a-tags-file-that-will-not-read-is-a-refusal-an-add-is-one-append-and-only-a-take-back-replaces-the-file`).
- The script also reads `$AUTODREAM_DIR/config`, which the extension cannot, so a tags file named only there is invisible to the extension's own resolution.
- OMP's `exec` has no stdin, so the turn text goes as an argument and a very long turn is bounded in the extension.
- The writer marks a cut with an ellipsis only when it sees more than its cap (2,000), counted in code points. A cut at exactly the cap would hand it a text that looks whole, and a cut in UTF-16 units splits an emoji. Same rule as `docs/adr/0018-focus-tags.md#the-mod-hands-the-writer-one-code-point-past-its-cap-counted-in-code-points`.
- A user-role message attributed to the agent (a steering note, hook output, an advisor's prompt) is not something the person typed.
- On the first live run `ctrl+alt+f` moved the window instead of reaching OMP: ctrl+option chords are the usual macOS window-manager family. Neither OMP nor cmux binds `ctrl+shift+f`, and Ghostty passes it through.
- `bun test` cannot start a headless OMP from the Claude Code sandbox, because OMP registers a client under `~/.omp/run/daemons/`, the live daemon's state.

### Decision

- `focus-core.ts` holds what decides something, free of the OMP API so `bun test` runs it: reading a turn (text blocks only, joined; a bare string for a user message; thinking and tool-call blocks are not text; a reply with no text is not a turn; agent-attributed user turns are skipped, as the script's `last --harness omp` skips them), the `/focus` argument words, the picker rows, and the argv.
- `tagArgv` cuts the text at `WRITER_CAP + 1` code points (`cutAt`) so the writer sees a turn over its cap and marks the cut.
- The picker's labels lead with the turn's number counted from the oldest, because the select dialog hands back a label and this keeps two turns with the same words apart. Rows already tagged are checked.
- `taggedIds` reads `tags.jsonl` text and ignores a line it cannot parse (torn or hand-edited): the script keeps such a line, the picker just cannot mark it.
- `tagsFileNow` asks `<script> path` (5 s timeout) and falls back to `tagsPath`, which resolves the way the script does: `AUTODREAM_TAGS_FILE`, else `AUTODREAM_DIR`, else the script's own directory when it holds `config` or `PROMPT.md`, else `~/.claude/autodream`.
- The footer mark describes the reply that was tagged, so a new `agent_start` clears it.
- The shortcut defaults to `ctrl+shift+f`; `AUTODREAM_FOCUS_KEY` changes it and an empty value registers none.
- `autodream-focus.test.ts` runs the extension against a fake OMP API whose `exec` runs the real `bin/autodream-focus.sh`, so the whole path from `/focus` to the line in `tags.jsonl` is checked.

### Consequences

Unverified: OMP's own extension loader and key handling. The first run in a real OMP is the check. If the writer's cap or its line format changes, change `WRITER_CAP` and the argv here in the same commit. Do not give the extension a write path to `tags.jsonl`.
