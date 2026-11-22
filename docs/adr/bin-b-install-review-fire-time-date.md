# bin-b: the review agent passes yesterday's date, computed when the job fires

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the review plist in `install_schedule`)

## Context

`review.sh` with no date picks the newest report. At 08:00 that is not necessarily yesterday's: a still-running overnight report makes the job triage an older one. CLAUDE.md, "The review triage LaunchAgent", describes the agent.

## Decision

- The plist runs `/bin/bash -c 'exec "$1" "$(date -v-1d +%Y-%m-%d)"' triage <review.sh>`. The `$(...)` and `$1` are escaped in the installer's heredoc so the plist bakes the expression, not a frozen date. `review.sh` then fails fast with "no autodream report found" when yesterday's report has not landed, which is better than silently triaging the wrong day.
- After writing the plist the installer greps for both literal strings (`$(date -v-1d +%Y-%m-%d)` and `exec "$1"`) and aborts if either is missing. If the escaping ever regresses and one expression is pre-expanded, the install fails loudly instead of provisioning a job with the wrong path or date.

## Consequences

Editing the heredoc's quoting means keeping those two greps true.
