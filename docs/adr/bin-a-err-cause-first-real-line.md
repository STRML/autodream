# bin-a: a failure's cause is the first stderr line that is not blank, `hint:` or `warning:`, cleaned for markdown

Status: accepted · Date: 2026-11-21 · Code: `bin/err-cause.sh` (`err_cause_line`)

## Context

`run.sh` (the changelog sections) and `bin/remote-sync.sh` (the `remote_sync_<label>_cause` key) both quote a failed tool's stderr in one line. They source this file so both quote a failure the same way. git and rsync both end their output with boilerplate that says nothing about the cause, and OpenSSH prints `Warning: Permanently added ...` before the real error. CLAUDE.md, "Upstream changelog window", states the same rule.

## Decision

- The cause is the first line that is not blank, `hint:` or `warning:` (matched in any case). It is the first and not the last, because the last lines are the boilerplate.
- Backticks and angle brackets are swapped out (`` ` `` becomes `'`, `<` and `>` become parentheses), because they would open a code span or an HTML tag in the markdown L2 reads. Control characters are removed.
- The line is capped at 200 characters.

## Consequences

Changing to the last line, or letting `warning:` through, makes the section and the run-stats key quote advice or an SSH notice in place of the failure.
