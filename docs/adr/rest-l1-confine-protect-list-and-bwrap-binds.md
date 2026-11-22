# rest: protected paths are denied after the writable ones, and bwrap binds protected paths read-only, stage last

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`emit_prefix`, `sb_profile`)

## Context

A default install keeps `$AUTODREAM_DIR` under `~/.claude`. A writable rule that covers a directory under `~/.claude` would then grant the engine the runner's own state.

## Decision

`L1_CONFINE_PROTECT` (colon-separated) names paths the engine cannot write even when a writable path covers them. Under `sandbox-exec` each is a `(deny file-write* (subpath ...))` placed after the writable allows, and the stage allow comes last. Under bwrap the writable paths are bound read-write, each protected path is then bound read-only over them, and the stage is bound last, so a protected path wins inside a writable directory and the stage wins inside a protected one.

bwrap binds an existing path, so a prefix rule binds the files that already match it (`~/.claude.json` itself, written in place) and cannot cover a temp file created later. `sandbox-exec` can. Symlinks matched by a prefix are skipped, so a prefix cannot grant a link's target.

## Consequences

The bwrap limit shows up in run-stats as `l1_confine_note` (`runsh-l1-confine-bwrap-prefix-rule-limit`). Reordering the deny and allow lines changes which one wins; the order is the rule. The protect list is built and validated by the runner (`runsh-l1-write-confinement-staging`).
