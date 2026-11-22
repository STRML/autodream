# tests: data-helper-suites: chunk-transcript, notes-path, preflight, session-window, report-format and report-scripts suites

Status: accepted · Date: 2026-11-22 · Code: `tests/chunk-transcript.sh` (`line`, `mk`, the `chunk: the limit counts bytes, not characters` case), `tests/notes-path.sh` (the `AUTODREAM_DIR` rows, `INSTALL2` symlink fixture, the seam rows), `tests/preflight.sh` (the python3 DEGRADED case, the `TO` timeout selection); the tool policy itself is in `bin/preflight.sh` (see `bin-a-preflight-hard-stop-versus-degraded.md`), `tests/session-window.sh` (`START`/`END`, the `bounds` assertions, `out-of-order.jsonl`), `tests/report-format.sh` (`old_marker`, `old_has_marker`, `old_has_sentinel`, `old_body`, `old_after`, `old_pins`, `uses`), `tests/report-scripts.sh`, `tests/stop-check-counts.sh`, `tests/portable.sh` (watchdog sleep), `tests/run-all.sh` (`test_report_scripts_*`, the unit-suite totals loop)

## fixture sizes are exact byte counts, and one fixture exists to separate bytes from characters

### Context

`bin/chunk-transcript.sh` cuts a transcript at line boundaries and measures the limit in bytes (`LC_ALL=C awk`). Every expected chunk count in the suite is arithmetic on line sizes and a limit. A fixture whose lines are 99 or 101 bytes still passes most cases, but the counts quietly stop meaning what the assertion says.

A multibyte line is the one case where a character count and a byte count give different chunk counts, so it is the only case that can tell the two implementations apart.

### Decision

- `line N` prints a line of exactly 100 bytes including its newline, padding by `84 - ${#N}` characters. The limits used in the cases (350, 250, 130) are chosen against that size.
- The multibyte case uses 60 two-byte characters, which is 120 bytes of content. At a 130-byte limit two such lines (2 x 123 bytes) do not fit together, so the correct answer is three chunks for three lines. A character count (2 x 63) would have put two lines in one chunk and returned two.

### Consequences

Changing the padding in `line`, or the character count in `mb`, changes every expected count. Recompute them rather than adjusting the assertions to the new output. Keeping the multibyte case at 60 characters and a 130-byte limit is what keeps it a mutation test for a switch from bytes to characters.

## the writer and the reader are run from an installed layout and compared by the file they touch

### Context

`autodream-note.sh` (writer) hardcoded `$HOME/.claude/autodream`, while `vault-notes.sh` (reader) resolves `AUTODREAM_DIR`. Under this port's install the writer appended to a file the nightly never opened. Nothing errored: no missing note and no warning, only an operator note that never reached the report.

Two test shapes would have passed with that bug present:

- Both scripts contain the string `$AUTODREAM_DIR/notes.md`, so a source grep matches even when the two resolve `AUTODREAM_DIR` to different directories.
- With the real `HOME`, the "legacy path is not written" row would check a directory nothing in the test could ever write to.

### Decision

- The rows are behavioural. Both scripts run from their installed location with no environment and the test compares the actual file each wrote to or read from.
- `install.sh` symlinks `bin/*.sh` into the target, so the writer's own directory is the install directory. The fixture reproduces that with `ln -s` rather than trusting the repo layout.
- `HOME` points at a sandbox, so the legacy-path row can fail.
- The note must be visible in the reader's own file, not merely adjacent to it.

### Consequences

Do not replace a row with a grep for the path expression. Add a new resolution path (a new variable or location) as a row that runs both halves and compares the file.

## the DEGRADED line is asserted directly, and the timeout wrapper follows the workflow's PATH choices

### Context

- A missing `python3` is a warning, not a stop. A test that only checked "exit 0 and not MISSING" passed on any host that has `python3`: it simulated nothing and proved nothing.
- The flag-without-value case needs a bound, because the failure it guards against is a hang. macOS has no stock `timeout`. The workflow installs coreutils for `gtimeout` only and deliberately keeps gnubin off `PATH`, because the suite depends on BSD `date` and `touch`.

### Decision

- The python3 case forces the tool missing with `AUTODREAM_PREFLIGHT_FORCE_MISSING=python3` and asserts that the output contains a `DEGRADED` line naming python3. The exit-0 and not-MISSING checks stay beside it.
- The hang case picks `timeout`, else `gtimeout`, the same selection `run-all.sh` already uses, and does not depend on gnubin. With neither, it reports the assertion as skipped.

### Consequences

Keep the positive `DEGRADED` assertion: removing it makes the python3 case pass on every host with python3 installed. A new bound in this suite uses the same selection.

## expected bounds are literals worked out separately, and the out-of-order fixture hides its stray record in the middle

### Context

