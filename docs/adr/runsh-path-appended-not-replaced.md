# runsh: run.sh appends its extra directories to the caller's PATH instead of replacing it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `export PATH=` line before `TIMEOUT_BIN`)

## Context
launchd hands the job a minimal PATH that lacks the engine binaries and git, which is why run.sh adds directories at all. Replacing the caller's PATH meant an interactive run and the nightly could resolve different binaries, and a test could not put a `curl` shim in front.

## Decision
`PATH="${PATH:+$PATH:}$HOME/.cargo/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"`: the caller's entries win, as in a shell, and the launchd case is still covered. CLAUDE.md records this under the network-defer notes ("`run.sh` appends to the caller's `PATH` instead of replacing it").

## Consequences
Do not prepend or reassign. The plist PATH written by install.sh is the other half (see CLAUDE.md, "What goes in the plist PATH").
