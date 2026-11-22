# oxlint and the JS comment parser: redesign after round 4

Branch `chore/oxlint-comment-parser`, PR 264 (issue 253). The gate used four rounds and exited 6 REDESIGN. Three of the four rounds blocked on the same class: the counter tried to be a JavaScript validator.

```
round 1  █████  5   (4 P1, 1 P2)  JSX spacing, U+2028, grammar, lint scope, UTF-8
round 2  ███    3                 grammar (C3), JSX brace regression, fixture cwd
round 3  ███    3                 grammar (C3), legacy-retry regression, JSX value regression
round 4  █      1                 grammar (C3) for .jsx
```

## Findings by class

| Class | Findings | The mistake behind them | Design change |
|---|---|---|---|
| A. The counter tries to be a JavaScript validator | r1: `const a: number = 1;` in `.js` accepted, and a `<!--` legacy script rejected. r2: the same two, plus `.jsx` accepted. r3: `const x = 1; const x = 2;` accepted, and the legacy retry rewrote a regex literal. r4: the duplicate declaration accepted in `.jsx`. | The counter needs comment positions. Each fix reimplemented a piece of an engine so the counter could also say whether a file is valid: syntactic diagnostics from a one-file program, then `node --check` for three extensions, then a text rewrite for legacy comments. TypeScript, node and oxlint disagree on what is valid, and every fix left a shape that one of them judges differently. | One judge per question. The TypeScript parser finds comment positions, as before. oxlint says whether a file is valid, and it already runs in the `lint` workflow over every tracked JS and TS file. The counter fails closed on what TypeScript cannot read and does nothing else. `node --check`, the one-file program, the legacy retry and the `.jsx` gap all go. |
| B. JSX comment lines found by reading text | r1: `{ /* c */ }` with a space. r2: `{ /* c */ let x = 1; }` in a plain block counted as JSX. r3: `{ /* c */ value }` not counted. | A line that starts with `{` was treated as JSX from its characters, then from "an expression with no expression". | A JSX comment line is a line whose first character starts a `JsxExpression` node and whose first token inside is a comment. Held at `48f5f4a`. |
| C. Line and byte boundaries | r1: U+2028 and U+2029 joined two comment lines. r1 (P2): invalid UTF-8 replaced before counting. | Splitting on `\n` and decoding with replacement. | Split on every JavaScript line terminator and decode strictly. Held. |
| D. The lint scope enumerates directories | r1: `bin/comment-count-js.mjs` sat outside the four directories. r2: the coverage fixture resolved `./package.json` from the caller's directory. | The directories were listed and the claim "oxlint lints the same files" was never checked. | `bin` joins the list. A fixture fails when a tracked JS or TS file is outside it, and reads the path from the repo root. Held. |

## Class A: the counter and oxlint each do one job

```
file ──▶ counter: TypeScript createSourceFile ──▶ comment lines
              │ parse error ─▶ exit 2 (fail closed, names the file)
              └ grammar validity: not judged here

file ──▶ oxlint (npm run lint, the lint workflow, every tracked file) ──▶ valid, or the PR fails
```

Measured with oxlint 1.93.0 on scratch files outside the repo:

| Input | oxlint |
|---|---|
| `const x = 1; const x = 2;` as `.js`, `.jsx` and `.mjs` | `Identifier x has already been declared` (error) |
| `const a: number = 1;` as `.js` | `Missing initializer in const declaration` (error) |
| a script that starts with `<!-- legacy` | accepted (a script may hold HTML-like comments) |

The coverage fixture (class D) makes oxlint a complete judge: a tracked JS or TS file outside the linted directories fails the ratchet. A second fixture runs the pinned oxlint on the four shapes above. A change to the lint script or the pinned version that stops rejecting one of them fails there.

### Failure matrix

| Input | Counter | oxlint | Merges |
|---|---|---|---|
| `const x = 1; const x = 2;` in a tracked `.js`, `.jsx` or `.mjs` | counts its comments | error, `lint` fails | no |
| TypeScript syntax in a tracked `.js` | counts its comments | error, `lint` fails | no |
| a tracked script with a legacy `<!--` comment at the start of a line | fails, names the file (the wrapper exits 1) | accepts | no: the ratchet fails closed. No tracked file has one, and the fix is to delete the construct |
| a legacy `<!--` after code on the same line (`x <!-- note`) | reads it as the expression `x < !(--note)` and counts 0 | accepts | yes. Accepted: the counter under-counts only this form, in a script, and no tracked file uses it |
| JSX text that looks like a block comment (`<p>/* shown`) | text, counts 0 | accepts | yes, correctly |
| a tracked `.d.ts` file | counts its comments | linted (the ignore pattern for `.d.ts` is gone) | by the same rules as any file |
| a tracked file TypeScript cannot parse (`const x = ;`) | fails, names the file (the wrapper exits 1) | error | no |
| a tracked JS or TS file outside the linted directories | counts it | not run | no: the coverage fixture fails |
| invalid UTF-8 | fails, names the file (the wrapper exits 1) | not run on it | no |
| `typescript` module missing | fails, says `npm ci` (the wrapper exits 1) | n/a | no |
| a comment added to a tracked file | count rises | n/a | no: over the baseline |

## Rebuild

1. `bin/comment-count-js.mjs` drops `spawnSync`, `NODE_MODES`, `nodeAccepts`, the one-file program, `legacyCommentAt` and `neutralize`.
2. The grammar fixtures that expected the counter to reject TypeScript syntax in `.js` and `.jsx` and a duplicate declaration are replaced by one that counts a duplicate declaration in `dup.js` and `dup.jsx`. The legacy-comment fixture expects a failure that names the file.
3. `lint_is_the_grammar_judge_fixture` runs the pinned oxlint with every rule off (`-A all`), so only a syntax or early error can make it exit non-zero, on four shapes, and fails when one passes.
4. ADR 0027 states the contract in one paragraph.

## Plan review

A `counsel` subagent read the plan against the code (the external `/debate:run tight` panel was denied an unsandboxed run). Verdict REVISE. Each finding was checked before it was acted on.

| Finding | Check | Disposition |
|---|---|---|
| `.oxlintrc.json` ignored `**/*.d.ts`, so two tracked declaration files were counted but never linted | `git ls-files '*.d.ts'` lists `mods/autodream-band/types/index.d.ts` and `mods/autodream-focus/types/index.d.ts`; a duplicate declaration in a probe `.d.ts` is now an error | Fixed: the ignore is gone and a fixture fails if the oxlint config ignores a JS or TS file by extension |
| the grammar fixture treated any non-zero oxlint exit as a rejection, so an unused-variable warning would pass it | `oxlint --deny-warnings` on `const x = 1;` warns; with `-A all` it exits 0 and a duplicate declaration still exits 1 | Fixed: the fixture runs with `-A all` |
| the plan named fixtures that do not exist, and called the failure exit 2 and 3 | the wrapper reports exit 1 | Fixed in this plan |
| JSX text `<p>/* shown` then `as text */</p>` was counted as a comment | probe printed 1; after the fix, 0 | Fixed: no trailing-comment scan right before JSX text, with a fixture |
| `x <!-- note` after code counts 0 | probe printed 0 | Accepted, and in the matrix above |

One gap remains: a file that `node` rejects and oxlint accepts. oxlint's parser follows the specification, so the gap is a bug in oxlint. `package.json` pins its version and the fixture watches the four shapes.
