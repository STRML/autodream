# runsh: every write and read of the session worklist and its provenance index fails closed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots`, `build_source_sidecar`)

## Context

Collision detection exists so two sessions never reach dispatch onto one `<hash>.json`. Every way its bookkeeping can fail silently arrives at that same overwrite:

- Losing one half of the paired write (`sessions.txt.raw` or `.src`) desynchronises the worklist from its provenance, and the collision detector reads the provenance half.
- If `.hash-to-path` cannot be written, every path looks unseen and no collision is ever detected. If `.collided` cannot be appended, the drop set is short and the fatal dedup block is bypassed.
- `grep -qxF ... || continue` treated "legitimately absent" (exit 1, dropped at enumeration) and "grep failed" (exit >1) as the same thing. On an I/O error that skips the row silently, so a collision may never be detected and the unchanged worklist is dispatched with both paths on one artifact: failing open on the way in to a check that fails closed on the way out.
- A write-only `.hash-to-path` passes the truncate and append guards and still cannot be read, so awk's read error returns empty, indistinguishable from "hash unseen"; every path would look new and `.collided` would stay empty.
- A silent `|| :` on the sidecar write drops rows on a full disk, and `SESSIONS_BY_SOURCE` is then computed from the short sidecar and reported as fact.

## Decision

The paired session-list writes are both checked (`log_fatal` and `rm -f` of the staging file on failure). `build_source_sidecar` truncates `sessions-source.txt`, `.hash-to-path` and `.collided` up front and refuses to run blind if any cannot be written. The worklist membership check switches on grep's status (0 present, 1 skip, other fatal). The `.hash-to-path` lookup checks awk's status. The sidecar append is checked. Each failure is `log_fatal` plus `return 1`.

## Consequences

Do not add a `|| :` or `|| continue` to any of these to make a test pass. The only deliberately survivable failures in this function are the sidecar row rewrites, see `collided-sessions-dropped-both-and-verified`.
