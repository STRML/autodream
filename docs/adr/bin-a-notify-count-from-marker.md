# bin-a: the banner's question count comes from the report's marker, with a tiered fallback only for reports that predate it

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (`MARKER`, `COUNT`, `count_matching`)

## Context

PROMPT.md requires L2 to close the Open questions section with `<!-- autodream:open-questions=N -->`, where N is the count that survived its triviality gate. `review.sh` reads the same marker to decide whether the morning triage session is worth opening. The marker is the only source that knows which candidates L2 considered and dropped. Counting list markers and hoping they line up with questions does not work: measured against the 14 reports on disk when this was written, the old single-pass `grep` disagreed with the marker on 4 of the 9 reports that carry one. The 2026-07-24 report had 1 real question and was counted as 6, because the "Other findings dropped by the gate" bullets below it each scored. A banner claiming six questions over one teaches people to stop reading banners.

L2 has emitted the section as a numbered list, as bullets under bold subheadings, as plain bullets and as bare prose. Counting every format at once double-counts the sub-bullets under an item.

## Decision

- The marker wins when present.
- Without one, take the first format tier that matches: numbered items, then bold titles, then bullets, then 1 for bare prose.
- A first line starting with "None" is zero and stays silent. Without that case the prose tier turns every quiet night into a false pop.
- The section's boundaries come from `report_questions` in `report-format.sh` (the questions block sentinels, the markdown heading only as the legacy fallback), so this script and `review.sh` cannot disagree about where the section stops.

## Consequences

CLAUDE.md, "The triage prompt is questions-only", explains the sentinels. Changing the marker format in PROMPT.md means changing `report_marker_count` and this fallback together, and `tests/review-skip.sh` covers the marker contract.
