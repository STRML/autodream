# tests-slim: each fixture carries the shape that tells the guarded code from its absence

Status: accepted · Date: 2026-11-22 · Code: `tests/slim-transcript.sh` (null-content, arguments, details, reshape and OMP cases)

## Context

Several cases would stay green with the guarded code deleted unless the fixture or the second assertion is exactly right.

## Decision

- `.content` null: assert both `has("content")` and `type == "null"`. `type` alone reports "null" for an absent key, so a regression that deleted `.content` would pass it.
- `arguments`: one fixture omits `arguments`. Without it, a bare `.arguments = (...)` assignment would invent the key and every other assertion would still pass.
- `details`: a fixture with `details: null`. `has("details")` is true for null, so every marker site announced a removal that never happened when the field was present but empty.
- Reshape mode: every fixture is paired with a sentinel conversation record. When the pre-pass emits nothing, the script treats it as a jq failure and falls back to the raw line pass, which hands the dropped record straight back and fails the "dropped" assertion for the wrong reason.
- OMP records through reshape: the denylist must never touch a record it does not name. OMP lines are not byte-identical to the file (the pre-pass always re-serialises with `jq -c` and strips toolResult payloads), so the test checks the denylist leaves them alone. An allowlist bug here deletes every OMP record.

## Consequences

Removing a null, omitted or sentinel fixture removes the only thing that discriminates the guarded code from deletion.
