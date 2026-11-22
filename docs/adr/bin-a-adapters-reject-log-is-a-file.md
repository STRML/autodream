# bin-a: refusals are recorded in a file, and an unreadable record reports `unknown`, never `none`

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`adapters_reject_log`, `adapters_rejected`, `_adapter_reject`, `_adapter_reject_broken_marker`, `adapters_list`, `_adapter_ok`)

## Context

`adapters_list` is almost always called as `$(adapters_list)`, and a variable assigned inside a command substitution never comes back to the caller. This is the same trap that cost the repo the cookie-expiry remediation text in `vault-notes.sh`, where `FAIL_REASON` was set inside nested `$(...)` and died with the subshell. The loader's first reject-flag was a shell variable set from `_adapter_reject`, from `_adapter_ok`, from `adapters_list`: the assignment died with the subshell and the flag was always 0 in the parent. It was the third time this trap was laid in this repo.

The count of refusals goes to `run-stats.txt`. A false `none` is worst on the total-outage path: the loader refuses every adapter, `run.sh` fatals with "accepted no adapters (rejected: none)", and the operator is told nothing was refused when everything was.

## Decision

- Refusals go to a log file (`ADAPTERS_REJECT_LOG`, so callers can point it at a findings dir). A file crosses the subshell boundary; a variable does not.
- The default log is `${TMPDIR:-/tmp}/autodream-adapters-rejected.$$`, not a path in the adapters root. `_adapter_reject` only appends and only `run.sh` truncates, so a repo-tree default made any other caller (an interactive `. bin/adapters.sh; adapters_list`, a future tool) accumulate refusals across invocations, and `adapters_rejected` then reported stale names as this run's. It also left untracked cruft in a checkout that `.gitignore` does not cover. The PID in the name keeps two callers from cross-contaminating.
- `adapters_rejected` prints `none`, never an empty string. `run.sh` writes it straight into `run-stats.txt`, and `adapters_rejected: ` with nothing after it cannot be told apart from a key that was never measured, the ambiguity `overlap_measured` and `stats_sidecars_unparseable` exist to refuse. A caller-side `|| printf none` cannot save it because returning 0 with no output is success.
- When the log could not be written, `_adapter_reject` drops a marker file and `adapters_rejected` prints `unknown (the reject log could not be written)` instead of a confident `none`. The refusals happened; the loader just cannot name them. The marker is a file for the reason above, and it lives in `TMPDIR`, because the case being reported is precisely the log's directory being unwritable.
- The append is `{ printf '%s\n' "$1" >> "$log"; } 2>/dev/null`. The braces matter: `printf ... >> "$log" 2>/dev/null` sets up the append before the suppression, so bash reports a failure to open `$log` on the original stderr and the line only reads as silenced. It showed in `tests/adapters.sh` as a raw `bin/adapters.sh: line NN: ...: Is a directory`. `run.sh` captures this call under `adapters_list 2>/dev/null`, so the nightly never saw it; any other caller does.
- `adapters_list` globs both `"$root"/*/` and `"$root"/.*/`. The first never matches a dot-prefixed directory, so a hostile or malformed `.evil` was silently invisible instead of recorded as a refusal, and `adapters_rejected` then reported `none` when something was refused. `.` and `..` are skipped.
- A leading underscore marks a test-only adapter. `_adapter_ok` excludes it without recording it, because it is a deliberate exclusion rather than a refusal worth counting.

## Consequences

Do not turn the log or the marker into shell variables, and do not move the log default back under the adapters root. `run.sh` and `tests/adapters.sh` rely on `none` and `unknown (...)` being distinct from a measured zero.
