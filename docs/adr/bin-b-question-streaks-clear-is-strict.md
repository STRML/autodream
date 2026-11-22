# bin-b: `clear` validates its key, takes the update lock first, and fails when it cannot forget

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`cmd_clear`)

## Context

An operator told a streak is forgotten must not find it still escalating tomorrow. Each rule below closed a way that happened or nearly did.

## Decision

- A key is exactly what `key_of` prints: 12 lowercase hex characters, refused otherwise before awk sees it. awk would compare numeric-looking keys as numbers (`89709551468` matching `089709551468`) and `awk -v` decodes backslash escapes (Codex reviews of 5f7ddaa and b67c2f1). The key comparisons in `streak_field` and `cmd_clear` use `$1"" == k""` for the same reason.
- `clear` takes the same lock as `update`, before its empty check. An update that already read the old state would write it back and the cleared streak would return (Codex review of 232c94c), and an update holding the lock may be about to write the first streak onto an empty board (Codex review of 4eea84d). With no state directory there is nothing to lock or clear, so that stays a no-op.
- A key no streak carries is a failure (#32), not a no-op. Printing "cleared" for a mistyped key left the real streak escalating.
- It keeps the watermark.

## Consequences

`update` exits 0 whatever happens; `clear` is the command that reports failure. Do not loosen the key pattern without keeping the string comparisons.
