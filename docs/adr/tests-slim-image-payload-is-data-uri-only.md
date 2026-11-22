# tests-slim: only an inline `data:` URI counts as an image payload

Status: accepted · Date: 2026-11-22 · Code: `tests/slim-transcript.sh` (`# slim: image payloads leave, in BOTH shapes`, `# slim: OMP image .data is stripped only when it IS a payload`)

## Context

The image branch claimed to strip base64 data from the day it was written and did not, for `image_url`: it set `.source` (Claude's field) on a block whose payload lives at `.image_url.url`, so the base64 stayed and the record gained a marker saying it had gone, a receipt for a deletion that never happened. The OMP side was grounded in the corpus: all 289 image blocks across 400 real OMP transcripts on the author's host carry `blob:sha256:<hash>`, a 76-character content-addressed reference, 22 KB in total against a 262144-byte cap.

## Decision

The slimmer strips an image only when it holds an inline payload (`data:image/...;base64,...`), in both the Claude and the OpenAI-style shape. A `blob:sha256:` reference survives with its `mimeType`; marking it stripped would delete an identifier and reclaim nothing. Tests assert the payload is gone and the metadata is kept, and that a blob reference stays.

## Consequences

A marker must only be written when bytes were removed. If OMP changes how it stores images, re-measure the corpus before widening what counts as a payload.
