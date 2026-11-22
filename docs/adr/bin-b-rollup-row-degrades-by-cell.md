# bin-b: a malformed findings JSON or sidecar costs its own row's cells, never the table

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`session_row`, `ROW_JQ`, `UNREADABLE_JQ`)

## Context

One bad file must not blank the whole roll-up, and a cell nothing measured must not read as a measured zero.

## Decision

- Each session is read by its own `jq` call. `session_row` tries four programs and the first that succeeds wins: the record with its sidecar, the record alone (a sidecar that does not parse or is not an object), the sidecar alone (a record that does not parse), then the bare hash.
- A cell nothing measured is blank, never 0. This covers `sandbox_shape_denies` from a missing or old sidecar and from omp, which does not measure it.
- Text cells go through `@tsv`, so a tab or newline in a value cannot break a row. Category and severity words and skill names have `,`, `:` and `=` replaced, because they sit in comma lists.
- A record whose `findings` is not an array is `unreadable`, judged before the noise gate.

## Consequences

The cost is one `jq` per session (up to four on a malformed one): about 3 seconds for 885 sessions. Batching the files into one `jq` would make a single bad file fail the batch.
