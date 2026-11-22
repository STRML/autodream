# rest: engine-prefix builds the prefix from the adapter's own write list, split without a temp file

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`cmd_engine_prefix`)

## Context

Setup and every worker call must build the same prefix from the same list, or a list that cannot be confined is found only when a worker runs. The list also has to survive its own parsing: a temp file or loop that fails part-way would leave an empty list behind, and an empty list is a valid, narrower sandbox that silently drops state paths the engine needs.

## Decision

`engine-prefix <adapter.sh> <stage>` runs `<adapter.sh> l1-writes` and exits 1 with the reason when the adapter declares no write profile (exit 2) or fails for another reason (first 200 characters of its stderr, exit status in the message). The list is one path per line, split by `IFS` alone (globbing is off for the whole script) into the positional parameters, with no here-string and no loop, so there is no temp file whose failure could leave an empty list. An adapter refuses to print a path that holds a newline, since a line is the only separator there is. `IFS` is restored before the prefix is built.

## Consequences

An adapter whose `l1-writes` exits nonzero for any reason is unconfinable, not unconfined by accident: the runner treats that as a setup failure. Do not replace the split with a `read` loop or a here-string without keeping the property that a failure cannot yield a shorter list.