`bin/session-window.sh bounds` computes local-day epoch bounds with BSD `date`. A test that derives its expected bounds with the same `date` call cannot disagree with the code, so it passes whatever the helper does on a DST day. The production rules are in `bin-b-session-window-record-timestamps-place-the-day`.

`needs-slice` decides whether a transcript holds records outside the day. A file whose first and last records are inside the day looks wholly in-day to a check of just those two.

### Decision

- `START=1790812800` and `END=1790899200` (2026-10-01 00:00:00Z and 2026-10-02 00:00:00Z) are literals. Every bound in the `bounds` block is a literal worked out separately from zoneinfo: ordinary days and the 23-hour and 25-hour days in New York, London and Sydney (northern and southern hemispheres), and a half-hour offset zone (Kolkata).
- `out-of-order.jsonl` has an in-day first record, a 2026-09-29 record in the middle and an in-day last record. `needs-slice` must still say yes, so the helper has to read every record. A fixture whose stray record sat first or last would pass a first-and-last check, and another day's records would leak into this one's report.

### Consequences

Never replace a literal with a `date` call or a helper, and never move the stray record to an edge of that fixture. A new zone needs its expected bounds computed outside this repo's code.

## the old inline code is kept verbatim as the oracle, and callers are checked by call, not by mention

### Context

`bin/report-format.sh` replaced inline marker and sentinel reads that lived in `run.sh`, `notify.sh`, `question-streaks.sh` and `triage-dream.sh`. The refactor is only safe if the helper and the code it replaced agree on stdout and on exit status for every fixture, the awkward ones included (CRLF, no trailing newline, a quoted sentinel, an unclosed pin block).

A check that a script "uses the lib" is easy to satisfy by accident. A script that only names `report-format.sh` in an error message, or in a comment, would pass a grep for the file name while still reading the report with its own awk.

### Decision

- The `old_*` functions are the previous implementations, copied verbatim. They are the oracle: `same` runs helper and reference over the whole fixture matrix and compares output and status.
- `uses <script> <helper>` greps for the helper's name on a line that is not a comment (`^[^#]*\bhelper\b`). Each caller must call the helper it replaced. A mention of the lib's file name proves nothing.
- The lib must also be sourced on a line of its own, and no other `bin/*.sh` may read the marker or the sentinel with its own grep, sed or awk (comment lines are skipped).

### Consequences

Do not "improve" an `old_*` function: once it changes, the test compares the helper with a reference nobody ever ran, and a behaviour change in the helper passes. A new fixture goes into `FIXTURES`, and a new caller gets a `uses` line.

## fixtures that must be able to fail, and a skip that never counts as a pass

### Context

`bin/report-scripts.sh` runs allowlisted commands before L2 so a failure becomes content in the findings dir, never silence and never an aborted run. Each trap below made a first version of a test pass for the wrong reason.

### Decision

- **A check that cannot run prints `skip - <reason>`.** It adds nothing to the passed count, and the totals line carries `skipped: N`. `run-all.sh` repeats that number beside the suite's count, so a CI log shows ran against skipped. A suite that prints no `skipped:` total is unchanged.
- **The watchdog test asks `kill -0`, not a process table.** A `sleep` shim records its pid and then becomes the real `sleep`; `kill -0` on that pid shows the watchdog's sleep ended with the command. `pgrep` and `ps` are denied in some sandboxes. `tests/portable.sh` and `tests/report-scripts.sh` use the same shim.
- **The failed-write case limits the file size.** SIGXFSZ is ignored and the limit is 1 KB, so the report's header line (the command is 1.2 KB) cannot be written while the short index row for a failed write can. The old collector wrapped every write in one brace group, whose status is its last command, and recorded an `ok` row for a report that was not there.
- **The unremovable stale index is an `rm` and an `mv` that refuse it.** The cleanup uses `rm -rf`, so a planted directory with a report name is not unremovable, and a read-only findings dir would stop the run long before the seam under test.
- **Fixture ordering and rewrites are deliberate in `run-all.sh`.** `report-z.md` sorts after the collected files, so the rows before it hash and match and `shasum` then fails on it. A stand-in collector rewrites the conf and the good script during `snapshot`, which `run.sh` calls after it fingerprinted the file: what an L1 worker with Write could do before the collector starts. A forced rerun keeps the findings dir, so the earlier run's files must not survive a failed collect.
- **`tests/stop-check-counts.sh` expected numbers are literals worked out by hand.** Every fixture line is synthetic and the clock is injected (`STOP_CHECK_NOW`, 2026-11-19T12:00:00Z, a Thursday whose UTC week starts Monday 2026-11-16). The real log's `message` and `note` fields hold quoted session text, so the script must print counts only.

### Consequences

A new case in these suites needs a way to fail with the guarded code removed. Do not replace a literal with a second run of the code under test.
