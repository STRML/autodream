# bin-b: the triage model call runs from the isolated work directory and wipes its project bucket

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (`WORK_DIR`, `clean_work_bucket`)

## Context

Claude Code's AI-title generation writes a one-line stub into the launch cwd's project bucket even with `--no-session-persistence`. Launched from the home directory, those stubs polluted real session history. See CLAUDE.md, "The AI-title stub vector (second-order self-pollution)".

## Decision

The engine runs from `$AUTODREAM_DIR/work`, the same directory `run.sh`'s workers use. The bucket that directory maps to under `$PROJECTS_DIR` is removed before the call and after it.

## Consequences

The model reads and writes only by absolute path, so the cwd carries no other meaning. Keep the work directory identical to `run.sh`'s, or the wipe misses the bucket.
