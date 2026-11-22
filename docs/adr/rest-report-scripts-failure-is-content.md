# rest: a failing report entry is written as report content, the collector never aborts the run, and every write is checked

Status: accepted · Date: 2026-11-22 · Code: `bin/report-scripts.sh` (`collect`, `write_report`, helper lookup at the top); CLAUDE.md "Report scripts"

## Context

L2 reads whatever `report-<name>.md` holds. If a failing script left no file, L2 would see silence and could not tell "no output" from "broke". The same principle as `x-bookmarks.sh`: the failure is the content. Separately, L2's Glob and directory reads stop at 200 entries, and a findings dir holds thousands, so PROMPT.md forbids globbing it.

## Decision

- **Every failure still writes a report.** A non-zero exit, a timeout, a missing or non-executable script, a relative path, an entry with no script path: each writes `report-<name>.md` with `FAILED:` on the first body line, plus the last 20 lines of stderr (cut to 4000 bytes). The index row's status says which.
- **`report-index.txt` is the one fixed path L2 reads.** It lists every entry with name, status, file and detail, and L2 then Reads each file by exact path. It is always written, `none configured` included.
- **The collector exits 0 whatever the entries do.** It exits 1 only when it cannot write the findings dir (not writable, no temp dir, earlier report files that cannot be removed, a write that failed). `run.sh` treats that as "refusing to let L2 read them" and reports it.
- **The earlier run's files are removed first.** A rerun of the same date would otherwise leave the report of an entry that has left the conf, and L2 would answer a note from last night's output.
- **A short index must not read as complete.** Every entry line writes exactly one row, and the row count is compared with the entry count after the index is written. A mismatch makes `collect` exit 1.
- **Every write is checked on its own.** The status of a brace group is its last command, so a full disk can fail an earlier write while a later one succeeds. `write_report` therefore checks each `printf`, `cat` and `head` with `|| return 1`, writes to `.report-<name>.tmp` and renames, so a failed write is a `write-failed` row and never an `ok` row for a missing file. The index is copied and renamed the same way.
- **The helper is found next to the script, then next to its symlink target.** `portable.sh` is looked up beside `BASH_SOURCE`, then beside the file a symlink points at. An installed copy is a symlink, and a merge updates the checkout before `install.sh` links a newly added helper, so the first lookup alone would fail on a live install.

## Consequences

The collector must never exit non-zero for an entry's behavior, or the run reads it as a collector failure. A new status needs a row in `report-index.txt`, in PROMPT.md's status contract and in `report_scripts_stats` in `run.sh` (`test_report_scripts_prompt_status_contract_matches_the_collector` pins that). In new code that reads the index, do not use a glob or a process substitution: the status of the read has to be seen.
