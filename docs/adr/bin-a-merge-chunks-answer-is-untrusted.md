# bin-a: a chunk answer is untrusted, `--check` judges exactly one value, and the merge refuses to merge around a bad one

Status: accepted · Date: 2026-11-21 · Code: `bin/merge-chunks.sh` (`CHUNK_OK`, `chunk_ok`, the pre-merge loop)

## Context

A worker can write the error object the prompt tells it to emit on malformed input, a bare `{}`, a wrongly typed field, or two values in one file, and a transcript can nudge it to. Plain `jq -e .findings` judges only the last value in a file, while the merge slurps them all. So an error object followed by a good object used to pass. CLAUDE.md, "Reading a long session: chunked triage", describes the same rule from the runner's side, and `tests/merge-chunks.sh` is the contract.

Call shapes and exits:

- `merge-chunks.sh --check FILE` exits 0 only for a usable chunk answer, else 1.
- `merge-chunks.sh --session PATH [--elided N] CHUNK.json ...` writes the merged object to stdout and exits 0. It exits 2 on bad usage and 3 when any chunk fails `--check`, with stdout left empty. Any other nonzero comes from jq failing.

## Decision

- A usable answer is exactly one JSON value, an object, with no `error` key and a `findings` array. `CHUNK_OK` runs over the whole file with `jq -s`, so a second value cannot hide behind a good first one.
- The test is `has("error")`, not a null test, because the runner treats any `error` key as a failed triage.
- `--check` is the one definition. The runner uses it before it keeps an answer for a retry, and the merge enforces it again itself instead of trusting its caller to have.
- A bad answer is retried. It is never cached and never merged around, because a session built from some of its chunks would read as if it were all of them.

## Consequences

Any new place that keeps or reads a chunk answer must call `--check`. A weaker test (`jq -e .findings`, a null check on `error`) reopens the error-then-good-object hole.
