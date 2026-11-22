# bin-b: a repo is suggested for triage only past a threshold, with write access, outside a cooldown

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-candidates.sh` (`read_issues`, `can_triage`, `held_back`)

## Context

Without limits the same backlog would be suggested every night, and an upstream project whose tracker the user cannot label would be suggested at all. The user-facing rules are in the script's `--help` text.

## Decision

- Untriaged means no state label (`needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) or an explicit `needs-triage`. A never-triaged repo has no state labels, so every open issue counts: its first triage is what the list exists for.
- `AUTODREAM_TRIAGE_MIN` sets the threshold. `AUTODREAM_TRIAGE_COOLDOWN_DAYS` holds a repo back after a suggestion unless the count has grown by `AUTODREAM_TRIAGE_GROW`.
- The permission and archived check (`gh repo view`) runs only for repos that cleared the threshold, so the extra call is spent where it matters.
- The script reads only. It always exits 0 once it has an output directory, because a failure here must not cost the night's report.

## Consequences

`tests/triage-candidates.sh` pins one row per case of the failure matrix. A new skip reason needs a row there.
