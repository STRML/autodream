# rest: remote-sync pulls *.jsonl one way with rsync over ssh into a mirror that is never pruned

Status: accepted · Date: 2026-11-21 · Code: `bin/remote-sync.sh`

## Context

Sessions on another host (#226) have to reach the nightly corpus. A network mount was rejected: it puts every live session's appends on a filesystem that drops whenever the laptop sleeps or the host reboots. A pull is read-only on the remote and needs only sshd there (CLAUDE.md, "Remote hosts: a one-way pull"; runner side `runsh-remote-roots-one-way-pull`).

## Decision

`remote-sync.sh <label> <ssh-target:path> <mirror-dir>` runs `rsync -rt --timeout=60` over ssh and asks for `*.jsonl` only (transcripts and subagent sidecars: `--include='*/' --include='*.jsonl' --exclude='*' --prune-empty-dirs`).

- `-t` keeps mtimes, because enumeration's lower bound is the file mtime.
- It never passes `--delete`. A transcript removed on the remote stays in the mirror, which is an archive nothing prunes: a file pruned out of the mirror and still on the host would be copied back (#228).
- rsync writes each file to a dot-named temp and renames it, so a copy killed mid-file leaves the old file whole plus a `.name.jsonl.XXXXXX` temp, which is not `*.jsonl` and is never enumerated.
- ssh runs with `BatchMode=yes` (no password or passphrase prompt, which under launchd would hang the night), `ConnectTimeout=10` (bounds a host that is asleep), and `ServerAliveInterval=15` and `ServerAliveCountMax=2` with rsync's `--timeout` (bound a stalled copy).
- Only the mirror's parent is made. rsync makes the mirror itself, so a first sync that fails leaves no empty mirror for the run to scan.

## Consequences

Disk is the only cost of the archive; the size is measured nightly (`runsh-remote-mirror-size-measured`). A prune would need an rsync exclude for what it removed, not just a delete. Do not add `--delete` or move the `mkdir` to the mirror itself.
