# runsh: every changelog source failing in one run posts a warning banner, one failing posts nothing

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_warn_all_failed`)

## Context

Every source failing is a broken fetch path on this host (lost credentials, a rewritten URL, no network), not a quiet night upstream, and the per-source lines sit in a findings file nobody reads until the report. A single failing source is already in its own section. See CLAUDE.md, "Upstream changelog window".

## Decision

When `failed` equals `sources` (and is above zero), `changelog_warn_all_failed` logs and runs `notify.sh --warning <date> "upstream changelog check failed for all N source(s); first: <first error>"`. A notify failure is logged and not fatal. `--warning` is used so the banner does not say FAILED or drop a `<date>-FAILED.txt` into the inbox for a run that still writes its report.

## Consequences

Do not escalate a single failing source to a banner.
