# rest: ci-scope prints `web` only when every changed path is known to be web or prose

Status: accepted · Date: 2026-11-17 · Code: `.github/ci-scope.sh`

## Context

A PR that changes only the web dashboard does not need the whole suite, so `tests.yml` asks `.github/ci-scope.sh` whether it may run only `tests/autodream-web.sh`. A wrong `full` costs a few minutes. A wrong `web` merges a change the suite would have caught. `tests/ci-scope.sh` pins every rule.

Plain `git diff --name-only` reports a rename by its new path alone, so moving `bin/run.sh` into `web/` would read as a web-only change.

Some paths look like web code and are not:

| Path | Why it is not web |
|---|---|
| `web/threads.*` | `bin/threads-render.py` inlines them into the page `run-all.sh` asserts on |
| `bin/autodream-web` | the shell launcher `install.sh` links |
| `tests/autodream-web.sh`, `.github/ci-scope.sh`, any workflow | they change how tests run |
| markdown under `prompts/`, `adapters/` or `skills/` | the suites assert on what it says (#178: a prompt-only PR skipped CI and left two tests red on main) |

## Decision

Invocations: `ci-scope.sh BASE HEAD` diffs two revisions with `--no-renames` and sends the changed paths to stderr; `ci-scope.sh < paths` reads one path per line. It prints `web` only when every path belongs to the web dashboard (or is prose markdown) and at least one is web code. Anything else prints `full`: a path with no rule, a path containing `..`, no paths at all, a failed `git diff`.

## Consequences

A new top-level directory needs a rule only if it should ever be web. The default is `full`. Adding a web path means adding a case and a row in `tests/ci-scope.sh`, which also checks that no code the Linux suite runs names a file the selector calls web. See `tests-ci-scope-and-shard-guards`.
