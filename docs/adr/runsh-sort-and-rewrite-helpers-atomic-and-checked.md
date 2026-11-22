# runsh: in-place list rewrites go through two helpers that replace the file atomically and account for every failure

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sort_unique_inplace`, `rewrite_filtered`)

## Context

`sort -u FILE -o FILE` can leave FILE empty or partial when it fails, and every consumer downstream trusts the damaged file. The worklist and the collision drop set both used the unchecked form; the drop set was fixed first and the worklist left, a half-fix.

The same three-line grep-then-mv pattern was patched site by site across four review rounds, and each patch closed one hole and left another: the grep status was swallowed, then checked but the `mv` was not, then the `mv` was guarded but its failure was silent. Three copies meant three chances to get it wrong.

## Decision

`sort_unique_inplace FILE WHAT` sorts to `FILE.su.$$` and `mv`s it over FILE; on failure it removes the temp, `log_fatal`s and returns 1. `rewrite_filtered FILE WHAT <grep args>` writes to `FILE.rw.$$`, treats grep exit 1 as a legitimate empty result and exit >1 as failure, and replaces the file only if the `mv` succeeds. On any failure the original is untouched, a reason is logged and the caller gets a nonzero status to decide whether that is survivable. One helper per job, all callers use it.

## Consequences

Do not inline a new `grep ... > tmp && mv` variant at a call site. The caller decides survivability: the worklist rewrite is fatal, the provenance-row rewrites are `|| :` (see `collided-sessions-dropped-both-and-verified`).
