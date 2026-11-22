# bin-b: the pre-pass never invents a key, never stringifies null, and strips an image where its data lives

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (the pre-pass `jq` program: `payload`, `trunc`, `trunc_at`, `strip`)

## Context

The first version of the pre-pass fabricated structure it was supposed to remove. Each item below was a real bug, verified with jq before and after.

## Decision

- `trunc` applies `tostring` only to a value over the cap and never to null. Run unconditionally, it gave a `toolResult` with `.content` null the literal string `"null"`, invented the key on a record that had none, and flattened a structured `.arguments` object to an escaped string while it was 40 times under the cap.
- `trunc_at` and `strip` act only when the key is present or the value is a `payload` (not null, and not an empty object). A bare presence check is true for null, so every guard turned a null into a marker announcing a payload had been stripped, a false claim. A thinking block with no `thinking` key came out with `thinking: ""` for the same reason, which is why there is no `// ""`.
- The two image shapes keep their data in different places. Claude puts the base64 in `.source`, an OpenAI-style `image_url` block in `.image_url.url`, and OMP in `.data`. Each is stripped where its data lives. Setting `.source` for both left the `image_url` payload intact beside a marker saying it was removed.
- OMP `.data` is not always a payload: across 400 real OMP transcripts on this host, all 289 image blocks carry `blob:sha256:<hash>`, a 76-character content-addressed reference totalling 22 KB against a 262144-byte cap. Replacing them with a marker would delete an identifier triage can use and save nothing. Only a `data:` URI is stripped, and anything else goes through `trunc`.
- `tool_result` blocks keep `tool_use_id` and `is_error`, so triage still sees which call failed; only the content goes.

## Consequences

A new guard must pass the test for an absent key, an explicit null and an empty object. `tests/slim-transcript.sh` pins each case.
