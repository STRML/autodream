# bin-a: the L1 worker runs with a replaced system prompt, JSON output and an explicit effort, and the warmup shares its permission, model, effort and isolation flags

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`l1-argv`, `warmup-argv`, `l1_effort`)

## Context

CLAUDE.md, "How claude is invoked" and "Who starts the L1 worker", has the lean-query rationale. The points a future editor would get wrong:

- `--system-prompt` replaces Claude Code's default prompt, about 1.9k tokens a call. Measured 2026-10-07: 6.9k to 5.0k input tokens on a one-word call, and 26% cheaper on a real triage run with the same findings count. The worker prompt is self-contained, so nothing is lost. Tools are already Read and Write only, with hooks, skills, MCP and CLAUDE.md off.
- `--output-format json` makes stdout one small result object that names the models that answered, read back by `served`. Not `stream-json`: `--verbose` would echo every Read result, the whole transcript, onto stdout, and a failed worker copies its stdout into the `.err`.
- The text of the system prompt must not be shell-expanded: it names the output path literally, hence the escaped dollar sign in the text.
- Haiku 5.5 trades cost for quality on the effort dial, and triage yield was the weak point of the old Haiku, so the default leans to quality (`high`); the pricing makes that cheap.

## Decision

- `l1-argv` is the invocation `run.sh` hard-coded before the engine moved behind the adapter. `tests/adapter-claude.sh` pins it against that literal text, so a change here that alters what the nightly runs has to say so.
- Effort resolves `AUTODREAM_L1_EFFORT_CLAUDE`, then `AUTODREAM_L1_EFFORT`, then `high`. `off` omits the flag, leaving the model's own default. An unknown level is an error (exit 2 from both argv subcommands), never a silent fallback.
- `warmup-argv` keeps the worker's permission mode, model, effort and isolation flags (no session persistence, no slash commands, MCP strict, hooks off). It differs in three places: no `--output-format json` (its stdout must be the word `ok`), `--tools Read` only, and a system prompt that asks for one word instead of a findings file. A warmup on a different login path would refresh a token the workers never use.

## Consequences

Changing the permission, model, effort or isolation flags in one argv without the other makes the warmup stop proving what the workers need.
