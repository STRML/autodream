# runsh: session roots resolve SESSION_ROOTS, then an explicit PROJECTS_DIR, then root-probe, and an unasked folder is held out

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`probe_roots`, `write_unindexed_flag`, `scan_roots`, `scan_one_adapter`)

## Context
The nightly once scanned only `$HOME/.claude/projects` and silently stopped seeing the real work (132 -> 7 -> 8 -> 1 sessions/night on 2026-08-03..06). See CLAUDE.md, "Session roots: one dir is not the corpus" for the full decision; what the code adds:

## Decision
- Order: (1) `SESSION_ROOTS` (colon-separated, env or config), authoritative; (2) `PROJECTS_DIR`, only when the caller set it explicitly (`projects-dir-explicitness-recorded`), kept for backward compatibility; (3) neither: autodetect every `$HOME/.claude*/projects` through `root-probe.sh --consolidated`, primary first. If the probe is missing or fails, fall back to the primary dir alone rather than scanning nothing.
- The probe is asked for the DECIDED roots only: the primary plus those `root-choices.conf` says index. An unasked root is held out of the report until the user decides, because that is the point of the flag file (`write_unindexed_flag` -> `unindexed-roots.txt`) the report reads, "found a folder we're not indexing"; scanning an undecided folder would make that flag a lie. Folders the user explicitly ignored are likewise skipped. The flag file is the report surface; the unattended run never prompts.
- A last-resort default is NOT a configured root. Discovery returning nothing means a fresh host with no store yet, and that has to stay a legitimate quiet night, so `SESSION_ROOTS_ARE_FALLBACK=1` marks the fallback and the all-roots-unavailable fatal (see `scan-roots-fails-loudly-not-quietly`) must not fire on it.
- SESSION_ROOTS is colon-separated, so a root path containing `:` is unrepresentable: the split already fragmented it. `scan_one_adapter` catches the symptom (a fragment that is not a directory), counts it in `ROOTS_UNAVAILABLE` and logs a WARNING naming the cause, rather than silently scanning nothing.
- A transcript reachable from two roots (one dir a symlink of another) must be triaged exactly once: `sort_unique_inplace` (`sort -u`) dedupes the raw worklist, and the run is fatal if the dedupe itself fails.

## Consequences
Do not make the probe scan every `~/.claude*` folder: the "unindexed root" flag would become a lie. `WORK_BUCKET` stays keyed off the primary dir (see `worker-cwd-isolated-work-bucket`).
