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

The lexer existed to answer one question: is a line that starts with `//` or `/*` really a comment, or data inside a template literal or string? The rule that does not need the answer reads each line on its own:

```
in a block?  yes ─▶ count the line; a `*/` on it ends the block
             no  ─▶ first non-blank characters are
                      //  ─▶ count (unless an exact directive: @ts-expect-error, @ts-ignore, oxlint-disable)
                      /*  ─▶ count; a `*/` later on the line closes it, otherwise a block opens
                      else ─▶ nothing (a `*` line outside a block is multiplication or a pointer, not a comment)
```

There are no strings, templates, regexes or division to classify, so there is nothing to guess and nothing to lose track of. The coordinator chose this on 2026-11-22. The JS and TS tracks had already deleted the real comments, so the rule only has to guard against new ones.

### Accepted trades, and which way each one fails

| Input | What the rule does | Direction | Fixture |
|---|---|---|---|
| a line inside a multiline template literal that starts with `//` or `/*` | counts it | over-count: can fail a PR, never hides a comment | `a template literal line that starts with // is over-counted…` |
| a block comment that opens after code (`x = 1; /* a`) with continuation lines | counts none of them | under-count: a comment can slip past on a continuation line | `a block that opens after code is not tracked…` |
| a regex, division or string in the middle of a line | ignored | none: only line starts are read | `a slash, regex or string in the middle of a line never matters…` |
| an unclosed `/*` | counts to the end of the file | over-count, no error | `an unclosed block comment counts to the end of the file` |
| CRLF endings | read the same | none | `CRLF line endings read the same` |
| `#!` hashbang | not counted | none | `a hashbang line is not a comment` |
| a `*` line outside a block | not counted | none | `a * line counts inside a block…` |

The under-count row is the one to weigh. It needs a block comment that starts after code, which is not how this repo writes comments, and that line still carries code a reviewer reads. I accept it for the same reason the coordinator accepted the over-count: it keeps the rule stateless.

### What this removes

The scanner class (about 200 lines), the paren and brace stacks, the adjacency rule and the speculation with 64 flips from the first draft of this plan. Every class D finding depended on a lexer, so none of them can recur.

## Not changing

Parsers for shell and Python, the exact directive list, fail-closed I/O, baseline rules, CI steps. They held through rounds 2 to 4 with no new findings.
