# bin-a: "is this session ours" is decided by the first user turn, in one script every caller asks

Status: accepted · Date: 2026-11-21 · Code: `bin/prune-self-sessions.sh` (`SELF_RE`, `first_user_turn`, `is_self`, `--is-self`, `--filter`)

## Context

Every `claude --print` worker used to persist its own session JSONL, and the next night triaged them as real sessions (~190 self-generated files a night, about 90% of the corpus, per the script's help text; CLAUDE.md, "Self-pollution", has the full account). The enumeration filter must drop those without ever dropping a human session that merely discusses autodream, for example one that mentions `SESSION_PATH=` mid-conversation.

## Decision

- A session is ours when its first user turn starts with one of our inlined prompts: `Session transcript to analyze (literal absolute path)`, `Findings directory to aggregate (literal absolute path)`, or the legacy `SESSION_PATH=` and `FINDINGS_DIR=` framings from earlier runs. The pattern is anchored to the start of the message content, which is what keeps a discussion of autodream from matching.
- Two transcript shapes carry user content. Claude stores a string (`{"type":"user",...,"content":"..."}`). OMP stores an array of items (`{"type":"message","message":{"role":"user","content":[{"type":"text","text":"..."}]}}`). The anchor `(content":"|text":")` matches both.
- `first_user_turn` finds the first record of either shape, with `grep -m1` over both patterns. Assistant and tool records never match, so callers always get the first user turn.
- The predicate lives only here. The adapter contract asks the question about one file through `--is-self`, and `run.sh` calls `--filter`. Exposing the predicate beats letting each adapter carry its own copy of the marker list: a marker added to `SELF_RE` must not have to be remembered in a second place.

## Consequences

A new prompt framing that autodream sends to a worker must be added to `SELF_RE`, or its sessions will be triaged as real. `tests/run-all.sh` covers the helper under `# prune-self-sessions helper: list / filter / delete`.
