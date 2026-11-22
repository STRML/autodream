# runsh: root scanning fails loudly where a shortfall would read as a quiet night, and stays a caveat where it would not

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots`, `scan_one_adapter`)

## Context
A report written from a corpus the run never saw looks complete and cannot say so itself. Several distinct causes need distinct treatment:
- Two colliding paths in the raw worklist while `.src` lost a row would send both to dispatch (the same fail-open overwrite as the collision index, one stage earlier).
- No usable adapter is a TOTAL outage with a mundane trigger: `adapters/claude/adapter.sh` losing its exec bit to a tarball copy, a restrictive umask or `core.fileMode=false`, since `_adapter_ok` requires `-x`. A host that produced a full report last night then produces nothing, every night.
- BSD find exits 1 when a single subdirectory is unreadable or vanishes mid-walk while still printing every other match (verified: 3 files, one locked directory, exit 1, two paths printed). Treating that as fatal threw away a usable corpus and produced no report on a night that previously produced a full one.
- Reading the adapter through process substitution hid the producer's exit code, so a root that failed on permissions or I/O emitted nothing and the run finalised a cheerful "no sessions" report over a corpus it never saw.

## Decision
- Both `sessions.txt.raw` and `.src` are truncated and checked; failure to write either is a fatal (`cannot write the session lists`).
- When no adapter is enabled, the two causes get different messages (the loader accepted nothing, versus it accepted adapters but none is enabled), because the first sends the reader hunting a containment or manifest failure that never happened for the second. The marker and banner come from `fatal_exit` (see `fatal-exit-marker-and-banner`); `log_fatal` carries the reason to it.
- Enumeration is staged to a file and its status is CHECKED. The distinction is output, not status: nothing read from a root AND a failure counts `ROOTS_FAILED`, logs that the root contributes NO sessions and moves on to the next root (the run does not stop; an old comment in the code said it did, and was stale); something read with a failure is a partial walk, counted in `PARTIAL_ROOTS` and logged as a possibly INCOMPLETE corpus.
- The "all configured roots unavailable" fatal is about roots never REACHED (`ROOTS_SCANNED` is 0 with `ROOTS_CONFIGURED` above 0, and the roots are not the bare fallback). It deliberately does NOT subtract `ROOTS_FAILED`: that looked symmetric and was a regression, because on a single-root host (the default install) "enumerator exited nonzero and returned nothing" is the exact shape of a quiet date plus any transient find error, and that host would then get no report on a night whose honest answer is the empty-night stub. A failed root is not silent regardless: it warns in the log, increments `roots_failed`, reaches `run-stats.txt` on both the zero-session and full paths, and PROMPT.md's Corpus integrity bullet names it in the morning report. That is the right weight for "we read less than we meant to": a caveat on the night, not the loss of it.

## Consequences
Do not "fix" the asymmetry: the fatal at the end of `scan_roots` tests `ROOTS_SCANNED` (roots never reached) and deliberately does not subtract `ROOTS_FAILED` (roots reached whose enumerator failed with no output). A host with no roots configured (`ROOTS_CONFIGURED` 0) stays legitimate and is not fatal; without that guard `RAW` and every shortfall counter would be 0 and the stub would say no files were modified. Do not switch the enumeration back to `<( ... )`. See CLAUDE.md, "Self-audit" for the degraded-measurement rule.
