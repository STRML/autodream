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

## Class D: no state, so no guess

The lexer existed to answer one question: is a line that starts with `//` or `/*` really a comment, or data inside a template literal or string? The rule that does not need the answer judges each line alone:

```
a line counts when its first non-blank characters are
    //   (unless an exact directive: @ts-expect-error, @ts-ignore, oxlint-disable)
    /*   a block opening
    *    a block body or closing line (` * text`, ` */`)
nothing else counts, and no line looks at any other line
```

There are no strings, templates, regexes or division to classify, and no state to lose. The coordinator chose the stateless direction on 2026-11-22. Round 5 then showed that the first version still carried one bit of state (an open block), and that a phantom block opened by `/*` inside a template swallowed every later line, so a new comment added after it changed nothing. Now every line stands alone, and a new `//`, `/*` or `*` line always adds exactly one.

### Accepted trades, and which way each one fails

| Input | What the rule does | Direction | Fixture |
|---|---|---|---|
| a line inside a multiline template literal that starts with `//`, `/*` or `*` | counts it | over-count: can fail a PR, never hides a comment | `a template literal line that starts with // is over-counted…`, `a /* inside a template opens nothing…` |
| a `*` line outside any block (a continued multiplication) | counts it | over-count | `a line that starts with * is counted whether or not a block is open` |
| a block body line with no star prefix | not counted; the opening and closing lines are | under-count by the body lines, but the opening line is always counted, so a new block comment still adds at least one | `a block body line with no star is not counted…` |
| a block that opens after code (`x = 1; /* a`) | the opening line is not counted (it is trailing, like `x = 1 // a`); its starred lines are | under-count by one line | `a block that opens after code is not counted…` |
| a regex, division or string in the middle of a line | ignored | none: only line starts are read | `a slash, regex or string in the middle of a line never matters…` |
| an unclosed `/*` | counts only its own line, swallows nothing | none | `an unclosed block opens nothing…` |
| CRLF endings, `#!` hashbang | read the same, not counted | none | `CRLF line endings read the same`, `a hashbang line is not a comment` |

## Round 5 (full review against this plan)

Five findings, grouped. Each is a repeat of an earlier class, so the rule for each is the same: fix by class, sweep the siblings.

| Finding | Class | Fix | Test |
|---|---|---|---|
| a phantom JS block hides newly added comments | class D, stateful rule | drop the block state (above) | `a /* inside a template opens nothing…` |
| CI skips code under `docs/` and `example/` | C: CI scope | `tests.yml` re-includes `**.sh`, `**.py` and each JS/TS extension after its exclusions, for push and pull_request | `tests/ci-scope.sh`: one assertion per extension and one for the order |
| `--update --allow-increase` onto a directory reports success | B: a successful move is not proof of replacement | refuse a directory destination, and compare the baseline with the new rows after the move | `--update --allow-increase onto a directory fails…` |
| a tracked dangling code symlink is skipped | B: an unreadable file read as nothing | a dangling link with a code extension fails and names the path; one with a data extension has nothing to read | `a tracked code symlink that points at nothing fails…` |
| the final totalling `awk` of `--update` is discarded inside `echo` | B: a failed subprocess hidden in a success message | totals are computed from the temp file and checked before the move, and the message prints only after the move is verified | `--update fails before publishing when the final totalling awk fails` |

## Not changing

Parsers for shell and Python, the exact directive list, fail-closed I/O, baseline rules, CI steps. They held through rounds 2 to 4 with no new findings.
