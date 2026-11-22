# bin-a: an AI-title stub is ours only if the file has no user turn and the title paraphrases our triage prompts

Status: accepted · Date: 2026-11-21 · Code: `bin/prune-self-sessions.sh` (`is_self_title`)

## Context

Claude Code's async title generation writes a one-line `{"type":"ai-title",...}` record into the worker's session bucket even under `--no-session-persistence`, which only suppresses the full transcript. These stubs carry no conversation, so the first-user-turn rule (see `bin-a-prune-self-sessions-first-turn-predicate.md`) never catches them. CLAUDE.md, "The AI-title stub vector", covers how they accumulated.

## Decision

- A file matches only if it is an orphan: no user turn anywhere. A real session is one file holding its title alongside its turns, so it always has a user turn and is never matched. Only headless calls that did not persist a transcript leave a title-only orphan.
- The title must also describe session triage or findings aggregation. The model-generated titles paraphrase our L1 and L2 prompts, for example "Analyze Claude session findings", "Triage coding session for findings" and "Aggregate daily findings into report". A real headless orphan about an unrelated task (for example "GCU Rush firmware development") is spared.
- Three patterns cover the variants: the L2 aggregator (`aggregate.*findings`, `findings.*(into|report)`); L1 phrasings of "session triage ... findings", where the verb may follow the noun; and L1 "a verb acting on a session or transcript, producing findings, triage or analysis", which needs both halves to match.
- The patterns were tuned against the real backlog: they catch the L1 and L2 title variants and spare terminal-tab-title stubs and unrelated work-session orphans.

## Consequences

Loosening a pattern risks deleting someone's real headless output; tightening it leaves stubs in the session history. Check any change against a real backlog, both for what it catches and for what it must spare. `tests/run-all.sh` covers the helper under `# prune-self-sessions helper: list / filter / delete`.
