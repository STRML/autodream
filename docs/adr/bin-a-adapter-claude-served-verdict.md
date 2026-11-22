# bin-a: the claude adapter judges whether the requested model answered

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`served`)

## Context

Only this adapter knows the CLI's naming: `modelUsage` in the result object carries canonical ids (`claude-haiku-5-5`) while a host may ask for a model by alias (`haiku`). The runner's `AUTODREAM_L1_REQUIRE_SERVED` needs a verdict it can trust (CLAUDE.md, "What answered, and whether it counts").

## Decision

`served` prints `<models, comma-joined><TAB><estimated cost USD><TAB>match|mismatch` from the result object, or exits 1 without a result. The models come from `modelUsage`, which lists every model that answered any part of the call. The cost is the CLI's estimate at API prices, not what a subscription bills; it is kept because it compares models on real numbers. The verdict is `match` when every model that answered is the one asked for. A bare family name matches any id of that family (`claude-<name>-...`), a full id only itself, and a context suffix such as `[1m]` is ignored on both sides. An alias the family rule cannot read (`default`, `opusplan`) is a `mismatch`: the runner then cannot vouch for the model, which is what `AUTODREAM_L1_REQUIRE_SERVED` asks.

## Consequences

An engine whose adapter has no `served` verb (omp) is `unmeasured`. A new model-family naming scheme that does not start with `claude-` would read as a mismatch.
