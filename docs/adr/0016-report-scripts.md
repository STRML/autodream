# 0016: Report scripts: operator-requested commands

Status: accepted · Governs: `bin/report-scripts.sh`, `bin/run.sh`, `bin/stop-check-counts.sh`, `tests/stop-check-counts.sh`

This record holds 9 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Report scripts: one collector so a note can ask for a command](#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command)
- [report scripts run from an allowlist snapshotted before any model runs, and an entry is pinned by hash](#report-scripts-run-from-an-allowlist-snapshotted-before-any-model-runs-and-an-entry-is-pinned-by-hash)
- [a report command is bounded by one built-in watchdog, never timeout(1), with a per-file size limit and a settled process tree](#a-report-command-is-bounded-by-one-built-in-watchdog-never-timeout1-with-a-per-file-size-limit-and-a-settled-process-tree)
- [a failing report entry is written as report content, the collector never aborts the run, and every write is checked](#a-failing-report-entry-is-written-as-report-content-the-collector-never-aborts-the-run-and-every-write-is-checked)
- [stop-check-counts prints counts only, reports every line it skipped, and fails when either pipeline stage fails](#stop-check-counts-prints-counts-only-reports-every-line-it-skipped-and-fails-when-either-pipeline-stage-fails)
- [The allowlist of operator-requested scripts is snapshotted, and the scripts run, before the first model call](#the-allowlist-of-operator-requested-scripts-is-snapshotted-and-the-scripts-run-before-the-first-model-call)
- [report-script health is copied into run-stats so a failing entry reaches the self-audit](#report-script-health-is-copied-into-run-stats-so-a-failing-entry-reaches-the-self-audit)
- [the report-script collector and its output are fingerprinted, and a fingerprint that cannot be taken counts as changed](#the-report-script-collector-and-its-output-are-fingerprinted-and-a-fingerprint-that-cannot-be-taken-counts-as-changed)
- [report-script output is re-hashed before L2 and replaced with an `unavailable` index if it changed](#report-script-output-is-re-hashed-before-l2-and-replaced-with-an-unavailable-index-if-it-changed)

## Background: Report scripts: one collector so a note can ask for a command

This section was moved here from the former CLAUDE.md. Its original title: "Report scripts: one collector so a note can ask for a command".

L2 has Glob and Read only, so an operator note such as "run review-gate-raises and quote the rows" failed with no sign of it. `bin/report-scripts.sh collect <findings-dir>` runs after the other collectors (vault notes, X bookmarks) and runs each entry of `$AUTODREAM_DIR/report-scripts.conf` (`<name> <absolute or ~/ path> [args...]`, `#` comments), so a new report is one conf line and never a change to `run.sh` or the prompt. `AUTODREAM_REPORTS_BIN` overrides the collector's path, authoritative like the other helper overrides.

- **The failure is the content.** A non-zero exit, a timeout (`AUTODREAM_REPORT_TIMEOUT`, 60s), a missing or non-executable script and a relative path each still write `report-<name>.md` with `FAILED:` on the first body line and the stderr, the same principle as `x-bookmarks.sh`. The collector exits 0 whatever the entries do; `run.sh` logs and continues if it does not.
- **L2 reads one fixed path, not a glob.** `report-index.txt` (tab-separated `name status file detail`, or `none configured`) is the only name PROMPT.md hands L2, which then Reads each listed file by exact path. A `Glob report-*.md` would break the rule at the top of PROMPT.md: a Glob stops at 200 entries and a findings dir holds thousands. The first request for this feature said to Glob; the index is the same thing under the repo's own rule. A stale `report-*.md` from an entry since removed is deleted at the start of each collect (a forced rerun of a date), so L2 can never read an old answer.
- **Nothing is evaluated.** Arguments are whitespace-split words (`set -f`, no `eval`, no quotes, no `$`), the stdin is `/dev/null`, the cwd is `$HOME`, and the output goes to files, never a `$(...)`, so a grandchild that outlives its parent cannot hold the collector. Names are `[A-Za-z0-9][A-Za-z0-9._-]*` and a repeated name is refused, so an entry cannot write outside the findings dir or overwrite another. An operator note cannot widen what runs because it never reaches the conf.
- **The allowlist is snapshotted before any model runs.** An L1 worker reads untrusted transcripts and holds Write, and the collector executes what the conf names, so a worker that rewrote the conf (or a listed script) would get code run with the operator's privileges (found by the preflight review of PR 233). `run.sh` calls `report-scripts.sh snapshot` next to the pins ledger snapshot, before the first L1 call, and keeps the output in memory: `#present` or `#absent`, then `<entry hash or -><TAB><conf line>` per entry. `collect` gets it back as a temp file and runs only that. A script whose hash differs, or that did not exist at the snapshot, is `changed` and never executed; a snapshot that failed is `#unavailable` and runs nothing (the index says so, it does not say none configured). A manual `collect` with no snapshot reads the conf and checks nothing. The check is fail-closed: a script runs only when the snapshot and the current hash are both real sha256 values and equal, so a `shasum` that fails twice reads as unverifiable, never as unchanged. The collector and the `portable.sh` it sources get the same treatment from `run.sh` (`report_collector_fingerprint`, taken before the snapshot call and checked again before `collect`), because they too are code a worker could rewrite; a mismatch or an unreadable file runs nothing. Whenever the collector does not finish (not found, fingerprint mismatch, exit non-zero) `report_scripts_unavailable` deletes the earlier run's `report-*.md` and `report-index.txt` and writes an index saying `unavailable`, so a forced rerun cannot answer a note from last night's output. If that cleanup itself fails the run stops with `log_fatal` (`refusing to let L2 read them`), the same shape as the other "cannot write the findings dir" fatals. An entry is pinned to its script and to every argument that is an existing file at snapshot time (`name /bin/bash ~/x.sh` pins bash and x.sh together, as one sha256 over the script hash and each file's path and hash; a relative argument is looked up from HOME, where the command runs; an argument file that appears later is `changed` too). Names are compared ignoring case, since `Foo` and `foo` are one file on APFS.
- **Collection runs before the first model call, so no worker has run when a script executes (round 2 of the gate on PR 233).** The snapshot and the hashes only pin what a script and its arguments are, not the files a script sources or runs, and a worker with the Write tool that is not confined (an engine whose adapter has no `l1-writes` profile, a host whose sandbox probe fails, `AUTODREAM_L1_CONFINE=0`) can rewrite any of them. `run.sh` therefore runs `collect` right after the snapshot, and what a worker can still reach is the output: `report_output_fingerprint` hashes `report-index.txt` and every `report-<name>.md` straight after collection, the runner keeps those hashes in memory, and before L2 it compares them. A file changed, added or deleted, or a hash that cannot be taken, replaces the report files with an `unavailable` index (`report_scripts_unavailable`, which also clears the earlier run's files and stops the run if it cannot). A script therefore reports the state of the machine as of the start of the run, minutes earlier than when collection followed L1. Confined workers (241) cannot write the findings dir at all, so on a confined host this check never fires.
- **The residual, only for workers that are not confined: an engine whose adapter has no `l1-writes` profile, a host whose probe says no, or `AUTODREAM_L1_CONFINE=0`.** A conf entry, a listed script or a file it sources that such a worker plants or rewrites on night N is trusted by the snapshot of night N+1, and `run.sh` and the other helpers the nightly runs are writable by the same worker (the exposure `vault-notes.sh` and `x-bookmarks.sh` already have), as is the sourced `$AUTODREAM_DIR/config`. No marker, latch or stored hash on disk can close that, because the worker can forge it too. It disappears for an engine once its adapter declares a write profile and `l1_confined_<engine>` reads `yes`. Claude and omp both declare one (PR 246), so on a host whose probe says yes it is closed for both, and `tests/run-all.sh` has a confined-worker case for each, which skips where no sandbox works.
- **A command cannot hold or fill the run.** The timeout is one built-in watchdog (`run_bounded`), never `timeout(1)`: the binary reports the command's own exit status when it traps TERM and exits 0, and leaves a TERM-ignoring child of an exited wrapper running, so it could not be told from a normal run. At `AUTODREAM_REPORT_TIMEOUT` the watchdog records the process tree (`pgrep -P`) in a flag file the collector owns, sends TERM, and `AUTODREAM_REPORT_KILL_GRACE` seconds later KILLs the recorded tree, so a command that traps TERM still ends and so does a child that outlived its wrapper. A row is `timeout` exactly when that flag file is non-empty, whatever the exit status was (a command that traps TERM and exits 0 is a timeout, not `ok`). `pgrep` cannot read the process table inside the Claude Code sandbox, so the child-kill assertions in `tests/report-scripts.sh` skip there and run in CI. The three numeric knobs are read with `10#`, so `08` is a number and not a bad octal. `ulimit -f` caps every file the command writes, stdout and stderr included, at four times `AUTODREAM_REPORT_MAX_BYTES`, so a command that never stops printing dies on SIGXFSZ long before the disk is full; the report body is cut at the cap itself. A report or index that cannot be written is a `write-failed` row and exit 1, never an `ok` row for a missing file; `write_report` checks each write on its own because a brace group's status is its last command. (macOS does not enforce `ulimit -f` on `>>` appends, which is why the test for this puts the failure in the header line.)
- **A zero-session day collects nothing, on purpose.** `run()` writes the stub report and returns before L2 when no session was triaged, so no model reads a report file that night and an operator note waits for the next report. The operator-notes and bookmark collectors have always behaved the same way.
- **A note that names no entry is told so.** PROMPT.md's "Command output the operator asked for" makes L2 say plainly that no allowlist entry covers the command and name the line to add, instead of guessing the rows. `report-index.txt` carries the conf path for that reason.
- **Shipped report scripts.** `bin/stop-check-counts.sh [--since-hours N]` counts the stop-check mod's verdict log (`~/.claude/stop-check/verdicts.jsonl`, `{"kind","at","message","note"}`) by kind in the window and by UTC week for eight weeks. Counts only: `message` and `note` hold quoted session text and are never printed. It is a plain jq pass with the clock injectable (`STOP_CHECK_NOW`) so `tests/stop-check-counts.sh` pins literal expected numbers; the weekly bucketing is by UTC Monday, and a Sunday 23:59:59 line belongs to the week before it.
- **A failing entry reaches the self-audit.** PROMPT.md tells L2 not to read the index unless an operator note asks for a command, so an entry that exits 1 every night would never be seen. After `collect`, `report_scripts_stats` in `run.sh` reads the index it just wrote and puts `report_scripts: off|unavailable|<entry count>` and `report_scripts_not_ok: <names>|none` into run-stats; an index it cannot read or whose first line it does not know is `unavailable`, never `off`. PROMPT.md's self-audit names every entry that is not `ok`. The statuses are `ok`, `failed`, `timeout`, `missing`, `invalid`, `changed` and `write-failed`; a `-` in the file column (a refused name, a failed write) means there is nothing to Read and the detail column is the whole message. Output past the per-file `ulimit -f` cap is `FAILED: output exceeded the N KB per-file limit and was stopped`, not a bare `exited 153`.
- **A watchdog takes its own `sleep` with it.** `run_bounded` here, `tmo` in `bin/portable.sh` and the hard-cap watchdog in `bin/prune-worktrees.sh` each ran `( sleep N; kill ... ) &` and killed only the subshell when the command finished in time, which left the `sleep` running until its timeout. Each watchdog subshell now traps TERM, kills the sleep it started and exits, so the kill that ends it also ends the sleep and a watchdog woken at that moment cannot signal a recycled pid. The tests ask the shimmed `sleep` for its pid and use `kill -0`, because `pgrep` and `ps` are denied in the Claude Code sandbox.
- **Tests.** `tests/report-scripts.sh` is the collector's failure matrix; the `test_report_scripts_*` cases in `tests/run-all.sh` pin the `run.sh` seam (a failing entry still lands a report, a broken or missing collector costs a log line) and that PROMPT.md names the index by exact path. `install.sh` links both scripts; it does not create the conf.

## report scripts run from an allowlist snapshotted before any model runs, and an entry is pinned by hash

Status: accepted · Date: 2026-11-22 · Code: `bin/report-scripts.sh` (`snapshot`, `entry_hash`, `hash_of`, `collect`), `bin/run.sh` (`report_collector_fingerprint`, `report_output_fingerprint`); docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command "Report scripts"

### Context

Operator notes kept asking the nightly run to "run X and quote the rows". L2 holds Read and Glob only, so it could not, and the ask failed without a word. `report-scripts.sh` runs the commands before L2 and writes each result to `<findings-dir>/report-<name>.md`, so a new report is one line in `$AUTODREAM_DIR/report-scripts.conf` and never a change to `run.sh` or the prompt.

The conf is code that runs with the operator's privileges. An L1 worker reads untrusted transcripts and holds the Write tool, so a worker that rewrote the conf, or a script the conf names, would get that code run by the next collect. The preflight review of PR 233 found this.

### Decision

- **Only the operator edits the conf.** An operator note (which can come from a phone or a transcript) never reaches it, so a note cannot widen what runs. Args are literal words split on whitespace: no quotes, no `$VAR`, no glob (`set -f`), no `;`, no `eval`. A missing conf is "no reports", never an error.
- **The allowlist is snapshotted before any model runs.** `run.sh` calls `snapshot` before the first model call and keeps the output in memory. The snapshot is `#present` or `#absent`, then `<hash or ->` TAB `<conf line>` per entry. `collect` is handed it back and runs only what it lists. A script whose hash differs now, or that did not exist when the snapshot was taken, gets status `changed` and is not executed. A snapshot that failed reads `#unavailable` and runs nothing, and the index says so rather than saying none is configured. An unreadable snapshot has no first line, so its state is empty and reads as unavailable.
- **A manual `collect` has no snapshot.** It reads the conf now and checks nothing (`checked=0`), because nothing has run since the operator wrote it. A conf that exists and cannot be read is `#unavailable`, not "none configured".
- **What the hash covers.** The file named as the entry's path, and every argument that is an existing file at snapshot time: `name /bin/bash ~/x.sh` pins bash and `x.sh` together as one sha256 over the script hash and each file's path and hash. A relative argument is looked up from HOME, where the command runs. An argument file that appears after the snapshot is also `changed`.
- **The comparison fails closed.** A script runs only when the snapshot's hash and the current hash are both real 64-hex sha256 values and equal. A `-` on both sides (the hash failed twice) must never read as "unchanged".
- **Names are compared ignoring case.** `Foo` and `foo` are one file on APFS (`report-<name>.md`), so the second is `invalid` as a duplicate.
- **The collector and what a worker can still reach.** `run.sh` fingerprints `report-scripts.sh` and the `portable.sh` it sources before the snapshot and checks again before `collect`, and runs `collect` right after the snapshot (before any worker). `report_output_fingerprint` then hashes the index and every report file, and L2 gets an `unavailable` index if one changed.

### Consequences

Not covered: anything a script sources, reads or runs on its own. The residual exists only for workers that are not confined (an engine whose adapter has no `l1-writes` profile, a host whose sandbox probe says no, or `AUTODREAM_L1_CONFINE=0`). A conf entry or script such a worker plants on night N is snapshotted as trusted on night N+1, because nothing tells a planted line from one the operator wrote, and a snapshot cannot protect a trust anchor the worker can also write. It closes for an engine once its adapter declares a write profile and `l1_confined_<engine>` reads `yes` (issue 169; PR 241 and 246 for claude and omp). The header this replaces said both gaps close when workers cannot write outside their staging dir. That is now true on a host whose probe passes, so check `l1_confined` before relying on it.

Before changing the snapshot format, grep `run.sh` for its readers: it passes the snapshot through a temp file, and the `report-index.txt` statuses (`changed`, `invalid`) are read by `report_scripts_stats` and PROMPT.md.

## a report command is bounded by one built-in watchdog, never timeout(1), with a per-file size limit and a settled process tree

Status: accepted · Date: 2026-11-22 · Code: `bin/report-scripts.sh` (`run_bounded`, `tree_pids`, `settle_tree`, the numeric knobs, the `collect` timeout branch); docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command "Report scripts"

### Context

A report command must not be able to hold or fill the nightly run, and the processes it started must not outlive it. Three observations shaped the code:

- `timeout(1)` reports the command's own exit status when the command traps TERM and exits 0, and leaves a TERM-ignoring child of an exited wrapper running. Neither can be told apart from a normal run, so there is no `timeout(1)` path (macOS ships none anyway).
- A watchdog written as `( sleep N; kill ... ) &` leaves its `sleep` running after the command finished in time. Killing only the subshell did not end the sleep.
- macOS does not enforce `ulimit -f` on `>>` appends.

### Decision

- **One path, `run_bounded`.** It starts the command, then a watchdog subshell that sleeps `AUTODREAM_REPORT_TIMEOUT` (default 60). At the timeout the watchdog records the process tree (`tree_pids`, via `pgrep -P`) in a flag file the caller owns, sends TERM to it, waits `AUTODREAM_REPORT_KILL_GRACE` (default 5) seconds and sends KILL. The watchdog traps TERM and kills its own sleep, so a command that finishes in time leaves nothing behind and a watchdog woken at that moment cannot signal a recycled pid.
- **The flag file is the evidence.** It is empty unless the timeout fired. A row is `timeout` exactly when it is non-empty, whatever the exit status was: a command that traps TERM and exits 0 is still one that ran past its limit. The exit status and the clock are never used to infer it.
- **The tree is settled after the command is gone.** A TERM-ignoring child the command started is no longer reachable through the command's process tree, so `settle_tree` walks the recorded list. It gives survivors what is left of the grace period, then sends KILL.
- **Output is limited per file.** `ulimit -f` caps every file the command writes, stdout and stderr included, at four times `AUTODREAM_REPORT_MAX_BYTES` (default 100000). A command that never stops printing dies on SIGXFSZ (exit 153, reported as an output-limit failure rather than a bare `exited 153`) long before the disk is full. The report body is cut at the cap itself. The limit is per file and macOS does not enforce it on appends, so what a script appends to its own files is bounded by the timeout alone.
- **The knobs are read with `10#`.** A value with a leading zero (`08`) is a number here, not a bad octal that aborts the collector. A non-numeric or zero value falls back to the default.

### Consequences

`pgrep` cannot read the process table inside the Claude Code sandbox, so the child-kill assertions in `tests/report-scripts.sh` skip there (3 skips on 2026-11-22) and run in CI. The same watchdog shape lives in `tmo` in `bin/portable.sh`, `run_bounded` in `x-bookmarks.sh` and the hard-cap watchdog in `bin/prune-worktrees.sh`. A fix to one is a fix to the class, so grep the others before changing it.

## a failing report entry is written as report content, the collector never aborts the run, and every write is checked

Status: accepted · Date: 2026-11-22 · Code: `bin/report-scripts.sh` (`collect`, `write_report`, helper lookup at the top); docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command "Report scripts"

### Context

L2 reads whatever `report-<name>.md` holds. If a failing script left no file, L2 would see silence and could not tell "no output" from "broke". The same principle as `x-bookmarks.sh`: the failure is the content. Separately, L2's Glob and directory reads stop at 200 entries, and a findings dir holds thousands, so PROMPT.md forbids globbing it.

### Decision

- **Every failure still writes a report.** A non-zero exit, a timeout, a missing or non-executable script, a relative path, an entry with no script path: each writes `report-<name>.md` with `FAILED:` on the first body line, plus the last 20 lines of stderr (cut to 4000 bytes). The index row's status says which.
- **`report-index.txt` is the one fixed path L2 reads.** It lists every entry with name, status, file and detail, and L2 then Reads each file by exact path. It is always written, `none configured` included.
- **The collector exits 0 whatever the entries do.** It exits 1 only when it cannot write the findings dir (not writable, no temp dir, earlier report files that cannot be removed, a write that failed). `run.sh` treats that as "refusing to let L2 read them" and reports it.
- **The earlier run's files are removed first.** A rerun of the same date would otherwise leave the report of an entry that has left the conf, and L2 would answer a note from last night's output.
- **A short index must not read as complete.** Every entry line writes exactly one row, and the row count is compared with the entry count after the index is written. A mismatch makes `collect` exit 1.
- **Every write is checked on its own.** The status of a brace group is its last command, so a full disk can fail an earlier write while a later one succeeds. `write_report` therefore checks each `printf`, `cat` and `head` with `|| return 1`, writes to `.report-<name>.tmp` and renames, so a failed write is a `write-failed` row and never an `ok` row for a missing file. The index is copied and renamed the same way.
- **The helper is found next to the script, then next to its symlink target.** `portable.sh` is looked up beside `BASH_SOURCE`, then beside the file a symlink points at. An installed copy is a symlink, and a merge updates the checkout before `install.sh` links a newly added helper, so the first lookup alone would fail on a live install.

### Consequences

The collector must never exit non-zero for an entry's behavior, or the run reads it as a collector failure. A new status needs a row in `report-index.txt`, in PROMPT.md's status contract and in `report_scripts_stats` in `run.sh` (`test_report_scripts_prompt_status_contract_matches_the_collector` pins that). In new code that reads the index, do not use a glob or a process substitution: the status of the read has to be seen.

## stop-check-counts prints counts only, reports every line it skipped, and fails when either pipeline stage fails

Status: accepted · Date: 2026-11-22 · Code: `bin/stop-check-counts.sh`, `tests/stop-check-counts.sh`; docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command "Report scripts" (shipped report scripts)

### Context

The stop-check mod appends one JSON line per judged turn to `~/.claude/stop-check/verdicts.jsonl`: `{"kind":"ok|ask|bad|error","at":"<UTC ISO, with milliseconds>","message":"...","note":"..."}`. This script is a report script for the nightly run: allowlisted in `report-scripts.conf`, its stdout becomes `report-<name>.md` and L2 can quote its rows (README, "Report scripts"). It makes no model call and writes nothing.

### Decision

- **Counts only.** `message` and `note` hold quoted session text and are never printed, so a report row cannot leak or inject transcript text.
- **Nothing is dropped silently.** A line that does not parse, or lacks a usable `kind` and `at`, is counted as `unparseable lines skipped`. A line dated after the clock is reported as `dated after now (not counted)`. A `kind` outside `[a-z]+` is counted as `other`: the log is written by another tool, and a kind holding a tab or newline would forge rows in this tab-separated report.
- **Two views.** `recent` is the window (default 36 hours, `--since-hours N`) grouped by kind, most frequent first. `weekly` is the last eight UTC weeks (Monday start, oldest first) with one column per kind seen in them. A week with no verdicts is a row of zeros, never a gap, so a quiet week reads as quiet and not as a missing row. A Sunday 23:59:59 line belongs to the week before it.
- **The clock is injectable.** `STOP_CHECK_NOW` (epoch seconds) replaces the clock so `tests/stop-check-counts.sh` pins literal expected numbers. `STOP_CHECK_VERDICTS` names the log (default `$HOME/.claude/stop-check/verdicts.jsonl`).
- **jq emits tagged TSV rows and awk lays them out**, so the column widths do not depend on jq's version.
- **Both stages must succeed.** The script reads `PIPESTATUS` and exits with the first failing stage. jq alone failing, or awk failing to write the layout, is a script failure, and the collector reads exit 0 as `ok`.

### Consequences

A new field in the verdict log must not be printed without checking that it is not session text. A change to the row layout changes what L2 quotes, so update the literals in `tests/stop-check-counts.sh` with it. Exit codes: 2 for a usage error, 1 for a missing `jq` or log.

## The allowlist of operator-requested scripts is snapshotted, and the scripts run, before the first model call

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `REPORT_SNAPSHOT`, `REPORT_COLLECTOR_FP`, the collect step, `REPORT_OUT_FP`)

### Context
The collector (`bin/report-scripts.sh`) EXECUTES what `$AUTODREAM_DIR/report-scripts.conf` names. An L1 worker reads untrusted transcripts and holds the Write tool, so it could rewrite the conf (or a script the conf names, or a file such a script sources) and have the collector run the result with this user's privileges. The sha256 pins alone cannot cover files a script sources. A worker that is not confined (a host whose sandbox probe fails, `AUTODREAM_L1_CONFINE=0`, or an engine whose adapter declares no `l1-writes` profile; the comment this ADR came from said omp had none, which stopped being true when both adapters gained one) can rewrite them, and the script's own hash would still match. See docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, 'Report scripts: one collector so a note can ask for a command' (snapshot and "Collection runs before the first model call").

### Decision
- Before the first model call, `report_collector_fingerprint` and `report-scripts.sh snapshot` are taken and held in memory (`#unavailable` when the snapshot fails). Just before collection the collector fingerprint is checked again; a mismatch, or a missing collector, runs nothing.
- The collector runs right after, from the snapshot file, never from the live conf; each allowlisted entry runs with a timeout and a failing one still writes its file with the failure as the content. A new report is a conf line, never a change to `run.sh` or the prompt.
- Nothing has run that could have rewritten a script when it executes. What a worker can still reach is the files the step wrote into the findings dir, so the runner hashes them (`report_output_fingerprint`), holds the hashes in memory and checks them again before L2 reads anything.
- A collector that cannot run costs a log line and an `unavailable` index (`report_scripts_unavailable`). The run stops (`log_fatal`) only when the earlier run's report files cannot be cleared.

### Consequences
- Do not move collection after L1: a script would then report the state after untrusted workers had run, and its sourced files could have been rewritten.
- A script reports the machine as of the start of the run, minutes earlier than when collection followed L1.
- Do not read the live conf in `collect` during a run.

## report-script health is copied into run-stats so a failing entry reaches the self-audit

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_scripts_stats`)

### Context
PROMPT.md tells L2 to read `report-index.txt` only when an operator note asks for a command, so an entry that fails every night would never be seen.

### Decision
After collection, `report_scripts_stats` reads the index the collector or `report_scripts_unavailable` just wrote and appends `report_scripts: off|unavailable|<entry count>` and `report_scripts_not_ok: <comma-separated names>|none` to `run-stats.txt`. An index it cannot read, or whose first line it does not recognise, is `unavailable`, never `off`.

### Consequences
PROMPT.md's self-audit names every entry that is not `ok`. See docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, "A failing entry reaches the self-audit".

## the report-script collector and its output are fingerprinted, and a fingerprint that cannot be taken counts as changed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_collector_fingerprint`, `fingerprint_unchanged`, `report_output_fingerprint`, `report_scripts_unavailable`)

### Context
The collector and the `portable.sh` it sources are code the run executes with the operator's privileges, and an L1 worker that is not confined holds Write. Comparing `"$(fn)"` directly discards `fn`'s exit status, so a fingerprint that printed the matching rows and then failed on the next file would read as unchanged. A forced rerun keeps the findings directory, so any earlier run's `report-*.md` files would be read by L2 as tonight's output unless something clears them. A worker that is not confined can plant a directory with such a name, and `rm -f` would leave it standing and stop the night over a file the runner is entitled to clear.

### Decision
- `report_collector_fingerprint` prints the sha256 of `$REPORT_SCRIPTS` and of its sibling `portable.sh` (resolving the symlink if needed), one per line, and fails when either cannot be read or hashed. It is taken before the snapshot and the first model call, and checked again right before `collect`.
- `fingerprint_unchanged FN BEFORE` is true only when the function succeeds and prints exactly the earlier output; an empty earlier value is never "unchanged".
- `report_output_fingerprint` prints `name sha256` for `report-index.txt` and every `report-*.md`, in name order, and fails when the directory cannot be entered or any file cannot be hashed. The runner holds the first result in memory and compares before L2.
- `report_scripts_unavailable WHY` runs whenever the collector does not finish or the output changed: it removes the earlier `report-*.md` and `report-index.txt` with `rm -rf` and writes an `unavailable` index. It returns 1 when it cannot, and the caller stops the run instead of letting L2 read last night's rows.

### Consequences
The original comment says the collector runs "after L1 workers have run"; that is out of date. Collection now runs before the first model call, and the first fingerprint is checked right before collect and the output fingerprint again before L2. Never make a failed hash read as "unchanged". See docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, "Report scripts: one collector so a note can ask for a command" (snapshot, collection before the first model call, the residual for unconfined workers).

## report-script output is re-hashed before L2 and replaced with an `unavailable` index if it changed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `fingerprint_unchanged report_output_fingerprint`, `report_scripts_unavailable`, `report_scripts_stats`)

### Context
L1 workers that are not confined can write anywhere the user can, the findings dir included. What L2 reads for an operator note is `report-index.txt` and the `report-<name>.md` files it names, which were collected before L1.

### Decision
The fingerprint is `report-index.txt` plus every `report-*.md` (name and sha256), taken by `report_output_fingerprint` straight after collection and held in memory (`REPORT_OUT_FP`); it is compared by `fingerprint_unchanged` after L1 and before L2. Any difference from the hashes the runner took right after collection (a file changed, added or deleted, or a failure to hash them then, which leaves `REPORT_OUT_FP` empty and so never matches) replaces the report files with an `unavailable` index. The earlier run's files are removed by the same call, and the run stops (`log_fatal`, `fatal_exit`) only if that cannot be done. `report_scripts_stats` then writes `report_scripts` and `report_scripts_not_ok` to run-stats from the index as it now stands. See docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, "Report scripts: one collector so a note can ask for a command" (the snapshot, collection-before-L1, and output fingerprint paragraphs).

### Consequences
Confined workers (#241) cannot write the findings dir, so on a confined host this never fires. Do not move collection after L1: that reopens the window the fingerprint exists to close.
