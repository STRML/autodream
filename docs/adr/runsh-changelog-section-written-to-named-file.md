# runsh: changelog sections are appended to a named file, never emitted on stdout

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_window`, `changelog_one`)

## Context

`log()` writes to stdout. A version that built the changelog inside a `{ ... } > "$out"` block silently interleaved every "cloning ..." progress line into the file L2 then reads as release notes. Caught in a live run against all three remotes; `test_changelog_multi_source` pins it. See CLAUDE.md, "Upstream changelog window".

## Decision

`changelog_window` truncates `$FINDINGS_DIR/changelog-window.md` once with its header line, then every `changelog_one` appends its own section to `$out` with `>>`. Nothing in `changelog_window` may wrap the loop in a `> "$out"` block.

## Consequences

Any new progress line is safe only because it goes through `log()` outside the file. Do not turn the section writers into stdout emitters.
