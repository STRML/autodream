# runsh: a directory under adapters/ makes an adapter accepted, not enabled; the host enables it with AUTODREAM_ADAPTERS

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`_enabled_adapters_uncached`, `AUTODREAM_ADAPTERS`)

## Context
Which harnesses a run scans is a host decision. Merging a new harness must not change what a live nightly reads.

## Decision
`AUTODREAM_ADAPTERS` is a space- or comma-separated list of names, or `all`, default `claude`. Accepted adapters not in it are logged as "accepted but not enabled" and not enumerated. Hosts that want omp say so in their config. See CLAUDE.md, "Several harnesses in one run: enabled is a host decision".

## Consequences
A new adapter ships dormant; enabling it also needs a re-install if the engine binary has to reach the launchd PATH.
