# Redesign: the L2 retry log's last line (fix/report-format-log-text)

Four gate rounds blocked the same class four times. This plan names the mistake, the design change, and the failure matrix the rebuild must pass.

## What the branch is for

When an L2 attempt leaves a report with no open-questions marker, the retry line in the run log says why and quotes what the capture ends on. Three cosmetic faults from the review of PR 261:

1. Invalid UTF-8 in a capture made BSD `sed` and `awk` fail under a UTF-8 locale, so the last line came back empty.
2. `cut -c1-80` could split a multibyte character.
3. With no sentinel, the trailing `report: <path>` line and its 3-line summary came after the prose question, so the cause fell back to generic wording.

Faults 1 and 2 are fixed and stay (round 1 added a P2 on fault 2, also fixed). Fault 3 is the class that kept blocking.

## Blocking findings, grouped by the mistake

| Round | Finding | What the code did |
|---|---|---|
| 1 | P1: a body line starting `report: ` hides what follows it | any `report: ` line was the trailer |
| 2 | P1: a quoted absolute `report: /quoted/path` within four lines of the end hides the question | any absolute `report: /path` was the trailer |
| 3 | P1: a quoted `report: /quoted/dropped-threads.md` does the same | any `dropped-threads.md` path was the trailer |
| 4 | P1: a quoted `report: <exact caller path>` does the same | a line equal to a caller-named path was the trailer |

Every round is one mistake: the helper decides where the body ends by reading the text of a line, and text in a degraded capture is not trustworthy. Each fix narrowed the pattern and the next counterexample used the narrower pattern. No pattern separates a real trailer from a body that quotes one, because the model wrote both.

## Design change

Stop deciding where the body ends. Nothing in a capture is ever classified as a trailer.

- `report_tail_question` is the new selector. It drops blank lines and the remote-short record first, takes the last five lines that remain (a trailer is a `report:` line and three summary lines, so a question before it sits in the window), strips trailing whitespace and closing markdown (`*`, `_`, `)`, quotes, backticks, and the `\r` of a CRLF line), and prints the last line in the window that ends in `?`. It prints nothing when there is none.
- `report_incomplete_cause` and `report_last_line_excerpt` both call it, so the cause and the excerpt cannot disagree. The excerpt is that line, else `report_last_line`, which stays as the last non-blank line that is not the remote-short record. It takes no paths and has no distance rule.
- The wording stops claiming the report ends in the question. The cause says the report carries a question written as prose near its end, and the retry line says `its tail reads:` in place of `it ends with:`. The end-to-end cases that grep the old wording change with it.
- The runner's call sites lose the path arguments added in round 4.

## Accepted limits (stated in ADR 0009)

- The window is positional. A question followed by more than four non-blank lines (a fourth summary line, a wrapped summary, a pin block with no sentinel) is missed, and the log falls back to the generic cause. This costs log text only.
- A summary line that ends in `?` replaces the real question in the excerpt, and a truncated report with any question-ending line in its last five lines gets the prose-question cause. Both cost log text only.

## What does not change

- Every `awk`, `sed` and `grep` over capture text in `report-format.sh` runs under `LC_ALL=C`, and so does the staging `awk` in `run.sh` (fault 1).
- `report_cut_chars` counts lead bytes and treats a stray continuation byte as a character (fault 2 and its round-1 P2).
- ADR 0009 keeps its section and states the window rule in place of the trailer rule.

## Failure matrix

| Input (last lines of the capture) | Before this branch | Required |
|---|---|---|
| `Should we clean up?`, `report: <path>`, 3 summary lines | summary line | the question, cause prose |
| `report: /quoted/path`, `Should we clean up?` | `# R` | the question |
| `report: /quoted/dropped-threads.md`, `Should we clean up?` | `# R` | the question |
| `report: <any path>`, `Should we clean up?` | `# R` | the question |
| body with no question, then 3 summary lines | summary line | the last line, cause plain |
| the question is the 5th non-blank line from the end | not a question | found |
| the question is the 6th non-blank line from the end | not a question | not found |
| `Should we clean up?` with a CRLF ending | not a question | found |
| `**Should we clean up?**`, `Should we clean up?"`, `(Should we clean up?)` | not a question | found |
| question, trailer, then the remote-short record | not a question | found (the record takes no window slot) |
| invalid UTF-8 in any line, UTF-8 locale | empty | the question |
| 79 `x` then five two-byte characters | split character | 79 `x` and one whole character |
| `x` then 1000 stray `0x80` bytes | 1002 bytes | 80 bytes |
| remote-short record last, no question | skipped | skipped, the last line is the line before it |
| empty capture | empty | empty |

## Rebuild steps

1. Rewrite the trailer asserts in `tests/report-format.sh` to the matrix above, red first against the current helper.
2. Add `report_tail_question`, route the cause and the excerpt through it, drop the path arguments from `run.sh`, and change the two log strings.
3. Update the end-to-end cases that grep the old wording (`test_a_prose_question_with_no_block_is_named_in_the_retry_log`, `test_a_bad_byte_in_the_l2_capture_does_not_hide_the_cause_or_the_report`).
4. Update the ADR 0009 section and its index entry, run the suite, re-run the gate with `--plan`.
