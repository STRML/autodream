# bin-a: the command that opens the inbox file is a shell snippet, defaulting to plain `open`

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (`OPEN_CMD`, the final `sh -c`, the inbox heredoc)

## Context

The tool ships with a LICENSE and an install script, so the out-of-the-box path cannot assume one particular editor is installed. An editor that needs flags ("code -g", "open -a Obsidian") should work without a wrapper script. `SUBL` was the earlier knob, and setups that predate `AUTODREAM_OPEN` must keep working untouched.

The inbox file is `.md` and the default opener hands it to a markdown app, so a `#`-prefixed comment block at the top reads fine in a plain-text editor but renders as a stack of H1s with stray `#` lines.

## Decision

- `OPEN_CMD` is `${AUTODREAM_OPEN:-${SUBL:-open}}`. `SUBL` is a deprecated alias that is still honored. The default `open` hands the file to whatever the Mac already opens `.md` with.
- It runs through `sh -c "$OPEN_CMD \"\$1\""` with the file passed as a positional argument. `sh -c` word-splits a multi-word command while the path stays one argument whatever it contains. The banner's `-execute` string uses the same command.
- The inbox file's header is real markdown: one title, plain lines, a rule.

## Consequences

Do not quote `$OPEN_CMD` as a single word, and do not interpolate the path into the `sh -c` string. A failed open is reported and never fails the run.
