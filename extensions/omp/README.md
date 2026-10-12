# autodream-focus for OMP

Tag a turn in OMP so the nightly autodream run takes a close look at it. The OMP counterpart of the Claude Code
mod in `mods/autodream-focus`, and it feeds the same `tags.jsonl`.

| | |
| --- | --- |
| `/focus` | Tag your last reply. |
| `/focus prompt` | Tag the last thing you typed. |
| `/focus pick` | Pick any prompt or reply on this branch, newest first. Checked rows are already tagged. |
| `ctrl+shift+f` | The same as `/focus`. |

Running it again on the same turn takes the tag back, and picking a checked row in `/focus pick` does the same. The
footer shows `✓ autodream focus` until the agent next runs, because the mark describes the reply you tagged and a new
run makes it a different one.

For a turn in an older session, `/resume` that session, then `/focus pick`. The tag goes into the next nightly report
as a note that names the session file, whatever day the turn was from.

There is no button on the row. OMP draws its own prompt and reply rows and lets an extension register commands and
shortcuts, set the footer and draw its own custom messages, but not decorate those rows, so a command is the closest
match.

## Install

Opt in; `install.sh` does not touch your OMP:

```bash
ln -s /path/to/cc-autodream/extensions/omp/autodream-focus.ts ~/.omp/agent/extensions/autodream-focus.ts
```

The extension does none of the writing. It calls `bin/autodream-focus.sh`, which `install.sh` links into
`~/.claude/autodream/`, so the lock, the refusal to overwrite a file it could not read and the line format are the
same as for every other harness.

| Variable | Default |
| --- | --- |
| `AUTODREAM_DIR` | `~/.claude/autodream`, where `autodream-focus.sh` and `tags.jsonl` are |
| `AUTODREAM_FOCUS_BIN` | `$AUTODREAM_DIR/autodream-focus.sh` |
| `AUTODREAM_FOCUS_KEY` | `ctrl+shift+f`; set it empty to register no shortcut |

The default is not `ctrl+alt+f` because ctrl+option chords are the usual macOS window-manager keys; on the first live
run one moved the window instead of reaching OMP. If your terminal does not pass `ctrl+shift+f` through, set
`AUTODREAM_FOCUS_KEY` (any OMP key id, such as `alt+shift+f`) or use `/focus`.

## Tests

```bash
bun test extensions/omp
```

`focus-core.test.ts` covers the logic that decides something (which turn, which action, the picker rows, the argv, where
the tags file is). `autodream-focus.test.ts` runs the extension against a fake OMP API whose `exec` runs the real
`bin/autodream-focus.sh`, so it checks the whole path from `/focus` to the line in `tags.jsonl`. It cannot check OMP's
loader, its picker or key handling. Those were checked by hand in OMP 18.3.5 under Ghostty in cmux on 2026-10-04: the
command loads, `getBranch()` is root to leaf, the picker marks tagged rows, `/resume` then `/focus pick` tags an older
session, the footer mark clears on the next run, and `ctrl+shift+f` reaches OMP. Repeat that after an OMP upgrade that
touches extensions.
