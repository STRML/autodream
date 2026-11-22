# bin-b: status counts tag lines with grep so it works without jq

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`status`)

## Context

`status` is a quick look by hand, and it is the command a user runs when something does not work. That includes a host with no `jq`.

## Decision

`status` counts lines in the tags file and the ledger with `grep -c .`, not tags parsed by `jq`. A torn line counts here and is skipped by `collect`, so the figure can read high and never low.

## Consequences

The "tagged" figure can exceed what the next report will contain. Parsing with `jq` would give an exact number and make `status` fail where `collect` reports UNREADABLE.
