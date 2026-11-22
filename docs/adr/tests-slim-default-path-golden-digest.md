# tests-slim: the default path is pinned by a golden digest from before the reshape landed

Status: accepted · Date: 2026-11-22 · Code: `tests/slim-transcript.sh` (`# slim: with both modes unset ...`)

## Context

`AUTODREAM_SLIM_RESHAPE` and `AUTODREAM_SLIM_FULL` default to 0, and `run.sh` passes both as `0` when chunking is off. Off must mean the old output byte for byte. A comparison of "reshape off" against "reshape off" through the new code cannot detect a change that leaks into a plain call.

## Decision

The digest `6ef17cb7...` was taken with `bin/slim-transcript.sh` as it stood on `origin/main` before the reshape landed, over a 2,800-line Claude-shaped fixture (envelope fields, bookkeeping records, hook attachments, thinking signatures) large enough to hit the head/tail elision and the footer. The call runs with both variables unset (`env -u`), and the test compares the SHA-256 of the output.

## Consequences

An intentional change to the default output means a new digest, taken and reviewed as such, not a casual update. The fixture must keep its size, or the elision and footer paths drop out of the pin.
