# bin-b: `AUTODREAM_SLIM_FULL=1` keeps every line, applies no byte cap and appends no footer

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (the output block and the footer `printf`)

## Context

The chunker sizes pieces itself at line boundaries. The footer is plain text, so in full mode it would land in the last chunk as a line that is not JSON, which the worker would read as transcript. The chunk note and the triage prompt already say that long lines are cut.

## Decision

Full mode skips head/tail elision, the byte cap and the footer. Lines are still cut to `AUTODREAM_SLIM_MAXLINE`, so each chunk parses as JSONL only for the chunker's own contract, not for a slimmed input. With the mode off, a plain call writes exactly what it always did.

## Consequences

Turning chunking off restores the head/tail view byte for byte. CLAUDE.md, "Reading a long session: chunked triage", is the rest of the design.
