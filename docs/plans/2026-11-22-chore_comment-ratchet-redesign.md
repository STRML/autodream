# Comment ratchet: redesign after round 4

Branch `chore/comment-ratchet`, PR 249. The gate used four rounds. Round 1 found 9 P1 and 1 P2, round 2 found 4, round 3 found 2, round 4 found 1. Rounds 3 and 4 were the same class twice.

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
| B. Every I/O step fails open | r1: unreadable file counted as 0, baseline comparison, `--update` publish, empty baseline `NR==FNR`; r2: `isfile` swallows a stat failure; r2: symlinks skipped | A failed `awk`, `sort`, `mv` or `stat` read as "nothing found" | Every status is checked, a file the counter cannot read or stat fails naming it, `--update` renames a same-directory temp file last, and every one of these has a test that shims the tool to fail. Held through rounds 3 and 4. |
| C. CI does not run the check | r1: web-only PRs skip the ratchet | Scope selector had no rule for it | `tests.yml` step for web scope, `ci-scope` test pins it. Held. |
| D. JS regex literal versus division, decided by one heuristic | r2: `if (x) /[/*]/`, CRLF continuation (separate site); r3: `1 + + /[/*]/`, `o.if(x) / 2`; r4: `label: {} /[/*]/` | A `/` is ambiguous without a full grammar. Each round patched the heuristic for the last counterexample and the reviewer found the next one. | Stop trying to be right everywhere. See below. |

## Class D: why patching the heuristic cannot end it

Telling a regex from a division needs the grammar. Round 4's `label: {}` is a statement context that a lexer only knows from the parser. Each heuristic rule I added (paren stack, brace stack, adjacency, property names) is correct for the case that prompted it and wrong for a neighbor.

What the ratchet actually needs is only the lexer state at the start of each line, and a regex literal cannot span lines. So a wrong guess costs something only when the text between the slash and the next slash on that line holds a character that changes lexer state.

```
slash ─▶ no closing slash on the line ───────────────▶ division (a regex needs one)
      ─▶ span has none of  ` ' " { } ( ) /  ─────────▶ both readings leave the same state: use the heuristic
      ─▶ span has one of them ─▶ speculate:
             1. read the file with the heuristic's choice
             2. a lexical error (unclosed block comment, template, expression)
                flips the latest such decision and reads again
             3. at most 64 flips, then the original error stands
```

What this rules out: every counterexample the reviewer produced was one where the wrong reading ends in an unclosed construct (they reported "block comment is never closed" or "template literal is never closed"), and the speculation recovers each of them. The heuristic stays as the tie-breaker when both readings lex.

What it does not rule out, and I say so: a file where both readings lex cleanly and differ in which lines are comments. That needs a slash with a quote or brace in its span, a wrong heuristic guess, and no later unclosed construct to expose it. I could not construct one that is also plausible code.

## Failure matrix for the slash decision

| Input | Heuristic says | Truth | What happens | Test |
|---|---|---|---|---|
| `if (ok) /[/*]/.test(v);` | regex (control paren) | regex | regex, one comment counted after it | `a regex literal after the parenthesis of an if…` |
| `1 + + /[/*]/.test(v);` | regex (not adjacent) | regex | regex | `two separated plus signs…` |
| `o.if(true) / 2; const t = \`` | division (property) | division | template opens on the same line | `a property named like a control keyword…` |
| `label: {} /[/*]/.test(v);` | division (labeled block read as object) | regex | division reading hits `/*` with no close, flip, regex reading lexes | `a regex after a labeled block…` |
| `b /[/*]/ c;` | division | regex | flips the same way | `a slash the heuristic reads as division is flipped…` |
| `1 +` newline `/ 2;` | regex (after `+`) | division | no closing slash on the line, so division | `a slash with no closing slash…` |
| `</div>` in TSX text | regex | text | no state-changing char in the span, no effect | the TSX torture check |
| `i++ / 2 / 4` | division | division | division | `division after a parenthesis or an increment…` |
| both readings lex, comment lines differ | heuristic | unknown | heuristic wins (the residual risk above) | none possible without a valid example |
| more than 64 flips needed | n/a | n/a | the original error, naming the file | none; the cap is a guard |

## Not changing

Parsers for shell and Python, the exact directive list, fail-closed I/O, baseline rules, CI steps. They held through rounds 2 to 4 with no new findings.

## Cost

Speculation re-reads the file once per flip, only on a file that already failed to lex. The repo's 18 JS and TS files lex on the first reading (23 slashes had a risky span, all of them settled by the heuristic with no error), so the usual path costs nothing extra.
