# runsh: The remote mirror is an archive and its size is measured every night

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`remote_mirror_size`, `remote_sync_job`, `remote_sync_finish`)

## Context
Nothing prunes a mirror (#228): `remote-sync.sh` never passes `--delete`, so a pruned file still on the host would be copied back. Disk is the only cost, so the growth is watched instead.

## Decision
`remote_mirror_size` prints `<files> <bytes>` of the `*.jsonl` transcripts in a mirror: `0 0` before a first good sync. `wc -c` prints a `total` line per batch, which a transcript cannot match because its name ends in `.jsonl`, so the awk skips a two-field `total` row. A walk or count that fails (an unreadable subdirectory, a file gone mid-count) prints `unknown unknown`, because totals from whatever did get counted would read as a measured size. A newline in a path would split `wc`'s line for it into two records, so a path containing one is also `unknown unknown`. The size is measured in the background sync job (it leaves it in `<prefix>.mirror`); `remote_sync_finish` measures it itself if the file is empty, and writes `remote_mirror_files_<label>` and `remote_mirror_bytes_<label>` into run-stats and counts unknown mirrors in `REMOTE_MIRROR_UNKNOWN`.

See CLAUDE.md, "Remote hosts" (The mirror is an archive, and its size is measured (#228)).

## Consequences
Revisit pruning only when the run-stats numbers say the disk matters, and then a prune needs an rsync exclude for what it removed, not just a delete.
