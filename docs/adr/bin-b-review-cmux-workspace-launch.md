# bin-b: review.sh hands off to cmux only after validating, re-runs itself inline there, and never launches headless claude

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (cmux branch: `INNER_CMD`, `shq`, `WS_REF`)

## Context

macOS routes a shell script to the default handler for `public.shell-script`, which was iTerm2 on this host, so the triage kept opening there. `AUTODREAM_TRIAGE_SURFACE=cmux` gives it a dedicated workspace instead. Environment variables override the config file, and the config overrides defaults.

## Decision

- **Hand off after validation.** The report is resolved and the skip logic has run first, so a missing-report error surfaces in the caller's terminal, not in a detached workspace.
- **The workspace re-runs this script with the surface forced to `inline`**, and with `--force` carried through when given. Without `--force` the inner run would find nothing to triage and exit, leaving a workspace that dies on open.
- **Every interpolated value in the inner command is `%q`-quoted.** Paths and the date may hold apostrophes (an install under `/tmp/O'Brien`), and an unquoted one breaks the inner shell parse. `FORCE_ARG` is generated here, so it stays literal.
- **cmux is found without PATH.** `CMUX_BIN` defaults to the app bundle path, so launchd's minimal environment resolves it whenever `install.sh` accepted it. Install provisions the review job iff the same three-step resolution (config, then PATH, then default) finds an executable, so runtime cannot diverge from install time.
- **`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`** stops claude rewriting the tab title. The title is then renamed three times, detached and best effort, over the window in which the shell sets its own startup title. The workspace ref is cosmetic. An unparseable one skips the rename and never the launch.
- **Focus defaults to false**, so a nightly run does not pull the user out of what they are doing.
- **No cmux and no TTY is a failure.** A headless `exec claude` has no terminal to talk to, so the marker is never confirmed and every trigger retries forever. A terminal run falls back to inline, because the user is watching it. A failed create releases the claim and exits non-zero, so a scheduled job cannot think the triage happened (and a cmux that prints workspace-like text while failing cannot latch a false marker).

## Consequences

Dedup of the launch is `bin-b-review-cmux-dedup-marker.md`. `tests/review-cmux.sh` pins this path with a mock cmux.
