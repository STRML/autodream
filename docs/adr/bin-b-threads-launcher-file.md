# bin-b: threads.sh gives cmux a launcher file, not an inline command

Status: accepted · Date: 2026-11-21 · Code: `bin/threads.sh` (`threads_launcher`)

## Context

cmux types `--command` into the user's login shell, which can be fish, and fish cannot parse bash's `$'...'` quoting. CLAUDE.md, "Local web dashboard" and the Tests section on `threads.sh explore`, record the launch contract.

## Decision

`threads_launcher` writes the bash command to a file in a fresh 0700 `mktemp -d` directory and prints its path. cmux is handed only `/bin/bash '<file>'`, which every shell reads the same way. The path is absolute (the pane may start in another directory) and free of single quotes and backslashes (a directory name containing either is rejected), so the single quotes are safe. The launcher removes its own file and directory when it starts, and nothing else is ever deleted.

## Consequences

`test_threads_explore_*` pins the quoting. Do not inline the command to save the file.
