# runsh: L1 workers launch from the isolated work dir so an AI-title stub lands in the work bucket

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `cd "$WORK_DIR"`)

## Context
Claude Code writes an AI-title stub into the launch cwd's project bucket. Workers that ran from `$HOME` polluted the real session history (339 stubs between 2026-05-25 and 2026-06-02).

## Decision
The worker does `cd "$WORK_DIR"` (best effort) before the engine call, so any stub lands in `$WORK_BUCKET`. All paths used afterwards are absolute, so the `cd` is safe.

## Consequences
A relative path added to the worker after this line would resolve against the work dir. See CLAUDE.md, "The AI-title stub vector (second-order self-pollution)", and the work-bucket write-list ADR.
