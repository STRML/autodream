# 0048: slim-transcript suite: assertions that can fail and discriminating fixtures

Status: accepted · Date: 2026-11-22 · Code: `tests/slim-transcript.sh` (`slim_one`, `slim_re`, `hasnt`, `jq_is`), `tests/slim-transcript.sh` (`# slim: with both modes unset ...`), `tests/slim-transcript.sh` (null-content, arguments, details, reshape and OMP cases), `tests/slim-transcript.sh` (`# slim: image payloads leave, in BOTH shapes`, `# slim: OMP image .data is stripped only when it IS a payload`)

## the helpers fail closed, so an assertion that cannot fail does not exist

### Context

The jq pre-pass in `bin/slim-transcript.sh` handles two schemas that keep tool output in different places. It fails silently: jq exits 0 and writes a valid file, the shell fallback never fires, and the line pass downstream truncates an OMP envelope at `"content":[`. The worker then gets ID soup and returns no findings, which looks like a quiet day. Exit status therefore proves nothing. Each rule below is a first-version bug in this suite:

- A `hasnt` over an empty slimmer output was vacuous, so a slimmer that emits nothing satisfied all of them.
- `hasnt '\\"file\\"'` meant "not stringified", but jq emits one backslash, so it could never match and survived the red-then-green check.
- Ignoring jq's exit status let a record that produced the expected value and then hit malformed bytes pass.
- A failed run left the previous case's `out.txt` for the next grep to read.
- Returning only the first output record let a clean first line followed by the original payload pass every negative assertion.

### Decision

Assertions check what survives the strip. `hasnt` fails on empty input. Type and presence claims go through jq, never a substring. `slim_one` removes the destination first, returns 1 on a failed run, and prints the whole output (`jq_is` picks the first record itself). Head, tail and cap are raised far out of reach so only the pre-pass is under test.

### Consequences

A new helper or assertion must be shown to fail with the guarded code removed. Do not shorten `slim_one` to a single-record grep.

## the default path is pinned by a golden digest from before the reshape landed

### Context

`AUTODREAM_SLIM_RESHAPE` and `AUTODREAM_SLIM_FULL` default to 0, and `run.sh` passes both as `0` when chunking is off. Off must mean the old output byte for byte. A comparison of "reshape off" against "reshape off" through the new code cannot detect a change that leaks into a plain call.

### Decision

The digest `6ef17cb7...` was taken with `bin/slim-transcript.sh` as it stood on `origin/main` before the reshape landed, over a 2,800-line Claude-shaped fixture (envelope fields, bookkeeping records, hook attachments, thinking signatures) large enough to hit the head/tail elision and the footer. The call runs with both variables unset (`env -u`), and the test compares the SHA-256 of the output.

### Consequences

An intentional change to the default output means a new digest, taken and reviewed as such, not a casual update. The fixture must keep its size, or the elision and footer paths drop out of the pin.

## each fixture carries the shape that tells the guarded code from its absence

### Context

Several cases would stay green with the guarded code deleted unless the fixture or the second assertion is exactly right.

### Decision

- `.content` null: assert both `has("content")` and `type == "null"`. `type` alone reports "null" for an absent key, so a regression that deleted `.content` would pass it.
- `arguments`: one fixture omits `arguments`. Without it, a bare `.arguments = (...)` assignment would invent the key and every other assertion would still pass.
- `details`: a fixture with `details: null`. `has("details")` is true for null, so every marker site announced a removal that never happened when the field was present but empty.
- Reshape mode: every fixture is paired with a sentinel conversation record. When the pre-pass emits nothing, the script treats it as a jq failure and falls back to the raw line pass, which hands the dropped record straight back and fails the "dropped" assertion for the wrong reason.
- OMP records through reshape: the denylist must never touch a record it does not name. OMP lines are not byte-identical to the file (the pre-pass always re-serialises with `jq -c` and strips toolResult payloads), so the test checks the denylist leaves them alone. An allowlist bug here deletes every OMP record.

### Consequences

Removing a null, omitted or sentinel fixture removes the only thing that discriminates the guarded code from deletion.

## only an inline `data:` URI counts as an image payload

### Context

The image branch claimed to strip base64 data from the day it was written and did not, for `image_url`: it set `.source` (Claude's field) on a block whose payload lives at `.image_url.url`, so the base64 stayed and the record gained a marker saying it had gone, a receipt for a deletion that never happened. The OMP side was grounded in the corpus: all 289 image blocks across 400 real OMP transcripts on the author's host carry `blob:sha256:<hash>`, a 76-character content-addressed reference, 22 KB in total against a 262144-byte cap.

### Decision

The slimmer strips an image only when it holds an inline payload (`data:image/...;base64,...`), in both the Claude and the OpenAI-style shape. A `blob:sha256:` reference survives with its `mimeType`; marking it stripped would delete an identifier and reclaim nothing. Tests assert the payload is gone and the metadata is kept, and that a blob reference stays.

### Consequences

A marker must only be written when bytes were removed. If OMP changes how it stores images, re-measure the corpus before widening what counts as a payload.
