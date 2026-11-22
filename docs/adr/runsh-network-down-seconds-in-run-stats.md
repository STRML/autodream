# runsh: Time blocked on the network is summed and reported in run-stats

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`NET_DOWN_SECONDS`, `wait_for_network`)

## Context
On 2026-09-04 the self-audit could not tell an outage from a transcript problem and blamed 90 minutes of dead network on oversized transcripts.

## Decision
`NET_DOWN_SECONDS` accumulates the seconds this run spent blocked on `wait_for_network`, summed across rounds, and is written to `run-stats.txt` so the self-audit can tell the two apart. Down time runs from the first failed probe to the one that answered; a healthy first probe adds nothing.

See CLAUDE.md, "A dead network or a refusing provider defers the date" (run-stats keys).

## Consequences
The counter must be added to on every exit path of `wait_for_network` that waited (the cap path and the recovery path both do).
