# runsh: a built-in claude L2 invocation remains for installs whose adapters tree predates `l2-argv`

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `L2_ENGINE = claude` fallback block; `l2-prompt.sh`, `prompts/L2_SYSTEM.txt`)

## Context
An install whose `adapters/` tree predates `l2-argv` (the per-file symlink installs this script supports, see `enumerate_for`) still has to deliver the night. The fallback is claude-only, for the same reason `enumerate_for`'s is: it hardcodes one engine's invocation. The system prompt is `prompts/L2_SYSTEM.txt`, the same text the adapters read. Without it no argv is built at all (a WARNING fires), because an L2 run with no word on where the report goes only looks like a night's work.

## Decision
When `L2_ARGV` is empty and the engine is `claude`, the runner loads the prompt via `find_lib l2-prompt.sh` / `l2_system_prompt` and builds `claude --print ... --tools Glob Read ... --append-system-prompt`. Otherwise it warns. See CLAUDE.md, "Which engine runs L2".

## Consequences
`tests/l2-prompt.sh` greps `run.sh` for the string `l2-prompt.sh`; keep the loader call. Do not extend the fallback to other engines.
