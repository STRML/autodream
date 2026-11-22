# rest: remote-sync prints exactly one status line, and exit 23 is split into partial and failed

Status: accepted · Date: 2026-11-21 · Code: `bin/remote-sync.sh` (the tail `case "$rc"`, `tool_lines`)

## Context

`run.sh` turns the helper's one line into `remote_sync_<label>` and `_cause` in run-stats. rsync's exit codes are not enough: 24 means a file vanished mid-copy, but 23 ("some files were not transferred") is also what both GNU rsync (`change_dir "..." failed`) and openrsync (`(l)stat: No such file`) return when the remote root does not exist, and that is a host with nothing to read, not a partial copy (#227, #232).

An ssh config's `Match exec` or `ProxyCommand` can print its own noise ahead of the real error (a killed `nc -z` probe prints a bash "Alarm clock" line), so the first line of stderr is not always the cause.

## Decision

Stdout is one line:

- `ok`
- `partial (<cause>)`: rsync 24, or 23 for a file it could not read
- `failed (<cause>)`: everything else, a remote root that does not exist included (23 with a `change_dir`/`link_stat ... failed: No such file` or `(l)stat: No such file` line), and 30 or 35 as `failed (timeout)`
- `invalid (<why>)`: the label or the target was refused before any ssh

Exit 0 for ok and partial, 1 for failed, 2 for invalid. rsync's whole stderr also goes to this script's stderr. The cause is the first meaningful line of rsync's stderr (ssh's own error comes first when the connection fails), cleaned like the changelog's git causes by `err_cause_line` in `bin/err-cause.sh` (`bin-a-err-cause-first-real-line`). A line from rsync or ssh (matched by `tool_lines`) wins over ssh-config noise; with none, the first line wins.

## Consequences

A new status or a changed word in these lines must be matched in `run.sh`'s reader and in the tests (`test_remote_sync_*` in `tests/run-all.sh`). Treating 23 as always partial would report a host whose projects path is wrong as healthy.
