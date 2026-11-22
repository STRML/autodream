# runsh: no L2 model is pinned by default; a pin must be an exact string

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, L2 engine and model resolution; `adapter_l2_model`)

## Context
A pin is a decision to re-make every time the roster moves, and a date-gated branch (since removed) hid that and left an unreachable default. With no `--model` the aggregator runs on whatever the CLI's default is, so upgrading the account upgrades the nightly report and nothing here has to be edited.

`AUTODREAM_L2_MODEL` overrides, for pinning deliberately. If it is set, pin an EXACT string: the CLI silently falls back on an unrecognized `--model` rather than failing (verified 2026-06-09 on 2.1.170; bare `claude-fable-5` was one of those, where `fable` and the `[1m]`-suffixed form both worked). A silent fallback is why the resolved value is recorded in run-stats (`l2_model`).

## Decision
`L2_MODEL=$(adapter_l2_model "$L2_ENGINE")`; empty means the engine's own default and no `--model` is passed (`${L2_MODEL:+--model ...}`). See CLAUDE.md, "Which engine runs L2".

## Consequences
Do not add a default model here. When someone pins one, check `modelUsage` of a real run, not the flag.
