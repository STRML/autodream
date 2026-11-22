# 0022: Review and triage of open questions

Status: accepted · Governs: `bin/pending-triage.sh`, `mods/autodream-band/hooks/lib.ts`, `mods/autodream-band/hooks/register.tsx`, `mods/autodream-band/tests/hooks.test.tsx`, `mods/autodream-band/tests/stand-in.tsx`, `bin/review.sh`, `bin/triage-candidates.sh`, `bin/triage-dream.sh` and 1 more

This record holds 23 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: The triage prompt is questions-only, and that is load-bearing](#background-the-triage-prompt-is-questions-only-and-that-is-load-bearing)
- [Background: The Claude Code mod (`mods/autodream-band`)](#background-the-claude-code-mod-modsautodream-band)
- [`pending-triage.sh` sources the user-edited config with nounset off, and the environment wins](#pending-triagesh-sources-the-user-edited-config-with-nounset-off-and-the-environment-wins)
- [a half-triaged report subtracts its logged questions but always keeps at least one pending](#a-half-triaged-report-subtracts-its-logged-questions-but-always-keeps-at-least-one-pending)
- [the mod resolves autodream locations from review.sh's own environment variables](#the-mod-resolves-autodream-locations-from-reviewshs-own-environment-variables)
- [the in-session triage prompt is submitted from a 100 ms timer](#the-in-session-triage-prompt-is-submitted-from-a-100-ms-timer)
- [the band shows a fresh report that is worth stopping for, and refreshes on three triggers](#the-band-shows-a-fresh-report-that-is-worth-stopping-for-and-refreshes-on-three-triggers)
- [the band stacks under other plugins' rows and is one truncating row](#the-band-stacks-under-other-plugins-rows-and-is-one-truncating-row)
- [default triage runs review.sh inline in a cmux split, with a fallback for each failure](#default-triage-runs-reviewsh-inline-in-a-cmux-split-with-a-fallback-for-each-failure)
- [the in-session triage prompt and skip rule mirror review.sh by hand](#the-in-session-triage-prompt-and-skip-rule-mirror-reviewsh-by-hand)
- [a cmux triage launch is deduplicated by a claim directory plus a confirmed token bound to the report's digest](#a-cmux-triage-launch-is-deduplicated-by-a-claim-directory-plus-a-confirmed-token-bound-to-the-reports-digest)
- [review.sh hands off to cmux only after validating, re-runs itself inline there, and never launches headless claude](#reviewsh-hands-off-to-cmux-only-after-validating-re-runs-itself-inline-there-and-never-launches-headless-claude)
- [the triage session always passes --model](#the-triage-session-always-passes---model)
- [the triage session is handed only the open questions, all or nothing, through a temp file](#the-triage-session-is-handed-only-the-open-questions-all-or-nothing-through-a-temp-file)
- [review.sh looks for a sibling helper beside itself, then beside its symlink target, and defaults reports to the install dir's sibling](#reviewsh-looks-for-a-sibling-helper-beside-itself-then-beside-its-symlink-target-and-defaults-reports-to-the-install-dirs-sibling)
- [review.sh skips a report only when it is sure, and checks "already triaged" before "no open questions"](#reviewsh-skips-a-report-only-when-it-is-sure-and-checks-already-triaged-before-no-open-questions)
- [a rerun of a report date neither keeps the old list nor is held back by its own suggestion](#a-rerun-of-a-report-date-neither-keeps-the-old-list-nor-is-held-back-by-its-own-suggestion)
- [a repo is suggested for triage only past a threshold, with write access, outside a cooldown](#a-repo-is-suggested-for-triage-only-past-a-threshold-with-write-access-outside-a-cooldown)
- [triage-dream.sh probes the config in a subshell before sourcing it, and the caller's environment wins](#triage-dreamsh-probes-the-config-in-a-subshell-before-sourcing-it-and-the-callers-environment-wins)
- [the triage model call runs from the isolated work directory and wipes its project bucket](#the-triage-model-call-runs-from-the-isolated-work-directory-and-wipes-its-project-bucket)
- [triage-dream.sh skips the pass when no timeout binary exists](#triage-dreamsh-skips-the-pass-when-no-timeout-binary-exists)
- [triage-dream.sh finds its libraries and prompt beside itself, beside its symlink target, in the install dir, then in prompts/](#triage-dreamsh-finds-its-libraries-and-prompt-beside-itself-beside-its-symlink-target-in-the-install-dir-then-in-prompts)
- [dream triage is opt-in, runs last, and is never fatal](#dream-triage-is-opt-in-runs-last-and-is-never-fatal)

## Background: The triage prompt is questions-only, and that is load-bearing

This section was moved here from the former CLAUDE.md. Its original title: "The triage prompt is questions-only, and that is load-bearing".

`review.sh` used to pass the whole report through `--append-system-prompt` and launch with the literal prompt `go`. On 2026-10-27 that refused every launch: the 2026-10-26 report narrated a night of TV-firmware work (`sdb`, root status, `dlopen`, W^X by mount), and Opus 5.5 answered `Opus 5.5's safeguards flagged this session ... Details: [cyber]` before the first reply. Replaying the same request headlessly with `claude -p` reproduced it, and the same report's questions section (~2KB of decision text) passed — so the trigger was the findings body, not the triage task, the memory hook, or the mnemopi store.

Two rules came out of it:

- **Never inline a long document into a system prompt.** Inline only the section the task acts on and point at the file for detail. A report body can read like a security incident even when nothing in it is wrong.
- **Never launch intent-carrying work with a one-word prompt.** `go` gives the model nothing to anchor on, so whatever context it was handed becomes the whole picture of what the session is about.

**The section is found by sentinel, not by heading.** `AUTODREAM_QUESTIONS_BEGIN` and `AUTODREAM_QUESTIONS_END` bracket it, `PROMPT.md` makes L2 emit them, and `report-questions` in `bin/report-format.sh` is the only reader. This was not the first design: the four consumers each parsed the markdown heading their own way, and five review rounds on `review.sh` alone found a new disagreement every time (a heading inside a fence, `~~~` fences, fence length, a fence's info string). Hand-rolled markdown parsing in four scripts is a losing shape; a producer-written sentinel is one line on each side and no grammar.

The cap on the inlined section is all-or-nothing. A section that does not fit is not inlined, and the prompt sends the session to the report. Cutting a section at a line, an item or a fence and calling the rest "the questions" is what asks a session to recommend on half a question.

A report from `AUTODREAM_QUESTIONS_EPOCH` (default 2026-10-27) on is truncated unless its block is closed, so a bad block costs one rebuild instead of a silent wrong read. `tests/review-prompt.sh` pins the launch contract; `tests/report-format.sh` pins the reader against the same fixtures the old inline code read.

## Background: The Claude Code mod (`mods/autodream-band`)

This section was moved here from the former CLAUDE.md. Its original title: "The Claude Code mod (`mods/autodream-band`)".

An optional mod for Claude Code itself (a hot-reloading plugin of function hooks, not shell): a band above the prompt when the newest report has open questions, `/dream` to read it, and Triage to run `review.sh` in a cmux split. It is the only thing in the repo that **parses the report**, so `prompts/PROMPT.md` now has a second reader besides L2's own consumers. These four shapes are its contract, and `hooks/lib.ts` is where to change it when one moves:

- the title `# Autodream — YYYY-MM-DD`;
- `## Top patterns` with `### <title>` blocks carrying `- **Severity**: high|medium|low`;
- `## Open questions` and the `<!-- autodream:open-questions=N -->` marker (no marker reads as zero questions, so the band stays hidden);
- a `## Triage decisions` heading, which is what makes the band go away.

It finds `review.sh`, the reports and cmux through the variables `review.sh` reads (`AUTODREAM_DIR`, `DREAMS_DIR`, `CMUX_BIN`) with the same defaults, so a new knob in `review.sh` means a matching line in `locations()`. It cannot see a value that lives only in `$AUTODREAM_DIR/config`. Its in-session walk-through (`/dream here`) is a prompt of its own in `triagePrompt`, modelled on `review.sh`'s system prompt but not generated from it: if `review.sh`'s rules change, check whether the mod's should.

Its tests run under Claude Code, not in `tests/run-all.sh` and not in CI (`claude plugin validate mods/autodream-band`, `claude plugin test mods/autodream-band`; `tsc -p` needs the types Claude Code writes into the git-ignored `.claude-plugin/types/` when it loads the mod). `$.env.get` takes a literal variable name, so the variables a mod reads can be listed: a loop over names fails validation.

## `pending-triage.sh` sources the user-edited config with nounset off, and the environment wins

Status: accepted · Date: 2026-11-21 · Code: `bin/pending-triage.sh` (config block)

### Context

The config is user-edited. A bare `source` under `set -u` kills the shell on one misspelled variable, before the summary prints. docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent, "Bash traps this feature hit", records the same trap for `run.sh` and the helper scripts.

### Decision

The script saves `DREAMS_DIR` and `AUTODREAM_PENDING_DAYS` from the environment, runs `set +u`, sources the config, runs `set -u` again, then restores the saved values when they were set. A variable exported by the caller therefore beats the config.

### Consequences

Any new variable this script reads from the config needs the same save and restore, or the config will override a caller who set it on purpose.

## a half-triaged report subtracts its logged questions but always keeps at least one pending

Status: accepted · Date: 2026-11-21 · Code: `bin/pending-triage.sh` (`pending`)

### Context

A report stays pending until its `## Triage decisions` heading exists. A session that is part way through a report logs under `## Triage in progress` and renames the heading only after the last question is resolved. The report's `autodream:open-questions=N` marker never changes while that happens.

### Decision

`pending` reports `N` minus the count from `report_progress_count`, so the summary shows what is left. The result never drops below 1. The heading is renamed only when the last question is resolved, so a report that still has no `## Triage decisions` heading has at least one question left.

### Consequences

Reports with an unreadable count are a separate case: they are listed with `?` and reported on their own (see `usage` in the script). `tests/pending-triage.sh` pins both.

## the mod resolves autodream locations from review.sh's own environment variables

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/lib.ts` (`locations`), `mods/autodream-band/hooks/register.tsx` (`autodreamPaths`)

### Context

The mod must find the reports, `review.sh` and cmux the way `bin/review.sh` does, or it would open a different install's files. docs/adr/0022-review-and-triage.md#background-the-claude-code-mod-modsautodream-band ("The Claude Code mod") already says: it reads `AUTODREAM_DIR`, `DREAMS_DIR` and `CMUX_BIN` with review.sh's defaults and cannot see a value that lives only in `$AUTODREAM_DIR/config`.

### Decision

`locations` takes `HOME`, `AUTODREAM_DIR`, `DREAMS_DIR` and `CMUX_BIN` from the mod's environment (`$.env.get` takes literal names, so the list is spelled out). An exported value wins, an empty one counts as unset, and the defaults are those of `install.sh` and `review.sh`. A value set only in the config file is invisible, so export it or set it in Claude Code's environment to move the mod too.

### Consequences

A new location knob in `review.sh` needs a matching line in `locations` and `autodreamPaths`.

## the in-session triage prompt is submitted from a 100 ms timer

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/register.tsx` (`triageHere`), `mods/autodream-band/tests/hooks.test.tsx` (`world`, `landed`)

### Context

`$.prompt.submit` resolves when the new turn starts, and a call begun inside a dispatch (a button press, a slash command) is dropped when that dispatch ends. Awaiting it inside the handler would either block the reply or lose the prompt.

### Decision

`triageHere` returns its reply text at once and schedules the submit with `$.clock.after(100, ...)`, outside the dispatch. A rejected submit is swallowed.

### Consequences

Tests that expect a prompt must let the timer fire: the mock clock exposes `landed()` for that, and a test that skips it sees `sent` empty.

## the band shows a fresh report that is worth stopping for, and refreshes on three triggers

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/lib.ts` (`isFresh`, `shouldShow`), `mods/autodream-band/hooks/register.tsx` (`refresh`, `register`)

### Context

Reports are nightly, so a report two days old is news and a week old is not. PROMPT.md asks for `high|medium|low` severities, but the shipped example report also uses `critical`, which outranks `high`. A band that always showed would be wallpaper; one that stayed after a triage would nag about decided questions. The docs/adr/0022-review-and-triage.md#background-the-claude-code-mod-modsautodream-band section "The Claude Code mod (`mods/autodream-band`)" lists the four report shapes the mod parses; this ADR records only the display rules built on them.

### Decision

- `isFresh` allows two days of age (the call in `refresh` passes `2`), compared by local calendar day.
- `shouldShow` is true only when the report is not triaged, is not the dismissed date, and has either open questions or a pattern with severity `critical`, `high` or `medium`. `low` and unknown never earn the band.
- A session can outlive the night, so `session.start` also arms a 30-minute `refresh`. A triage ends by logging decisions into the report, so `turn.complete` refreshes too and the band clears on the turn that ends it.

### Consequences

A new severity word in PROMPT.md needs a line in `WORTH_STOPPING_FOR`, or its reports never raise the band. The two-day window is a constant at the call site, not a setting.

## the band stacks under other plugins' rows and is one truncating row

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/register.tsx` (`AbovePrompt` render), `mods/autodream-band/tests/stand-in.tsx`

### Context

Other plugins and the engine draw in the `AbovePrompt` slot too. Replacing their output would silently remove their rows. Buttons next to a long summary wrap into several lines if the summary is allowed to.

### Decision

The render awaits `next(e)` and stacks the band beneath what it returns. The band is one row: the summary sits in a `flexGrow`/`flexShrink` box with `wrap="truncate-end"`, and the buttons in a `flexShrink={0}` box, so the summary takes the room the buttons leave and ends in an ellipsis. `stand-in.tsx` is a second plugin loaded in the `prepend` and `append` tiers to prove both the other row and the engine's row survive.

### Consequences

Tests find the band by `key: 'band'`; keep that key when restructuring the row.

## default triage runs review.sh inline in a cmux split, with a fallback for each failure

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/register.tsx` (`triageBeside`, `runInNewSplit`, `triageInCmux`), `mods/autodream-band/hooks/lib.ts` (`triageCommandLine`, `surfaceRef`, `cmuxTriage`)

### Context

Triage in the current session derails whatever that conversation was about, so the default opens a fresh session beside it. `review.sh` normally hands off to a new cmux workspace; typed into a split it must instead fill that split. cmux's `new-split` and `send` default to the surface the session runs in. `new-split` prints a short ref (`surface:7`) or a UUID, and `send` reads a backslash-n in its text as Enter.

### Decision

- `triageCommandLine` runs `env AUTODREAM_TRIAGE_SURFACE=inline bash <script> [--force] <date>`, so the triage session fills the split instead of opening another workspace.
- `surfaceRef` reads the new split's address from `new-split`'s stdout (ref, else UUID). The command is sent as `<line>\n` with the two characters backslash and n.
- The cascade: no cmux or no review.sh means triage in this session; outside cmux (no `CMUX_SURFACE_ID`) there is nothing to split, so review.sh opens its own workspace; an unreadable split address or a failed send also falls back to the workspace, and the reply says so.
- `cmuxTriage` drives the workspace route through review.sh's documented knobs (`AUTODREAM_TRIAGE_SURFACE=cmux`, `AUTODREAM_TRIAGE_FOCUS=true`), so nothing in the user's autodream config changes.

### Consequences

The tests assert the exact argv of each step and the escaped newline. A change to cmux's output format or Enter convention lands in `surfaceRef` and the `send` text.

## the in-session triage prompt and skip rule mirror review.sh by hand

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/lib.ts` (`triagePrompt`), `mods/autodream-band/hooks/register.tsx` (`nothingToTriage`)

### Context

`/dream here` walks the open questions in the current session. `bin/review.sh` has its own system prompt for the same walk and its own rule for when there is nothing to triage (already triaged, or no open questions, unless `--force`). docs/adr/0022-review-and-triage.md#background-the-claude-code-mod-modsautodream-band ("The Claude Code mod") states the prompt is "modelled on review.sh's system prompt but not generated from it".

### Decision

`triagePrompt` copies the review.sh workflow with two deliberate differences: the report is read from its path rather than inlined (docs/adr/0022-review-and-triage.md#background-the-triage-prompt-is-questions-only-and-that-is-load-bearing "The triage prompt is questions-only": never inline a long document into a system prompt), and this session's own permission mode applies, not `bypassPermissions`. `nothingToTriage` repeats review.sh's skip rule, and `force` overrides it in both.

### Consequences

Nothing keeps the copy in step. When review.sh's rules or skip condition change, check the prompt and `nothingToTriage` in the same change.

## a cmux triage launch is deduplicated by a claim directory plus a confirmed token bound to the report's digest

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (cmux branch: `REPORT_KEY`, `LAUNCH_MARKER`, `LAUNCH_CONFIRMED`, `CLAIM_GRACE`)

### Context

`install.sh` provisions the review job with five triggers a day (08:00, 09:15, 12:15, 15:30, 18:15). Whichever fires first after the report lands opens the workspace, and later ones for the same report must not open a second.

### Decision

- **Key by content digest, not mtime.** mtime has one-second resolution, so a same-second rebuild would share a marker and its triage would be swallowed. A rebuild with `AUTODREAM_FORCE=1` has new content, so it invalidates the old marker. A missing `shasum` is a hard error (the key is checked for emptiness, since the assignment's status is awk's); an empty key would collapse every report of that day into one marker.
- **Claim by `mkdir`**, which is atomic, so two overlapping triggers cannot both pass. A failed `mkdir` where the directory now exists is a genuine race (exit 0). Where it does not exist it is an I/O error (exit 1), because reporting it as "in progress" silently drops triage.
- **The confirmed token is a sibling file**, not inside the claim directory. The stale reap uses `find -delete`, which cannot remove a non-empty directory, and both names still match the `review-launched-*` prune glob. Claims and tokens older than 14 days are reaped, including on `--force`, since that is the retry-after-failure route.
- **A claim with no token** younger than `CLAIM_GRACE` (900 s) is an in-flight launch. An older one is abandoned (a killed process) and is reclaimed, so a dead popup cannot suppress triggers forever.
- **The token is bound to the launch-time digest and stamped as soon as cmux returns 0**, before any output parsing. The workspace reads the report path when it starts, so the parent cannot know which bytes it read. Re-hashing after the create could mark a rebuilt report B confirmed when the workspace triaged A, swallowing B's questions. Bound to A, B has no token and its own trigger surfaces it. The worst case is a duplicate popup, never a lost triage. A failed `touch` is a warning, not a failure, because the workspace exists.
- **A failed create releases the claim only if this process owns it or it is past the grace window.** A `--force` run never claims, so it must not delete a live claim of a concurrent normal run, but it does release a stale one.

### Consequences

Changing the key, the token location or the grace window changes what `tests/review-cmux.sh` pins. Do not re-hash the report after launch.

## review.sh hands off to cmux only after validating, re-runs itself inline there, and never launches headless claude

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (cmux branch: `INNER_CMD`, `shq`, `WS_REF`)

### Context

macOS routes a shell script to the default handler for `public.shell-script`, which was iTerm2 on this host, so the triage kept opening there. `AUTODREAM_TRIAGE_SURFACE=cmux` gives it a dedicated workspace instead. Environment variables override the config file, and the config overrides defaults.

### Decision

- **Hand off after validation.** The report is resolved and the skip logic has run first, so a missing-report error surfaces in the caller's terminal, not in a detached workspace.
- **The workspace re-runs this script with the surface forced to `inline`**, and with `--force` carried through when given. Without `--force` the inner run would find nothing to triage and exit, leaving a workspace that dies on open.
- **Every interpolated value in the inner command is `%q`-quoted.** Paths and the date may hold apostrophes (an install under `/tmp/O'Brien`), and an unquoted one breaks the inner shell parse. `FORCE_ARG` is generated here, so it stays literal.
- **cmux is found without PATH.** `CMUX_BIN` defaults to the app bundle path, so launchd's minimal environment resolves it whenever `install.sh` accepted it. Install provisions the review job iff the same three-step resolution (config, then PATH, then default) finds an executable, so runtime cannot diverge from install time.
- **`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`** stops claude rewriting the tab title. The title is then renamed three times, detached and best effort, over the window in which the shell sets its own startup title. The workspace ref is cosmetic. An unparseable one skips the rename and never the launch.
- **Focus defaults to false**, so a nightly run does not pull the user out of what they are doing.
- **No cmux and no TTY is a failure.** A headless `exec claude` has no terminal to talk to, so the marker is never confirmed and every trigger retries forever. A terminal run falls back to inline, because the user is watching it. A failed create releases the claim and exits non-zero, so a scheduled job cannot think the triage happened (and a cmux that prints workspace-like text while failing cannot latch a false marker).

### Consequences

Dedup of the launch is `docs/adr/0022-review-and-triage.md#a-cmux-triage-launch-is-deduplicated-by-a-claim-directory-plus-a-confirmed-token-bound-to-the-reports-digest`. `tests/review-cmux.sh` pins this path with a mock cmux.

## the triage session always passes --model

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (`AUTODREAM_REVIEW_MODEL`)

### Context

Without `--model`, `claude` inherits the default from the user's `settings.json`. That is rarely the model the triage was meant to run on.

### Decision

`review.sh` passes `--model "$AUTODREAM_REVIEW_MODEL"` (default `opus`) on every launch, and the cmux workspace's inner command carries the value forward.

### Consequences

Changing the triage model is a config or environment change, never a reliance on the user's settings default.

## the triage session is handed only the open questions, all or nothing, through a temp file

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (`QUESTIONS_CAP`, `SYSTEM_TMP`)

### Context

On 2026-10-27 every launch with the whole report inlined was refused with "Opus 5.5's safeguards flagged this session ... [cyber]", including a bare "go". The night's findings, 25 KB of TV-firmware narrative (`sdb`, root status, `dlopen`), read as an offensive-security engagement to the provider's content classifier. The same report's questions section, about 2 KB of decision text, passed. docs/adr/0022-review-and-triage.md#background-the-triage-prompt-is-questions-only-and-that-is-load-bearing, "The triage prompt is questions-only, and that is load-bearing", has the full account.

### Decision

- The prompt inlines the section `report_questions` returns and points at the report file for anything deeper. Which text is "the section" is `report-format.sh`'s contract (`docs/adr/0009-l2-aggregation.md#the-open-questions-section-is-found-by-sentinel-lines-with-a-fenced-heading-fallback-only-for-legacy-dates`), so `review.sh` parses no markdown.
- The cap (`QUESTIONS_CAP`, 12000 bytes) is all-or-nothing. A section that does not fit is not inlined, and the prompt tells the session where to read it. Cutting a section at a line, item or fence asks the session to recommend on half a question. The intro text differs for a block report (sentinel names) and a pre-block one (heading name), because the sentinels do not exist in the latter.
- The system prompt is built through a temp file. A heredoc inside `$(...)` is mis-parsed when the body holds apostrophes or a literal `)`.

### Consequences

Never inline a long document into a system prompt. Never launch intent-carrying work with a one-word prompt: the launch text names the task. `tests/review-prompt.sh` pins the contract.

## review.sh looks for a sibling helper beside itself, then beside its symlink target, and defaults reports to the install dir's sibling

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (`source_sibling`, `DREAMS_DIR` default)

### Context

`install.sh` symlinks each script into `$AUTODREAM_DIR`. A merge updates the repo checkout, and so every installed script, before `install.sh` links a newly added helper. Looking only beside the symlink would then fail with a missing file.

An install under another prefix (the omp one lived in `~/.omp/agent/{autodream,dreams}`) made the legacy `~/.claude/dreams` default fail every manual `review.sh <date>` with "could not locate" the report.

### Decision

- `source_sibling` tries the symlink's own directory first, then the directory of `readlink`'s target.
- `DREAMS_DIR` defaults to `dreams` beside the install dir, not to `~/.claude/dreams`. Install-dir resolution itself is `bin/lib-install-dir.sh`.

### Consequences

A new helper that `review.sh` sources is found straight after a merge. `bin/triage-dream.sh` has the same lookup in `find_file` (see `docs/adr/0022-review-and-triage.md#triage-dreamsh-finds-its-libraries-and-prompt-beside-itself-beside-its-symlink-target-in-the-install-dir-then-in-prompts`).

## review.sh skips a report only when it is sure, and checks "already triaged" before "no open questions"

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (skip block before the cmux hand-off)

### Context

Most nights the report has no open questions, and launching a session to be told "nothing to do" costs a full session's tokens. A false "nothing to do" silently swallows real questions, while a false launch only wastes tokens.

A report can be both empty and already worked through (an empty-day stub someone closed out), and "already triaged" is the more informative reason of the two.

### Decision

- The skip uses `report_open_questions` (see `docs/adr/0009-l2-aggregation.md#the-open-questions-count-is-read-strictly-completeness-loosely-and-anything-unrecognised-is-unknown`), which says `unknown` for any shape it does not recognise. Only an exact `0` skips.
- The triaged check runs first, so the notice names the better reason. `--force` bypasses both.

### Consequences

Do not add a looser "looks empty" test to the skip. Moving the open-questions check ahead of the triaged check changes the notice text the tests assert.

## a rerun of a report date neither keeps the old list nor is held back by its own suggestion

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-candidates.sh` (`held_back`, `last_suggestion`, the artifact removal before the first exit)

### Context

The nightly can be retried, and a date can be rebuilt long afterward. A stale `triage-candidates.md` from an earlier run would be copied by L2 into the new report, and a retried night held back by its own earlier suggestion would show nothing.

### Decision

- Both output files are removed before the first early exit, whatever happens next.
- The cooldown counts from the report date (the findings directory's name), not from today, so a late rerun of an old night judges it as that night did. A negative gap (a rerun of an older night, or a skewed clock) applies no cooldown, and a state row for the same date is a retried night and never holds it back.
- `last_suggestion` takes the latest valid row for the slug, compared in any case, so one garbage row cannot hide a good one.

### Consequences

Keep the state file's `slug<TAB>date<TAB>count` shape. `record_suggestion` skips a row identical to the last, so reruns do not grow it.

## a repo is suggested for triage only past a threshold, with write access, outside a cooldown

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-candidates.sh` (`read_issues`, `can_triage`, `held_back`)

### Context

Without limits the same backlog would be suggested every night, and an upstream project whose tracker the user cannot label would be suggested at all. The user-facing rules are in the script's `--help` text.

### Decision

- Untriaged means no state label (`needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) or an explicit `needs-triage`. A never-triaged repo has no state labels, so every open issue counts: its first triage is what the list exists for.
- `AUTODREAM_TRIAGE_MIN` sets the threshold. `AUTODREAM_TRIAGE_COOLDOWN_DAYS` holds a repo back after a suggestion unless the count has grown by `AUTODREAM_TRIAGE_GROW`.
- The permission and archived check (`gh repo view`) runs only for repos that cleared the threshold, so the extra call is spent where it matters.
- The script reads only. It always exits 0 once it has an output directory, because a failure here must not cost the night's report.

### Consequences

`tests/triage-candidates.sh` pins one row per case of the failure matrix. A new skip reason needs a row there.

## triage-dream.sh probes the config in a subshell before sourcing it, and the caller's environment wins

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (config block)

### Context

Sourcing a user-edited file under `set -u` kills the shell with its error hidden, so a bad config fails the pass with no explanation. See docs/adr/0017-operator-notes-and-vault.md#background-bash-traps-this-feature-hit-all-of-them-silent, "Bash traps this feature hit, all of them silent". `run.sh` follows the same rule.

### Decision

A throwaway subshell sources the config with `set -u` first and its stderr is captured. On failure the script logs `WARNING: ignoring <file>: <error>` and carries on. On success it snapshots `export -p`, sources the config with `set -a`, and replays the snapshot, so a variable the caller exported beats the config.

### Consequences

Keep the three steps together. `set -a` is what lets helper processes see a config key, and the replay is what lets a caller disable a feature by exporting an empty value.

## the triage model call runs from the isolated work directory and wipes its project bucket

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (`WORK_DIR`, `clean_work_bucket`)

### Context

Claude Code's AI-title generation writes a one-line stub into the launch cwd's project bucket even with `--no-session-persistence`. Launched from the home directory, those stubs polluted real session history. See docs/adr/0011-self-pollution.md#background-the-ai-title-stub-vector-second-order-self-pollution, "The AI-title stub vector (second-order self-pollution)".

### Decision

The engine runs from `$AUTODREAM_DIR/work`, the same directory `run.sh`'s workers use. The bucket that directory maps to under `$PROJECTS_DIR` is removed before the call and after it.

### Consequences

The model reads and writes only by absolute path, so the cwd carries no other meaning. Keep the work directory identical to `run.sh`'s, or the wipe misses the bucket.

## triage-dream.sh skips the pass when no timeout binary exists

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (`TMO`)

### Context

The pass runs at the end of the night, holding the run and its lock. A wedged engine with no bound would hold both indefinitely. macOS ships no `timeout`.

### Decision

The call is wrapped in `timeout` or `gtimeout` (`-k 30`, `AUTODREAM_TRIAGE_TIMEOUT`, default 900). With neither on PATH the script logs why and exits 1 rather than run an unbounded model call, as L1's warmup does.

### Consequences

A host without coreutils never gets a triage file. The exit code 1 says the pass produced nothing, and the log line names the cause.

## triage-dream.sh finds its libraries and prompt beside itself, beside its symlink target, in the install dir, then in prompts/

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (`find_file`)

### Context

The install symlinks each script into `$AUTODREAM_DIR`, so the directory a script runs from may not hold its libraries or `TRIAGE_DREAM.md`. See `docs/adr/0022-review-and-triage.md#reviewsh-looks-for-a-sibling-helper-beside-itself-then-beside-its-symlink-target-and-defaults-reports-to-the-install-dirs-sibling` for the same reason in `review.sh`.

### Decision

`find_file` returns the first readable copy from the script's directory, the symlink target's directory, `$AUTODREAM_DIR`, then `<target dir>/../prompts`.

### Consequences

A new helper or prompt is found whichever way the script was started, including a checkout run before `install.sh` re-links.

## dream triage is opt-in, runs last, and is never fatal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `AUTODREAM_TRIAGE`, `TRIAGE_DREAM`, `bin/triage-dream.sh`)

### Context
It is one more model call, so a hang or a failure there must not hold back the pins, the banner or the consume steps above it. Only a validated delivery is triaged. The engine is L2's (an adapter); the model gets Read and Glob only, and `bin/triage-dream.sh` writes `dreams/<date>.triage.md` itself.

### Decision
When `AUTODREAM_TRIAGE=1`, `L2_DELIVERED=1` and `report_complete`, the runner calls the script with `AUTODREAM_L2_ENGINE="$L2_ENGINE"`, appends its output to the run log, logs and continues on failure, and cleans the work bucket. It is off unless `AUTODREAM_TRIAGE=1`, and a missing `triage-dream.sh` logs and skips.

### Consequences
Keep it last. Do not make the missing or failing script abort the run.
