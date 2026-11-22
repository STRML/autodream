# tests-slim: the helpers fail closed, so an assertion that cannot fail does not exist

Status: accepted · Date: 2026-11-22 · Code: `tests/slim-transcript.sh` (`slim_one`, `slim_re`, `hasnt`, `jq_is`)

## Context

The jq pre-pass in `bin/slim-transcript.sh` handles two schemas that keep tool output in different places. It fails silently: jq exits 0 and writes a valid file, the shell fallback never fires, and the line pass downstream truncates an OMP envelope at `"content":[`. The worker then gets ID soup and returns no findings, which looks like a quiet day. Exit status therefore proves nothing. Each rule below is a first-version bug in this suite:

- A `hasnt` over an empty slimmer output was vacuous, so a slimmer that emits nothing satisfied all of them.
- `hasnt '\\"file\\"'` meant "not stringified", but jq emits one backslash, so it could never match and survived the red-then-green check.
- Ignoring jq's exit status let a record that produced the expected value and then hit malformed bytes pass.
- A failed run left the previous case's `out.txt` for the next grep to read.
- Returning only the first output record let a clean first line followed by the original payload pass every negative assertion.

## Decision

Assertions check what survives the strip. `hasnt` fails on empty input. Type and presence claims go through jq, never a substring. `slim_one` removes the destination first, returns 1 on a failed run, and prints the whole output (`jq_is` picks the first record itself). Head, tail and cap are raised far out of reach so only the pre-pass is under test.

## Consequences

A new helper or assertion must be shown to fail with the guarded code removed. Do not shorten `slim_one` to a single-record grep.
