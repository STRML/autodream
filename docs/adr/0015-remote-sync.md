# 0015: Remote host sync

Status: accepted · Governs: `bin/remote-sync.sh`, `bin/run.sh`

This record holds 12 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Remote hosts: a one-way pull, not a shared filesystem (#226)](#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226)
- [remote-sync refuses a bad label, host or path before any ssh, and uses builtins until then](#remote-sync-refuses-a-bad-label-host-or-path-before-any-ssh-and-uses-builtins-until-then)
- [remote-sync pulls *.jsonl one way with rsync over ssh into a mirror that is never pruned](#remote-sync-pulls-jsonl-one-way-with-rsync-over-ssh-into-a-mirror-that-is-never-pruned)
- [remote-sync prints exactly one status line, and exit 23 is split into partial and failed](#remote-sync-prints-exactly-one-status-line-and-exit-23-is-split-into-partial-and-failed)
- [The remote mirror is an archive and its size is measured every night](#the-remote-mirror-is-an-archive-and-its-size-is-measured-every-night)
- [Remote session roots are a one-way pull into local mirrors, never a mount](#remote-session-roots-are-a-one-way-pull-into-local-mirrors-never-a-mount)
- [A report carries a record of the hosts it did not fully read, so later nights can name the gap](#a-report-carries-a-record-of-the-hosts-it-did-not-fully-read-so-later-nights-can-name-the-gap)
- [a remote-short record line inside L2's body is dropped; only the runner writes it](#a-remote-short-record-line-inside-l2s-body-is-dropped-only-the-runner-writes-it)
- [A banner fires only when every remote host failed](#a-banner-fires-only-when-every-remote-host-failed)
- [Remote entries are validated before any ssh, and reserved labels are refused](#remote-entries-are-validated-before-any-ssh-and-reserved-labels-are-refused)
- [Hosts sync in parallel background jobs, and results are read in config order](#hosts-sync-in-parallel-background-jobs-and-results-are-read-in-config-order)
- [A held mirror lock is waited for, then the run syncs itself](#a-held-mirror-lock-is-waited-for-then-the-run-syncs-itself)

## Background: Remote hosts: a one-way pull, not a shared filesystem (#226)

This section was moved here from the former CLAUDE.md. Its original title: "Remote hosts: a one-way pull, not a shared filesystem (#226)".

Sessions also run on a Studio (headless, under herdr), and a Claude session there writes to the
Studio's own `~/.claude/projects`. Without a sync that work drops out of the report with no warning,
the same blackout as 2026-08-03..06. A network mount was rejected: it puts every live session's
appends on a filesystem that drops whenever the laptop sleeps or the Studio reboots for an update.
A pull is read-only on the remote and needs only sshd there.

- **Config.** `AUTODREAM_REMOTE_ROOTS` holds space-separated `label=ssh-target:path` entries, for
  example `studio2=studio2:.claude/projects` (the path is relative to the remote home). Unset means
  off, and a run then differs from one without the feature by the single `remote_sync: off` line.
- **`bin/remote-sync.sh <label> <target:path> <mirror>`** runs `rsync -rt --timeout=60` over
  `ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2`,
  asks for `*.jsonl` only (`--include='*/' --include='*.jsonl' --exclude='*' --prune-empty-dirs`),
  and never passes `--delete`. `-t` matters: enumeration's lower bound is the mtime. It prints one
  line: `ok`, `partial (<cause>)`, `failed (<cause>)` or `invalid (<why>)`. The cause comes from
  `err_cause_line` in `bin/err-cause.sh`, the cleaner the changelog sections use too.
- **Exit 23 is split.** rsync 24 (a file vanished) is partial. 23 is partial too, except that both
  GNU rsync (`change_dir "…" failed`) and openrsync (`(l)stat: No such file`) also return 23 when
  the remote root does not exist, and that is a host with nothing to read, so it is `failed`.
- **Validation before ssh.** run.sh refuses a label outside `[A-Za-z0-9._-]+`, `.`, `..`, a
  repeated label, and a reserved one: `invalid`, or any name ending in `_cause` or `_last_ok`.
  Run-stats builds `remote_sync_<label>`, `remote_sync_<label>_cause`, `remote_sync_<label>_last_ok`
  and the refusal key `remote_sync_invalid` by concatenation, so without that rule a host called
  `studio_cause` prints like `studio`'s cause line and no reader can tell them apart (four review
  rounds on the short-dates scan, 2026-11-21). A refused entry takes the key `invalid`, with the
  label in its cause. The helper refuses a host or path that starts with `-` (ssh would read it as an
  option) or holds a character outside the set a projects path needs, because openrsync does not
  quote the path for the remote shell. The mirrors are claude roots, so with the claude adapter not
  enabled every entry is refused as `invalid` (and the all-failed banner fires) rather than synced
  and reported `ok` while nothing scans it.
- **Where it runs.** `sync_remote_roots` sits below the idempotency guard and the run lock, so a
  catch-up trigger never reaches ssh, and above enumeration. It sets globals and is never called
  inside `$(...)`. Every mirror that exists (`$AUTODREAM_DIR/remote/<label>/projects`, synced this
  run or kept from an earlier one) is appended to `SESSION_ROOTS`, including an explicit
  `SESSION_ROOTS`. The helper makes only the mirror's parent and rsync makes the mirror, so a
  first sync that fails leaves no empty mirror in the roots. The mirror is not under
  `$HOME/.claude*`, so root-probe never reports it as an unasked folder.
- **Lock.** `$AUTODREAM_DIR/locks/remote-<label>.lock` uses the run lock's helpers
  (`acquire_lock` and `release_lock`, each taking the lock dir), so the flock on
  `remote-<label>.flock` decides and a dead holder frees it with no reclaim (ADR 0001, "One run per
  date at a time"). The nightly and an `autodream-now.sh` run for another date take different run
  locks and would otherwise rsync into one directory at once. A live holder
  is waited for (`AUTODREAM_REMOTE_LOCK_WAIT`, default 600 seconds) and the run then syncs itself,
  because scanning a mirror mid-copy misses the files not yet renamed into place, and the next
  day's mtime bound never picks them up. A holder still alive after the wait gives
  `skipped_locked`, and the mirror is scanned as it stands. A lock that cannot be taken at all
  (read-only locks directory, no python3) gives `failed (cannot take the lock ...)`.
- **Reporting.** run-stats gets `remote_sync: off|on` and, per label, `remote_sync_<label>`
  (`ok|partial|failed|skipped_locked|invalid`), `remote_sync_<label>_cause` and
  `remote_sync_<label>_last_ok` (stamped in `remote/<label>/last-ok` on ok and partial, else
  `never`). Every run-stats block carries them, the fatal one included. PROMPT.md's self-audit names every label that is not
  `ok`. When every entry failed or was invalid, `notify.sh --warning` posts one banner in its own
  `remote-sync` group, so it cannot replace the changelog warning. A failure never defers the date
  (a down Studio is not a down model provider) and never aborts the run. On a night with no
  sessions, any host that is not `ok` (failed, invalid, partial or skipped_locked) makes the stub
  report say the host was not fully synced instead of calling the night empty.
- **What a failed host loses, and how it is named later (#230).** A finished report stops every
  later trigger at the guard, so nothing syncs that date again, and the next night's mtime lower
  bound skips a transcript last written on the failed day. Those sessions reach no report unless the
  date is rebuilt (`autodream-now.sh <date> --force`). Nothing rebuilds on its own: a rebuild
  replaces the report, including any `## Triage decisions` the user wrote into it, and a sync above
  the guard would rerun L2 on every trigger while a host stays down. What happens instead is
  `remote_short_scan`, run at the end of `sync_remote_roots`. For each label whose sync was `ok` or
  `partial` tonight it reads the seven days before the target date and writes
  `remote_short_dates_<label>: <dates>` (oldest first, `none` when empty). PROMPT.md turns each into
  a self-audit line and one open question titled `Rebuild the report dates missing <label>
  sessions?` (a stable title per label, so the streak escalation applies). A night with nothing to
  triage skips L2, so the stub report carries the same question inside its sentinels with the marker
  counting it (a "None" and a zero would read to `question-streaks.sh` as the question resolved),
  plus a line when the scan itself could not read a night, or a mirror could not be measured.
  - **The record is a line inside the report**, `<!-- autodream:remote-short=a,b -->` (the labels the
    report did not fully read, empty when none), written by `remote_short_line` inside the same
    atomic write as the report body (the L2 writer's `tmp` plus `mv`, and the stub, which is written
    to `<report>.tmp` and published with one `mv` after its status is checked). One
    file, so the record and the report cannot disagree: a run killed before it publishes, a rebuild
    that defers and a write that fails all leave the old report with its old record. This replaced a
    `remote-short.txt` beside the report, which took four review rounds because two files have an
    order of writes to get wrong (the same lesson as `question-streaks.sh`); the scan reads
    `$DREAMS_DIR/<date>.md` and nothing under `findings/`.
  - **What a report did not fully read** (`remote_short_labels`): every configured label whose sync
    was not `ok` (`partial` included: rsync 23 can leave a file uncopied, and the next sync copies it
    with an old mtime that the next day's lower bound skips); every configured label when the
    enumeration was incomplete (`ROOTS_FAILED`, `ROOTS_UNAVAILABLE` or `PARTIAL_ROOTS` above zero),
    because a failed root cannot be told apart from a mirror; and every label in the record of the
    report this run replaces that this run does not configure (`REMOTE_PREV_SHORT`, read before
    anything moves the old report: the report at the path if it carries a record, else the newest
    moved-aside `.stale-<epoch>` copy that does, because a rebuild killed mid-L2 can leave a
    record-less capture at the path. A copy cannot resurface an old label: a delivered report, L2 or
    stub, takes every copy it supersedes out of the `.stale-*` glob (`drop_stale_report_copies`: a
    copy holding a `## Triage decisions` heading is renamed to `<report>.triaged-<epoch>`, because it
    holds the user's own writing, and every other copy is deleted), so a copy still in the glob
    means nothing has been delivered since and a `.triaged-*` copy is never read by the lookup), so a rebuild with fewer
    hosts cannot erase it, including across the retry of a failed rebuild. With remote sync
    off the line is still written when the replaced report had one to keep.
  - **No migration.** A report with no record line was written with remote sync off or before the
    record existed, and the scan skips it. Nights since #227 shipped were already named by that
    night's own self-audit line, so detection for them was not worth a fallback to run-stats, which
    a rebuild rewrites before L2 runs.
  - **Refusals and reserved labels**: a malformed, repeated or reserved entry has no label of its
    own and takes the run-stats key `invalid`, so only real labels join the record (an entry refused
    because the claude adapter is off does, under its own label).
  - A label still failing tonight lists nothing (the host is down, and the banner covers it); only
    labels configured tonight are listed, so a renamed or removed host lists nothing; a night with a
    findings dir and no report (a rebuild that died in L2 moved the old report aside, and the next
    trigger rebuilds it), a report that will not read, or a date that will not compute is counted in
    `remote_short_scan_unreadable` (a night with no findings dir and no report did not run, and is
    not counted). Each report is read once into memory, so a read error is counted and never reads as
    "no match".
- **Hosts sync in parallel (#229).** `sync_remote_roots` validates every entry first, starts one
  `remote_sync_job` per valid label in the background, then reads the results in config order. Each
  label has its own lock and mirror, so the jobs share nothing, and with several hosts down the
  `ConnectTimeout` and `--timeout` waits overlap instead of adding up. A job cannot set the parent's
  variables, so it leaves `<label>.status`, `.secs` and `.mirror` in a per-run job dir,
  `$AUTODREAM_DIR/remote-jobs/<run pid>`, removed with `rm -rf` after the results are read. It is
  under the install and not in `$TMPDIR` because a run killed while it waits skips every cleanup:
  the next run removes the dirs of dead pids there and never a live one's. A job that dies before
  writing reads `failed (remote-sync.sh printed nothing)`; if the job dir cannot be made, no job
  starts and every valid entry reads `failed (cannot make a job dir for the sync jobs)`, and an
  empty job-dir path is never joined to a result name, so nothing at `/0.status` can be read as a
  result. Run-stats lines, `SESSION_ROOTS` and the refusal warnings are
  written in the second pass, in the order of `AUTODREAM_REMOTE_ROOTS`, so a refused entry keeps its
  place and the artifact does not depend on which host answered first. `bin/remote-sync.sh` is
  unchanged.
- **The mirror is an archive, and its size is measured (#228).** Nothing prunes a mirror.
  `remote-sync.sh` never passes `--delete`, so a file pruned out of the mirror and still on the host
  would be copied back the next night, and the mirror keeps transcripts the remote deleted on purpose.
  Disk is the only cost: the nightly `find` drops old files by the mtime bound cheaply. Every run
  writes `remote_mirror_files_<label>` and `remote_mirror_bytes_<label>` (the `*.jsonl` count and
  byte sum, `0` and `0` before a first good sync, `unknown` and `unknown` when the walk or the count
  failed (an unreadable subdirectory, a file gone mid-count, a newline in a path), so a partial total never reads as a
  measured size, nothing for a refused entry), measured in the
  background job, so the month of growth the retention question wanted accrues in the run-stats
  files without anyone remembering to look. Revisit pruning only when those numbers say the disk
  matters, and then a prune needs an rsync exclude for what it removed, not just a delete.
- **A killed copy.** rsync writes each file to a dot-named temp (`.name.jsonl.XXXXXX`) and renames
  it, so a file is old or new, never torn by rsync, and a stranded temp is not `*.jsonl`. A file
  copied while the remote session was appending can end in a torn line; session-window and the
  stats tolerate it, and the next night copies the whole file.
- **Known double triage.** A session resumed on the Studio from a laptop transcript has the same
  session id in both trees, and both copies are enumerated (different paths, so different hashes).
  The day cut keeps only each copy's records inside the day, so on the day the session moved, the
  part written before the move is triaged twice. Deduping across trees is out of scope (#226).
- **Tests.** The `test_remote_sync_*` cases in `tests/run-all.sh` put a fake `rsync` (logs argv,
  copies `*.jsonl` with `cp -p`, exits with a per-host code and stderr, logs start and end epochs to
  `rsync.times`, and sleeps (`rsync.<host>.delay`) or SIGKILLs its helper (`rsync.<host>.kill`) on request;
  the parallel test asserts the two hosts' intervals overlap rather than timing the run) and a logging `ssh` that
  always fails first on PATH, and every target is a `*.invalid` host. The missing-tool case runs
  the helper with a PATH that holds no rsync, because run.sh appends `/usr/bin` to PATH.
  `install.sh` resolves `rsync` into the plist PATH beside claude, git and bash.

## remote-sync refuses a bad label, host or path before any ssh, and uses builtins until then

Status: accepted · Date: 2026-11-21 · Code: `bin/remote-sync.sh` (argument checks, `usage_invalid`)

### Context

The label names a directory under `remote/` and a lock, so a label with a slash, a dot-only name or an odd character could write outside the mirror root. A host that starts with `-` would reach ssh as an option. The path reaches the remote shell, and openrsync does not quote it, so a character outside what a projects path needs could be interpreted there. The runner validates its own config the same way (`docs/adr/0015-remote-sync.md#remote-entries-are-validated-before-any-ssh-and-reserved-labels-are-refused`); the helper repeats the checks because it is also run alone.

### Decision

Before any ssh or rsync the helper refuses, with `invalid (<why>)` and exit 2: a wrong argument count, a label outside `[A-Za-z0-9._-]+` or equal to `.` or `..`, a target with no `:`, a host that is empty, starts with `-` or holds a character outside `[A-Za-z0-9._@-]`, a path that is empty, starts with `-` or holds a character outside `[A-Za-z0-9._/~+-]`, and an empty mirror. Everything up to the `command -v` checks uses builtins only, so a PATH without rsync or ssh is reported (`failed (rsync not found)`, `failed (ssh not found)`) and not crashed on.

### Consequences

Widening the path character set widens what openrsync hands the remote shell. A missing `err-cause.sh` beside the script (looked up through the symlink `install.sh` makes) is `failed (err-cause.sh not found beside remote-sync.sh)`, not a crash (`docs/adr/0023-install-and-scheduling.md#an-installed-script-finds-a-newer-helper-through-its-own-symlink-target`).

## remote-sync pulls *.jsonl one way with rsync over ssh into a mirror that is never pruned

Status: accepted · Date: 2026-11-21 · Code: `bin/remote-sync.sh`

### Context

Sessions on another host (#226) have to reach the nightly corpus. A network mount was rejected: it puts every live session's appends on a filesystem that drops whenever the laptop sleeps or the host reboots. A pull is read-only on the remote and needs only sshd there (docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts: a one-way pull"; runner side `docs/adr/0015-remote-sync.md#remote-session-roots-are-a-one-way-pull-into-local-mirrors-never-a-mount`).

### Decision

`remote-sync.sh <label> <ssh-target:path> <mirror-dir>` runs `rsync -rt --timeout=60` over ssh and asks for `*.jsonl` only (transcripts and subagent sidecars: `--include='*/' --include='*.jsonl' --exclude='*' --prune-empty-dirs`).

- `-t` keeps mtimes, because enumeration's lower bound is the file mtime.
- It never passes `--delete`. A transcript removed on the remote stays in the mirror, which is an archive nothing prunes: a file pruned out of the mirror and still on the host would be copied back (#228).
- rsync writes each file to a dot-named temp and renames it, so a copy killed mid-file leaves the old file whole plus a `.name.jsonl.XXXXXX` temp, which is not `*.jsonl` and is never enumerated.
- ssh runs with `BatchMode=yes` (no password or passphrase prompt, which under launchd would hang the night), `ConnectTimeout=10` (bounds a host that is asleep), and `ServerAliveInterval=15` and `ServerAliveCountMax=2` with rsync's `--timeout` (bound a stalled copy).
- Only the mirror's parent is made. rsync makes the mirror itself, so a first sync that fails leaves no empty mirror for the run to scan.

### Consequences

Disk is the only cost of the archive; the size is measured nightly (`docs/adr/0015-remote-sync.md#the-remote-mirror-is-an-archive-and-its-size-is-measured-every-night`). A prune would need an rsync exclude for what it removed, not just a delete. Do not add `--delete` or move the `mkdir` to the mirror itself.

## remote-sync prints exactly one status line, and exit 23 is split into partial and failed

Status: accepted · Date: 2026-11-21 · Code: `bin/remote-sync.sh` (the tail `case "$rc"`, `tool_lines`)

### Context

`run.sh` turns the helper's one line into `remote_sync_<label>` and `_cause` in run-stats. rsync's exit codes are not enough: 24 means a file vanished mid-copy, but 23 ("some files were not transferred") is also what both GNU rsync (`change_dir "..." failed`) and openrsync (`(l)stat: No such file`) return when the remote root does not exist, and that is a host with nothing to read, not a partial copy (#227, #232).

An ssh config's `Match exec` or `ProxyCommand` can print its own noise ahead of the real error (a killed `nc -z` probe prints a bash "Alarm clock" line), so the first line of stderr is not always the cause.

### Decision

Stdout is one line:

- `ok`
- `partial (<cause>)`: rsync 24, or 23 for a file it could not read
- `failed (<cause>)`: everything else, a remote root that does not exist included (23 with a `change_dir`/`link_stat ... failed: No such file` or `(l)stat: No such file` line), and 30 or 35 as `failed (timeout)`
- `invalid (<why>)`: the label or the target was refused before any ssh

Exit 0 for ok and partial, 1 for failed, 2 for invalid. rsync's whole stderr also goes to this script's stderr. The cause is the first meaningful line of rsync's stderr (ssh's own error comes first when the connection fails), cleaned like the changelog's git causes by `err_cause_line` in `bin/err-cause.sh` (`docs/adr/0008-failure-and-network.md#a-failures-cause-is-the-first-stderr-line-that-is-not-blank-hint-or-warning-cleaned-for-markdown`). A line from rsync or ssh (matched by `tool_lines`) wins over ssh-config noise; with none, the first line wins.

### Consequences

A new status or a changed word in these lines must be matched in `run.sh`'s reader and in the tests (`test_remote_sync_*` in `tests/run-all.sh`). Treating 23 as always partial would report a host whose projects path is wrong as healthy.

## The remote mirror is an archive and its size is measured every night

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`remote_mirror_size`, `remote_sync_job`, `remote_sync_finish`)

### Context
Nothing prunes a mirror (#228): `remote-sync.sh` never passes `--delete`, so a pruned file still on the host would be copied back. Disk is the only cost, so the growth is watched instead.

### Decision
`remote_mirror_size` prints `<files> <bytes>` of the `*.jsonl` transcripts in a mirror: `0 0` before a first good sync. `wc -c` prints a `total` line per batch, which a transcript cannot match because its name ends in `.jsonl`, so the awk skips a two-field `total` row. A walk or count that fails (an unreadable subdirectory, a file gone mid-count) prints `unknown unknown`, because totals from whatever did get counted would read as a measured size. A newline in a path would split `wc`'s line for it into two records, so a path containing one is also `unknown unknown`. The size is measured in the background sync job (it leaves it in `<prefix>.mirror`); `remote_sync_finish` measures it itself if the file is empty, and writes `remote_mirror_files_<label>` and `remote_mirror_bytes_<label>` into run-stats and counts unknown mirrors in `REMOTE_MIRROR_UNKNOWN`.

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (The mirror is an archive, and its size is measured (#228)).

### Consequences
Revisit pruning only when the run-stats numbers say the disk matters, and then a prune needs an rsync exclude for what it removed, not just a delete.

## Remote session roots are a one-way pull into local mirrors, never a mount

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sync_remote_roots`, `remote_sync_stat` and the `REMOTE_*` globals)

### Context
Sessions also run on other hosts (#226). Without a sync that work drops out of the report with no warning.

### Decision
`AUTODREAM_REMOTE_ROOTS` names hosts as space-separated `label=ssh-target:path` entries. Each is pulled one way by `remote-sync.sh` into `$AUTODREAM_DIR/remote/<label>/projects`, and every mirror that exists, synced this run or kept from an earlier one, joins `SESSION_ROOTS` for the claude adapter. `sync_remote_roots` runs below the idempotency guard (a catch-up trigger never reaches ssh) and above enumeration. A failed host never defers the date and never stops the run: it is a line in `run-stats.txt`, and a banner when every host failed. Results go to globals (`REMOTE_SYNC_LINES` and friends), not stdout, so the function is called directly and never inside `$(...)`, which would lose them.

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts: a one-way pull, not a shared filesystem (#226)".

### Consequences
Do not call `sync_remote_roots` in a command substitution. Related decisions: `remote-sync-entry-validation`, `remote-sync-parallel-jobs`, `remote-sync-waits-for-held-mirror`, `remote-mirror-size-measured`, `remote-short-dates-record-in-report`, `remote-sync-all-failed-banner`.

## A report carries a record of the hosts it did not fully read, so later nights can name the gap

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`remote_short_scan`, `remote_short_line`, `remote_short_labels`, `remote_report_record`, `sync_remote_roots`, `REMOTE_PREV_SHORT`)

### Context
A finished report stops every later trigger at the guard, and the next night's mtime lower bound skips a transcript last written on the failed day, so a date whose host was down is never retried (#230). Rebuilding it replaces a report the user may have triaged, so nothing rebuilds on its own. An earlier design kept the record in a second file and spent four review rounds on the orders in which the two could diverge.

### Decision
The record is one line inside the report, `<!-- autodream:remote-short=a,b -->`: the labels that report did not fully read, empty when none. `remote_short_line` is called by the L2 writer and the stub inside the same atomic write as the report body, so the record and the report are one file and cannot disagree. A run killed before it publishes, a rebuild that defers, and a write that fails all leave the old report with its old record. A report with no such line was written with remote sync off (or before the record existed) and is skipped. With remote sync off, `remote_short_line` still writes the line when the report being replaced carried a record to keep, and writes nothing otherwise.

A run whose sync worked looks back `REMOTE_SHORT_SCAN_DAYS` (7) days and, per label that synced `ok` or `partial`, writes `remote_short_dates_<label>` (`none` when empty) plus an open question with the rebuild command (`autodream-now.sh <date> --force`). The question warns that a rebuild replaces that date's report, including any `## Triage decisions` already written into it, so a date already triaged should be left alone. A night with a findings dir and no report (a rebuild that failed in L2 moved the old one aside, and the next trigger rebuilds it), a report that will not read, or a date that will not compute is counted in `remote_short_scan_unreadable`. Only labels configured tonight are listed.

What a report did not fully read (`remote_short_labels`): every configured label whose sync was not `ok` (partial counts: rsync 23 can leave a file uncopied, which the next sync copies with an old mtime that the next day's lower bound skips); every configured label when the enumeration was incomplete (`ROOTS_FAILED`, `ROOTS_UNAVAILABLE`, `PARTIAL_ROOTS` above zero), because the roots that failed cannot be told apart from a mirror; and every label the replaced report listed that this run does not configure (`REMOTE_PREV_SHORT`), so a rebuild with fewer hosts cannot erase them.

`REMOTE_PREV_SHORT` is the record of the report at the path if it carries one, else of the newest moved-aside `.stale-<epoch>` copy that does: a rebuild that died in L2 moved the real report aside and may have left a record-less capture at the path. A copy cannot resurface an old label, because a delivered report removes every copy it supersedes (see `drop-stale-report-copies-keep-triage-decisions`).

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (What a failed host loses, and how it is named later (#230)).

### Consequences
Do not move the record into a second file. The stub report must carry the same question inside its sentinels.

## a remote-short record line inside L2's body is dropped; only the runner writes it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: the `awk '!/^<!-- autodream:remote-short=.* -->$/'` filter and `remote_short_line`)

### Context
Only the runner states which hosts a report did not read, and the short-dates scan takes the last record line it finds. A record line the model wrote into its own body could become a date's record when remote sync was off and the runner wrote none.

### Decision
The staged report is the model's body with any record-shaped line removed, followed by the runner's `remote_short_line` (which prints nothing when `AUTODREAM_REMOTE_ROOTS` is empty and the replaced report carried no record), in one `.tmp` and one `mv`. See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (what a failed host loses, "The record is a line inside the report").

### Consequences
Do not trust a record line from the body. Keep the record and the body in one atomic write; two files have an order of writes to get wrong.

## A banner fires only when every remote host failed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (end of `sync_remote_roots`)

### Context
Every host failing is a broken path (lost key, renamed host, no route), and the per-host lines sit in `run-stats.txt` until the report, so it needs a louder signal. One host failing, or a host another run is syncing, is not a path failure.

### Decision
When `REMOTE_SYNC_BAD` equals `REMOTE_SYNC_TOTAL` (and the total is above zero), `notify.sh --warning` posts one banner in its own `remote-sync` group naming the first failure. `REMOTE_SYNC_BAD` counts only `failed` and `invalid` hosts, so `skipped_locked` and `partial` do not count. The banner is a warning, in its own group, so it cannot replace the changelog warning. With no executable `$AUTODREAM_DIR/notify.sh` there is no banner, and a failure of the notify call is logged and ignored. `REMOTE_SYNC_BAD` also counts refused entries, since a refusal is an `invalid` host.

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (Reporting).

### Consequences
A failure never defers the date and never aborts the run.

## Remote entries are validated before any ssh, and reserved labels are refused

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`remote_sync_refuse`, pass 1 of `sync_remote_roots`)

### Context
Run-stats builds `remote_sync_<label>`, `remote_sync_<label>_cause`, `remote_sync_<label>_last_ok` and the refusal key `remote_sync_invalid` by concatenation. A host called `invalid`, or one ending in `_cause` or `_last_ok`, would print like another run-stats line, and no reader could tell the two apart (four review rounds on the short-dates scan, 2026-11-21).

The mirrors are claude roots. With the claude adapter not enabled nothing would scan them, and a sync reported `ok` would hide a whole host's missing sessions.

### Decision
Pass 1 refuses, before any ssh: an entry with no `label=target`, a label outside `[A-Za-z0-9._-]+` (including `.` and `..`), a reserved label (`invalid`, `*_cause`, `*_last_ok`), a repeated label, and, when the claude adapter is not in `ENABLED_ADAPTERS`, every entry. The reserved check sits ahead of the adapter check so a reserved label never gets a key of its own. A refusal takes the synthetic key `invalid` (so it never joins the short list), except an entry refused only because the adapter is off, which has a real label and is passed `real` so `remote_sync_refuse` adds it to `REMOTE_SHORT_LABELS`. Each refusal counts toward `REMOTE_SYNC_BAD` and `REMOTE_SYNC_SHORT` and logs a WARNING.

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (Validation before ssh).

### Consequences
A new run-stats suffix per label must also be added to the reserved-label `case` pattern in pass 1, or a host named like it prints as another line. `tests/run-all.sh` pins this with `test_remote_sync_reserved_labels_are_refused` and `test_remote_sync_refused_when_the_claude_adapter_is_off`.

## Hosts sync in parallel background jobs, and results are read in config order

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sync_remote_roots` passes 1 and 2, `remote_sync_job`, `remote_sync_finish`)

### Context
A host that is asleep costs `ConnectTimeout` and a stalled copy costs rsync's `--timeout`, so with several hosts down the waits added up (#229).

### Decision
Pass 1 validates every entry and starts one `remote_sync_job` per valid label in the background, so the waits overlap. Each label has its own lock and mirror, so the jobs share nothing, and `$$` is still this run's pid inside a job, so the lock it takes is this run's. A job cannot set the parent's variables, so it leaves `<prefix>.status`, `.secs` and `.mirror` in a per-run job dir. That dir is `$AUTODREAM_DIR/remote-jobs/<run pid>`, under the install and not in `$TMPDIR`: a run killed while it waits skips every cleanup, so the next run removes the dirs of dead pids there and never a live one's (a name is only ever this run's pid or an earlier run's). The dir is removed with `rm -rf` after the results are read. A job that dies before writing reads `failed (remote-sync.sh printed nothing)`. If the dir cannot be made no job starts and every valid entry reads `failed (cannot make a job dir for the sync jobs)`. `remote_sync_finish` is given an empty prefix in that case and reads nothing, so a failed job-dir allocation never turns into a read of `/0.status`. Pass 2 reads the results in `AUTODREAM_REMOTE_ROOTS` order, so run-stats and `SESSION_ROOTS` do not depend on which host answered first, and a refused entry keeps its place.

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (Hosts sync in parallel (#229)).

### Consequences
Never add a variable assignment to the job body expecting the parent to see it. `bin/remote-sync.sh` itself is unchanged by this.

## A held mirror lock is waited for, then the run syncs itself

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`acquire_lock`, `remote_sync_locked`)

### Context
A run that scanned a mirror another run was still copying into would miss the files not yet renamed into place, and the next day's mtime lower bound would never pick them up. The nightly and an `autodream-now.sh` run for another date take different run locks and would otherwise rsync into one directory at once.

### Decision
`remote_sync_locked` takes `$AUTODREAM_DIR/locks/remote-<label>.lock` with the run lock's helpers (see ADR 0001, "One run per date at a time"). If a live holder has it, `acquire_lock` waits inside its holder process up to `AUTODREAM_REMOTE_LOCK_WAIT` (default 600, a non-number becomes 600) and the run then syncs itself. A holder still alive after the wait gives `skipped_locked` and the mirror is scanned as it stands. A lock that cannot be taken at all (a read-only locks directory, no python3) gives `failed (cannot take the lock <dir>: read-only locks directory or no python3)`.

See docs/adr/0015-remote-sync.md#background-remote-hosts-a-one-way-pull-not-a-shared-filesystem-226, "Remote hosts" (Lock).

### Consequences
`skipped_locked` is a short-mirror label (it joins `REMOTE_SHORT_LABELS`) but not a failure for the all-failed banner.
