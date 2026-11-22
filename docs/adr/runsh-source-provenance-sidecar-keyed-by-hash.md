# runsh: source provenance lives in a sidecar keyed by artifact hash, and sessions.txt stays one bare path per line

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`build_source_sidecar`; `session_hash` is in `bin/lib-project.sh`)

## Context

The hash assignments in `l1_missing_count()` and `dispatch_l1()` key each artifact by the sha1 of the WHOLE `sessions.txt` line, `oversized-gate.sh` recomputes the same hash from it, and every archived findings dir depends on that shape. Adding a source field to `sessions.txt`, or including the source in the hash formula, would silently invalidate all of them. See CLAUDE.md, "Where state lives" (`sessions.txt`, `<hash>.json`).

Two sources can still land on one artifact in two ways: the same path claimed twice, and two different paths truncating to one 12-character hash. The original header comment called the first a misconfiguration of two adapters; a later comment in the same function corrected that. `sessions.txt.src` is not deduplicated while `.raw` is `sort -u`'d, so every duplicate seen is one transcript reached through two entries of `SESSION_ROOTS`, which is ordinary on a host where `root-probe` autodetects each `$HOME/.claude*/projects` and one is a symlink of another.

## Decision

`sessions-source.txt` maps `<12-char hash><TAB><source>`; the hash formula is unchanged. `build_source_sidecar` detects the two cases: the same path claimed twice (`DUPLICATE_PATHS`, keep the first, log "duplicate: ... was reached more than once") and two DIFFERENT paths truncating to one hash (`HASH_COLLISIONS`, no sensible winner, drop both, see `collided-sessions-dropped-both-and-verified`). The duplicate message deliberately does not say "claimed by more than one adapter": naming adapters sends the reader after a misconfiguration that does not exist.

## Consequences

The comment's claim that "only `claude` is ever enabled" is stale (the log line now says "two session roots, or two adapters"), but the symlinked-roots explanation is still the common cause. Do not change the hash formula or the `sessions.txt` shape without migrating every archived findings dir.
