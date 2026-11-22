# tests-ci-scope: the selector leans toward `full`, sees both sides of a rename, and is checked against what the full suite reads

Status: accepted · Date: 2026-11-22 · Code: `tests/ci-scope.sh` (the rename fixture repo, `reader_paths`)

## Context

`.github/ci-scope.sh` decides whether a PR's `tests.yml` run needs the whole suite or only the web dashboard's. The failure that matters is a PR classified `web` whose change the full suite would have caught. Cheap CI is never worth that, so every assertion leans toward `full`.

- `git diff --name-only` reports a rename by its new path only. Moving `bin/run.sh` into `web/` read as a web-only change. The selector now runs the diff itself with `--no-renames`.
- The rule "a web file is one the full suite never reads" needs an oracle. `web/threads.*` failed it, which is why the selector excludes those files.
- Readers deliberately left out of the oracle: `install.sh` (only links the web files); the macOS-only suites `run-all.sh` adds on Darwin, among them `install-web-agent` (`tests.yml`'s Linux shards never run them and `launchd.yml` runs them on its own paths); and `bin/autodream-web`, the launcher only the web suite and those macOS suites start.
- `reader_paths` is a function and not a loop inside `$(...)`: bash 3.2, the interpreter `run-all.sh` and launchd use on macOS, cannot parse a case pattern's `)` inside a command substitution.

## Decision

The test builds a throwaway repo with a rename and asserts `base..moved` is `full` while `moved..css` is `web`. A missing ref also yields `full`. The oracle lists every tracked file the selector calls web and fails if any code the Linux shards run names one, minus the three exclusions above.

## Consequences

A new assertion that could narrow the scope needs a matching case that proves it still returns `full` on the dangerous input. Keep the `reader_paths` exclusions in step with `run-all.sh`'s Darwin-only list.
