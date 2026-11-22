# tests-run-all: the pin tests pin the order of run steps and where the pin block sits in the prompt

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_pins_applied_after_complete_report`, `test_pins_applied_before_notify`, `mk_stranded_pins`, `test_no_markdown_memory_writer_remains`)

## Context

Pins are the only thing the nightly writes outside its own directory, so the order of steps decides what a killed or hung run can lose. `AUTODREAM_OPEN` runs synchronously inside `notify.sh`, so a blocking editor command holds the run there.

## Decision

- **Pins and their authorization list land before the report** (issue 72), so a complete report on disk always has them beside it. The test compares mtimes with `-nt`. `mk_stranded_pins` runs `sleep 1` before writing the report for the same reason: mtime resolution must separate the two files.
- **`notify.sh` is replaced by a stand-in** that records whether `pins-applied.tsv` was already non-empty when it ran. That checks the order directly. It does not need a real blocking command.
- **The pin block follows the report sentinel in PROMPT.md.** A capture cut off before the sentinel is retried whole, so a pin can never be stored for a report that was never delivered. The test compares the line numbers of the two prompt steps.
- **The report may only say a pin was proposed.** L2 exits before any pin is applied, and the runner can still refuse one, so PROMPT.md must not tell the report to call a pin stored.

## Consequences

Moving the pin step after report delivery, or editing PROMPT.md's step wording, fails these tests on purpose. The grep patterns for the two step lines are literal prompt text, so a prompt rewrite needs the patterns updated in the same change.
