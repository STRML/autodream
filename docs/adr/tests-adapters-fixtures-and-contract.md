# tests: adapters-fixtures-and-contract: adapter suites: atomic writes, rejects, contract and the pinned L1 argv

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-contract.sh` (`normalize`, `stats`, `slim`, directory-destination and read-only-directory groups), `tests/adapter-claude.sh` (`normalize` temp check), `tests/adapters.sh` (the rejection groups, the dispatch-guard group, the `adapter_l1_model` subshell counts), `tests/adapter-contract.sh` (`run_contract`, the `enumerate` and `is-self` groups), `tests/adapter-claude.sh` (the `l1-argv` and `warmup-argv` cases)

## the atomic-write assertions are shaped so a leaking or direct-writing adapter fails them

### Context

Adapter subcommands that write a file go through a temp and a rename (`bin-a-adapter-claude-atomic-destination-write`, `docs/design/unify-harness-adapters-2026-08-23.md`). Several assertions for it passed against the broken implementations they were meant to catch.

### Decision

- **A glob, not a literal.** `mktemp` creates `<out>.tmp.XXXXXX`, so a check for `<out>.tmp` names a path nothing creates and passes against an adapter that leaks a temp on every call. The check is `set -- "$out".tmp*` then `-e "$1"`, the bash 3.2-safe way to ask whether a glob matched. It is `.tmp*` and not `.tmp.*`: anchoring on `.tmp.` stops seeing an adapter that leaks the bare `<out>.tmp`, the name the contract prose uses and the likeliest one a new adapter picks. The same mistake was made three times (twice in the contract, once in the claude suite).
- **A directory destination is refused.** `mv -f "$t" "$2"` with an existing directory at `$2` moves the temp inside it and returns success, so the adapter reports a write it did not perform and plants a random file in a directory the caller chose. The delegates once refused this on their own (a `>` redirect to a directory fails); the wrap removed that and has to restore it.
- **A read-only destination directory** is how the property "slim and stats do not write the destination directly" is tested, because the interrupt window cannot be opened from a unit test. The design doc requires it of every writing subcommand; the claude adapter had handed `slim` and `stats` straight to scripts that wrote the destination, so an interrupted slim left a non-empty, footer-less transcript that the caller's `-s` check accepts and sends to L1 as a whole session.
- **What both halves prove.** A pre-existing SENTINEL file in the destination rules out a direct writer (truncating in place needs no directory write, while a temp-and-rename writer cannot create its temp). The exit status rules out reporting success while writing nothing. Together they are narrower than the section name: an adapter that rejects an unwritable destination up front, without trying a temp, also passes, and that is fine because it satisfies the property (no partial write, no false success). Two review seats read a stronger guarantee into the original prose.

### Consequences

Do not weaken the glob or drop the SENTINEL. Do not describe the read-only test as proving interrupt safety. The test skips as root because a read-only directory proves nothing there.

## every loader rejection test pairs an empty list with the refusal record

### Context

An empty `adapters_list` cannot tell "the loader saw this and refused it" from "the glob never matched it". `"$root"/*/` never matched a dot-prefixed directory, so a malformed `.evil` was invisible rather than rejected and `adapters_rejected` reported `none`, which reads as "nothing was refused". It stayed that way until a test asked for the record (`bin-a-adapters-reject-log-is-a-file`).

### Decision

- Each rejection case asserts both an empty list and a named entry in `adapters_rejected`. Every rejection reaches `_adapter_reject` in `bin/adapters.sh`, so every one can say so.
- The dispatching functions (`adapter_run`, `adapter_manifest_get`) are tested with an unsafe name even though every caller today passes a name that came through `adapters_list`. The header of `bin/adapters.sh` argues that identity is the directory basename because dispatch builds a command path from it; that argument holds only if the dispatchers check. The test holds the guarantee for the third-party adapter that arrives later. A valid name is asserted to still work, so the guard is a check and not a blanket refusal.
- The `adapter_l1_model` assertions run in a subshell that writes `pass fail` to a counts file. A missing counts file means the subshell died before reporting and is itself a failure, because the assertions inside never reached the totals.

### Consequences

A new rejection rule needs both assertions. Do not read the counts file with a default of "no failures".

## the adapter contract runs unchanged against every adapter, including a fixture that resembles neither harness

### Context

A contract that only runs against the adapter it was written beside describes that adapter, and keeps passing on the day someone adds a Claude-shaped assumption to shared code.

### Decision

- `run_contract` runs the same assertions for `claude`, `omp` and `_fixture`. `_fixture` uses a session format (`{"cwd":...,"turns":2}` in a `.fixture` file) that matches neither real harness, so a leaked assumption fails immediately. A new adapter is one more `run_contract` line; if more than that is needed, the seam is not real.
- `enumerate` pins the session to a fixed day (`touch -t 202001021200`) and asks for exactly that day. A wide range such as 1970..2999 is not portable: BSD `find` fails to parse `-newermt` at that far end and errors out, and the assertions would measure the date parser rather than the contract (the runner itself uses a five-year reach for the same reason, CLAUDE.md "Which day a session belongs to").
- `is-self` must answer for a session that cannot be READ, and must not answer "not ours". The predicate greps with stderr discarded and returns 1 for a missing file, the same answer a genuine user session gives, so a vanished transcript silently became someone else's problem. Every sibling subcommand has that guard.

### Consequences

Do not special-case an adapter inside `run_contract`. Do not widen the `enumerate` date range.

## the claude l1-argv test compares against text copied from the old run.sh, not against the adapter

### Context

The L1 engine moved behind the adapter without changing what the nightly runs (CLAUDE.md "Who starts the L1 worker"). A test that derives its expectation from the adapter can only agree with the adapter.

### Decision

- The expected argv, system prompt and settings string are written out literally, copied from `run.sh` as it stood at `b473c6f6d` (the `dispatch_l1` call). The test fails if the adapter and the old nightly ever disagree. The one deliberate change since is `--output-format json`, which `served` reads the answering model from.
- `warmup-argv` is compared with `l1-argv` for everything before `--tools`, after dropping the worker's `--output-format` pair. The warmup must take the same auth path as the worker, so every flag except the tools list, the system prompt and the output format has to match. The warmup keeps plain text because it is judged on the word `ok`, and the output format changes only what stdout carries.

### Consequences

Changing a worker flag means editing the literal in this test on purpose, in the same change, with the reason. Do not regenerate the expected text from the adapter.
