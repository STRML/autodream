# bin-a: report claims are grounded by fixed, read-only checks in code, and a check that cannot run says unknown

Status: accepted · Date: 2026-11-21 · Code: `bin/dream-grounding.sh` (`classify`, `check_skill`, `check_allow`, `check_sha`)

## Context

The report is written by a model reading findings, and its claims about the filesystem go stale or wrong. Examples: "skill X does not exist" when it lives under `~/.claude/skills` and the report only looked in the plugins dir; an allowlist key whose exact text was never compared with `settings.json`; a commit SHA that was never resolved.

The triage pass (`triage-dream.sh`) hands the model this script's JSON as data, so the model never needs a shell. A prompt that says "do not run anything that writes" is weaker than checks fixed in code.

## Decision

- The runner runs a fixed set of read-only, model-free checks and writes one JSON file. Claims come from backticked spans in the report: `skill` (a span on a line mentioning "skill", matched by installed name with any `plugin:` prefix dropped), `allowlist` (a `Tool(...)` rule or an `mcp__` name, matched against the exact string in `permissions.allow`), and `sha` (a 7 to 40 hex span with a digit and a letter, resolved with `git cat-file` as a commit in a known repo).
- A 12-hex span is a findings hash, which `citation-check.sh` owns, so it is never a sha claim.
- Status is `present`, `absent` or `unknown`. `unknown` means the check could not run (no settings file, no repo, no skill listed), never `absent`. The output records `truncated: true` when there were more claims than `AUTODREAM_GROUNDING_MAX` (default 100); the rest were not checked.
- Exit 0 whenever the check ran. Exit 2 when it could not (usage, unreadable report, no `jq`).

## Consequences

An `absent` result is evidence only inside what was searched, and its `evidence` text says so (built-in and project-local skills are not searched; a broader rule or project setting may still allow an allowlist key). Collapsing `unknown` into `absent` would reproduce the wrong "does not exist" claims this exists to catch.
