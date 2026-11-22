# bin-a: failure classes are judged on what the worker printed, with every line `run.sh` wrote skipped by its exact text

Status: accepted · Date: 2026-11-21 · Code: `bin/failure-class.sh` (`worker_text_of`)

## Context

`run.sh` builds a failed worker's `.err` in this order: the worker's stderr, then its own notes (the timeout line, the malformed-output dump, the session-path line, and the staging and sandbox lines from #169), the exit-code line, the stdout section, and finally the omp log tail and the network notes. A session path or a dumped findings JSON can say "quota" or "HTTP 500" without any provider refusing anything. CLAUDE.md, "A failed worker leaves its evidence, and the failure is classified", describes the classes.

## Decision

`worker_text_of` prints only what the worker itself printed: everything before the `worker exit code:` line except the lines `run.sh` wrote, then the stdout section. Each `run.sh` line is skipped by its exact text. The stdout section ends only at `run.sh`'s next marker (the omp log line, the `curl could not be run here` line or the `no route to` line). It does not end at any `--- ` line a worker might print. The decision came out of Codex reviews of b19ec84 and 7eda1a8.

## Consequences

A new line that `run.sh` writes into the `.err` must be added to the skip list here, or the classifier reads it as worker output. CLAUDE.md warns that any new line in the `.err` would be read as worker output (before the exit-code line) or as worker stdout (after it).
