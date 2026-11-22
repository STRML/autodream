# bin-a: the oversized gate recomputes from artifacts and never reads a clean result from a measurement that did not happen

Status: accepted · Date: 2026-11-21 · Code: `bin/oversized-gate.sh`

## Context

The issue #12 gate is a trailing-window judgment: the share of oversized transcripts that still failed to triage because of size. `run.sh` records one night at a time, and an old runner (#29) may omit the counters, so the gate recomputes the window from sidecars, findings and `.err` files. A false-clean reading is the failure it was written to refuse, and each rule below closes one way a clean number could appear without a measurement behind it.

## Decision

- **Size** comes from the sidecar's `transcript_bytes`. When that is missing or unusable the gate measures the transcript with `wc -c`, which is the same quantity from its original source (#27). A session whose transcript is also gone is counted as unmeasurable and left out of the ratio, never sized at 0.
- **The key** comes from `session_hash` (see `bin-a-lib-project-session-hash.md`), so an empty hash cannot make the gate read the wrong files.
- **A date counts as measured** only when at least one of its sessions was sized. A list of transcripts that are all gone says nothing about size (Codex review of cdfdf3b). When no date in the window was measured, the output says the gate has no evidence either way, because "no oversized transcripts" would claim a measurement that never happened (Auditor verification of 6ca1584).
- **A network-deferred run** (`network_deferred: yes`) is excluded. It stopped before its workers finished, so its oversized sessions were counted but the ones that never ran have no stub, and its share reads lower than the evidence supports. PROMPT.md already says to keep it out of the trailing week.
- **An errored session** is recognized by the top-level `error` key of its findings JSON, not by a text match: a successful file whose evidence quotes an error would otherwise count as a failure with no `.err` to classify.
- **The share** leaves out silent, provider and unclassified failures on both sides of the ratio. When nothing remains, the window gets no verdict. With zero size failures it also prints the rule-of-three bound (95% upper bound about 3/n), so a clean run is not read as stronger evidence than the sample supports.
- A window with no oversized transcripts is reported as "nothing to measure", which "is not the same as a measured 0%" and does not close #12 on its own.

## Consequences

The gate opens at 5% or more (the threshold in the help text). A new failure class has to be added to `failure-class.sh` and to both sides of the ratio here, or it is counted as a size failure by default. `tests/run-all.sh` pins the gate in the `# oversized-gate.sh: a context overflow opens the size gate` section.
