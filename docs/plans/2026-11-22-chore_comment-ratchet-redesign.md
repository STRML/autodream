# Comment ratchet: redesign after round 4

Branch `chore/comment-ratchet`, PR 249. The gate used four rounds. Round 1 found 9 P1 and 1 P2, round 2 found 4, round 3 found 2, round 4 found 1. Rounds 2, 3 and 4 hit the same class.

```
round 1  ██████████  10   scanner guessed a grammar; every I/O step failed open
round 2  ████         4   regex guess, CRLF, symlink/stat, string continuation
round 3  ██           2   regex guess (adjacent ++, property names)
round 4  █            1   regex guess (labeled block)
```

## Findings by class

| Class | Findings | The mistake behind them | Design change |
|---|---|---|---|
| A. A hand-written scanner guesses shell, Python and JS grammar | r1: heredoc detection, multiline strings, directive prefixes | Matching lines instead of parsing | Shell: `shfmt --to-json` Comment nodes. Python: `tokenize`. Done in b7e7a59 and held through rounds 2 to 4. |
| B. Every I/O step fails open | r1: unreadable file counted as 0, baseline comparison, `--update` publish, empty baseline `NR==FNR`; r2: `isfile` swallows a stat failure; r2: symlinks skipped | A failed `awk`, `sort`, `mv` or `stat` read as "nothing found" | Every status is checked, a file the counter cannot read or stat fails naming it, `--update` renames a same-directory temp file last, and each of these has a test that shims the tool to fail. Held through rounds 3 and 4. |
| C. CI does not run the check | r1: web-only PRs skip the ratchet | Scope selector had no rule for it | `tests.yml` step for web scope, `ci-scope` test pins it. Held. |
| D. JS regex literal versus division, decided by a lexer that tracks string and template state | r2: `if (x) /[/*]/`; r2: CRLF string continuation; r3: `1 + + /[/*]/`, `o.if(x) / 2`; r4: `label: {} /[/*]/` | A JS lexer needs the grammar to tell `/` apart, and a stateful lexer that guesses wrong loses its place for the rest of the file. Each patch fixed the last counterexample and the reviewer found the next. | Delete the state. See below. |

## Class D: no lexer, so no guess

The lexer existed to answer one question: is a line that starts with `//` or `/*` really a comment, or data inside a template literal or string? The rule that does not need the answer reads line starts and one lookahead:

```
a line counts when its first non-blank characters are
    //   (unless an exact directive: @ts-expect-error, @ts-ignore, oxlint-disable)
    /*   a block opening. Look ahead for the first `*/` (same line or later):
           found      ─▶ every non-blank line from the opener to that line counts
           not found  ─▶ only the opener counts; later lines are read normally
    *    a line that starts with a star outside any block (ratchets a stray ` * x`)
nothing else counts; there are no strings, templates, regexes or division to classify
```

The coordinator chose the stateless direction on 2026-11-22. Two review rounds then pushed on opposite edges of it, and the rule above is the one that answers both:

- Round 5: a `/*` inside a template with no `*/` after it opened a block to the end of the file. Blank lines inside counted, so replacing a blank line with `// real comment` changed nothing. Now an unclosed opener counts alone, and a blank line inside a block never counts, so any non-blank line added anywhere raises the count by one.
- Round 6: with no block state at all, a body line with no star prefix (`/*`, `new comment`, `*/`) was invisible, so a comment could grow inside a block. Now every non-blank line of a closed block counts.

### Accepted trades, and which way each one fails

| Input | What the rule does | Direction | Fixture |
|---|---|---|---|
| a line inside a multiline template literal that starts with `//`, `/*` or `*` | counts it | over-count: can fail a PR, never hides a comment | `a template literal line that starts with // is over-counted…` |
| a `/*` at a line start inside a template that a later `*/` closes | counts every non-blank line up to that `*/`, code included | over-count. The residual risk: deleting a counted code line in that span leaves slack until the baseline is tightened. It needs a template line that starts with `/*` and a later `*/`, which this repo does not contain; `--update` and the below-baseline note exist to drain slack. | none possible without a pathological file |
| an unclosed `/*` | counts only its own line | none | `a /* inside a template opens nothing…`, `an unclosed block opens nothing…` |
| a `*` line outside any block (a continued multiplication) | counts it | over-count | `a line that starts with * is counted whether or not a block is open` |
| a block that opens after code (`x = 1; /* a`, including a line that also closes an earlier block) | the opening line is not counted (it is trailing, like `x = 1 // a`); its starred lines are | under-count: the unstarred continuation lines of that block are missed | `a block that opens after code is not counted…` |
| a JSX comment, which has to be `{/* … */}` | a line that starts with `{/*` or `{//` is read as if the brace were not there | none (p1-verifier's finding on 8dd3c21) | `a JSX comment that starts a line…` |
| `/* oxlint-disable … */`, the block form of the directive | counted: only the `//` forms are exempt, matching the exact list in CLAUDE.md | over-count, a choice and not a bug | none |
| a regex, division or string in the middle of a line | ignored | none: only line starts are read | `a slash, regex or string in the middle of a line never matters…` |
| CRLF endings, `#!` hashbang | read the same, not counted | none | `CRLF line endings read the same`, `a hashbang line is not a comment` |

## Rounds 5 and 6 (against this plan)

Round 5 had five findings and round 6 three (phantom block regression, CI scope again, dangling symlink again). Grouped. Each is a repeat of an earlier class, so the rule for each is the same: fix by class, sweep the siblings.

| Finding | Class | Fix | Test |
|---|---|---|---|
| a phantom JS block hides newly added comments | class D, stateful rule | drop the block state (above) | `a /* inside a template opens nothing…` |
| CI skips code under `docs/` and `example/` | C: CI scope | round 6 showed that re-including extensions still misses a script with a shebang and no extension, and a path filter cannot read a shebang. So `tests.yml` no longer excludes any directory: only markdown and LICENSE skip the tests | `tests/ci-scope.sh`: no `!docs/` or `!example/` exclusion, markdown still skipped in both lists |
| `--update --allow-increase` onto a directory reports success | B: a successful move is not proof of replacement | refuse a directory destination, and compare the baseline with the new rows after the move | `--update --allow-increase onto a directory fails…` |
| a tracked dangling symlink is skipped | B: an unreadable file read as nothing | round 6: an extensionless link can hold a script, and its language cannot be known once the target is gone, so any dangling tracked symlink fails and names the path | `a tracked symlink that points at nothing fails and names it, whatever its name` |
| the final totalling `awk` of `--update` is discarded inside `echo` | B: a failed subprocess hidden in a success message | totals are computed from the temp file and checked before the move, and the message prints only after the move is verified | `--update fails before publishing when the final totalling awk fails` |

## Not changing

Parsers for shell and Python, the exact directive list, fail-closed I/O, baseline rules, CI steps. They held through rounds 2 to 4 with no new findings.
