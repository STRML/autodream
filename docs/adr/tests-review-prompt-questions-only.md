# tests-review-prompt: the triage session gets the questions block only, and the fixtures prove the body stays out

Status: accepted · Date: 2026-11-22 · Code: `tests/review-prompt.sh` (`mk_report`, `test_block_content_is_inlined_findings_not`, `test_markdown_inside_the_block_is_text`)

## Context

`review.sh` used to pass the whole report through `--append-system-prompt`. On 2026-10-27 that refused every launch. The 2026-10-26 report narrated a night of Samsung TV work (`sdb`, root status, `dlopen`), and the Opus 5.5 classifiers answered "safeguards flagged this session ... [cyber]" before the first reply, on the literal prompt `go`. The questions section (about 2 KB of decision text) passes and the findings body does not. CLAUDE.md, "The triage prompt is questions-only", records the rules that followed.

## Decision

- `mk_report` puts the string `FINDINGS-SENTINEL` only in the report body. `assert_nogrep` on it proves the body was not inlined. A sentinel that also appeared in the questions block would make that assertion meaningless.
- `test_markdown_inside_the_block_is_text` puts a fenced block and a plain `## ` heading inside the questions block, with `AFTER-EXAMPLES` text after them. Under the old heading-to-next-heading read these ended the section. Under the sentinel contract they cannot, so the test fails if a markdown parse returns.

## Consequences

Keep the sentinel out of the block and the headings inside it. The mock claude records argv positions (`arg4` is the system prompt, `arg5` the launch prompt, `arg7` the model), so adding a flag to the launch shifts them.
