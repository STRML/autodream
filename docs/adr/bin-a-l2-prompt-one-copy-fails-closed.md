# bin-a: the L2 system prompt has one copy, found through the install symlink, and a missing or blank copy is an error

Status: accepted · Date: 2026-11-21 · Code: `bin/l2-prompt.sh` (`l2_system_prompt`)

## Context

Every L2 engine runs under the same system prompt, kept in `prompts/L2_SYSTEM.txt`, so the claude adapter, the omp adapter and `run.sh`'s built-in claude fallback all say the same thing. It states the stdout grammar that `bin/report-format.sh` parses: the report, `AUTODREAM_REPORT_END`, the optional pin block and the summary. This file is sourced, never executed. CLAUDE.md, "Which engine runs L2", names the same rules.

## Decision

- A change to the grammar is one edit in `prompts/L2_SYSTEM.txt` and one in `report-format.sh`.
- An installed copy of this script is a symlink into the checkout, and the prompt sits beside `bin/` there. The function resolves its own symlink, then looks at `../prompts/L2_SYSTEM.txt`, then at `$AUTODREAM_DIR/L2_SYSTEM.txt`.
- A candidate must hold a non-whitespace character. A file of blank lines would start an engine with an empty instruction.
- When no copy can be read, the function prints the reason on stderr and returns 2. It prints the text with no trailing newline added.

## Consequences

An engine started without this prompt would run L2 with no instruction about where the report goes, and the output would look like a night's work. That is why a missing prompt fails the run and is never defaulted to an empty string.
