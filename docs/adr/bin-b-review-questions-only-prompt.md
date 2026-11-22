# bin-b: the triage session is handed only the open questions, all or nothing, through a temp file

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (`QUESTIONS_CAP`, `SYSTEM_TMP`)

## Context

On 2026-10-27 every launch with the whole report inlined was refused with "Opus 5.5's safeguards flagged this session ... [cyber]", including a bare "go". The night's findings, 25 KB of TV-firmware narrative (`sdb`, root status, `dlopen`), read as an offensive-security engagement to the provider's content classifier. The same report's questions section, about 2 KB of decision text, passed. CLAUDE.md, "The triage prompt is questions-only, and that is load-bearing", has the full account.

## Decision

- The prompt inlines the section `report_questions` returns and points at the report file for anything deeper. Which text is "the section" is `report-format.sh`'s contract (`bin-b-report-format-sentinels.md`), so `review.sh` parses no markdown.
- The cap (`QUESTIONS_CAP`, 12000 bytes) is all-or-nothing. A section that does not fit is not inlined, and the prompt tells the session where to read it. Cutting a section at a line, item or fence asks the session to recommend on half a question. The intro text differs for a block report (sentinel names) and a pre-block one (heading name), because the sentinels do not exist in the latter.
- The system prompt is built through a temp file. A heredoc inside `$(...)` is mis-parsed when the body holds apostrophes or a literal `)`.

## Consequences

Never inline a long document into a system prompt. Never launch intent-carrying work with a one-word prompt: the launch text names the task. `tests/review-prompt.sh` pins the contract.
