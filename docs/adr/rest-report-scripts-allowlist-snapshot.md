# rest: report scripts run from an allowlist snapshotted before any model runs, and an entry is pinned by hash

Status: accepted · Date: 2026-11-22 · Code: `bin/report-scripts.sh` (`snapshot`, `entry_hash`, `hash_of`, `collect`), `bin/run.sh` (`report_collector_fingerprint`, `report_output_fingerprint`); CLAUDE.md "Report scripts"

## Context

Operator notes kept asking the nightly run to "run X and quote the rows". L2 holds Read and Glob only, so it could not, and the ask failed without a word. `report-scripts.sh` runs the commands before L2 and writes each result to `<findings-dir>/report-<name>.md`, so a new report is one line in `$AUTODREAM_DIR/report-scripts.conf` and never a change to `run.sh` or the prompt.

The conf is code that runs with the operator's privileges. An L1 worker reads untrusted transcripts and holds the Write tool, so a worker that rewrote the conf, or a script the conf names, would get that code run by the next collect. The preflight review of PR 233 found this.

## Decision

- **Only the operator edits the conf.** An operator note (which can come from a phone or a transcript) never reaches it, so a note cannot widen what runs. Args are literal words split on whitespace: no quotes, no `$VAR`, no glob (`set -f`), no `;`, no `eval`. A missing conf is "no reports", never an error.
- **The allowlist is snapshotted before any model runs.** `run.sh` calls `snapshot` before the first model call and keeps the output in memory. The snapshot is `#present` or `#absent`, then `<hash or ->` TAB `<conf line>` per entry. `collect` is handed it back and runs only what it lists. A script whose hash differs now, or that did not exist when the snapshot was taken, gets status `changed` and is not executed. A snapshot that failed reads `#unavailable` and runs nothing, and the index says so rather than saying none is configured. An unreadable snapshot has no first line, so its state is empty and reads as unavailable.
- **A manual `collect` has no snapshot.** It reads the conf now and checks nothing (`checked=0`), because nothing has run since the operator wrote it. A conf that exists and cannot be read is `#unavailable`, not "none configured".
- **What the hash covers.** The file named as the entry's path, and every argument that is an existing file at snapshot time: `name /bin/bash ~/x.sh` pins bash and `x.sh` together as one sha256 over the script hash and each file's path and hash. A relative argument is looked up from HOME, where the command runs. An argument file that appears after the snapshot is also `changed`.
- **The comparison fails closed.** A script runs only when the snapshot's hash and the current hash are both real 64-hex sha256 values and equal. A `-` on both sides (the hash failed twice) must never read as "unchanged".
- **Names are compared ignoring case.** `Foo` and `foo` are one file on APFS (`report-<name>.md`), so the second is `invalid` as a duplicate.
- **The collector and what a worker can still reach.** `run.sh` fingerprints `report-scripts.sh` and the `portable.sh` it sources before the snapshot and checks again before `collect`, and runs `collect` right after the snapshot (before any worker). `report_output_fingerprint` then hashes the index and every report file, and L2 gets an `unavailable` index if one changed.

## Consequences

Not covered: anything a script sources, reads or runs on its own. The residual exists only for workers that are not confined (an engine whose adapter has no `l1-writes` profile, a host whose sandbox probe says no, or `AUTODREAM_L1_CONFINE=0`). A conf entry or script such a worker plants on night N is snapshotted as trusted on night N+1, because nothing tells a planted line from one the operator wrote, and a snapshot cannot protect a trust anchor the worker can also write. It closes for an engine once its adapter declares a write profile and `l1_confined_<engine>` reads `yes` (issue 169; PR 241 and 246 for claude and omp). The header this replaces said both gaps close when workers cannot write outside their staging dir. That is now true on a host whose probe passes, so check `l1_confined` before relying on it.

Before changing the snapshot format, grep `run.sh` for its readers: it passes the snapshot through a temp file, and the `report-index.txt` statuses (`changed`, `invalid`) are read by `report_scripts_stats` and PROMPT.md.
