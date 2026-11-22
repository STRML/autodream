# bin-b: an oversized transcript is read through a lossy, representative slim

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (default mode: line cut, head and tail, byte cap)

## Context

Some sessions are enormous: 4500+ lines, about 10 MB, with base64 images and giant tool outputs. The L1 haiku worker cannot read 20 such lines without blowing the 25k-token Read limit, so it gave up and returned an error finding instead of triaging. Those large sessions are often the most interesting ones.

## Decision

`run.sh` calls the slimmer only for sessions over `AUTODREAM_SLIM_BYTES`; smaller ones are read verbatim. The default mode caps the damage in three steps:

1. Cut every line to a maximum width, which removes base64 blobs and huge tool outputs.
2. Keep the head and the tail and elide the middle, which is usually repetitive churn.
3. Hard-cap the total bytes as a last safety net.

A lossy view is acceptable because triage is fuzzy pattern-spotting, not strict JSON parsing: a representative transcript still yields useful findings.

## Consequences

Lossy has a measured limit. On a real 3,479-line session the head and tail were mostly bookkeeping records and the line cut deleted the timestamp, so the worker saw 17% of the lines and about 2% of the text. The reshape and full modes, and the chunked reader that uses them, exist for that reason; see the CLAUDE.md section "Reading a long session: chunked triage" and `bin-b-slim-transcript-reshape-is-a-denylist.md`. With chunking off, the head/tail view above is what a worker sees, byte for byte.
