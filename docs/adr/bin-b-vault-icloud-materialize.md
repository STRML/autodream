# bin-b: iCloud-evicted notes are materialized with two tools, waited for under a cap, and reported when still missing

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`materialize`, the placeholder pass in `collect`)

## Context

The vault lives in iCloud Drive. macOS evicts file contents under storage pressure and replaces the file outright with a dot-prefixed `.<name>.icloud` placeholder. launchd fires at 03:15, when nothing has touched the vault for hours and eviction has had time to happen.

## Decision

- `materialize` runs both `brctl download` and `fileproviderctl materialize`, then polls for `.*.icloud` placeholders every 2 seconds up to `AUTODREAM_ICLOUD_WAIT` (default 30). Neither tool alone is reliable. `brctl` predates the FileProvider migration (Monterey) and on a current system often succeeds while doing nothing, which would reduce the wait to a passive timeout dressed up as a fetch. A missing tool or a failure of either is not an error.
- The cap means a broken iCloud daemon costs seconds, not the run.
- An evicted note is not a zero-byte `foo.md`, so the `*.md` walk matches nothing and its UNREADABLE branch (written for zero-byte files) never fires. A note the user wrote on a phone would then show as `unreadable: 0`, which reads as "nothing was missed". Placeholders therefore get their own pass, which emits a `## note: <name> - UNREADABLE` block and counts it.
- A placeholder whose real file has also appeared is skipped, so one note is not counted twice.
- Placeholders are not manifested. The note has not been read, so it stays in the inbox for the next run to retry.

## Consequences

CLAUDE.md, "Operator notes", and the "Bash traps this feature hit" list record the same facts. `tests/run-all.sh` covers the placeholder case. The rule is the one `overlap_measured` follows: a degraded measurement says so and never reads as zero.
