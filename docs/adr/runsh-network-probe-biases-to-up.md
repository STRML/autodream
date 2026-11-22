# runsh: The network probe reads "cannot answer" as up

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`net_up`)

## Context
No URL, or a `curl` that cannot run at all (exit 127 not found, 126 found but not executable), means the check cannot answer; it does not mean the host is down. Reading that as down made a machine without curl wait out the full cap and defer a healthy run, every run, for a reason nothing reported.

## Decision
`net_up` returns up when called with no URL, and when `curl` exits 127 or 126. The test is on the exit status, not `command -v`, which also covers a curl that is present but unrunnable. Bias is to up: a wrong "up" costs one round of workers, a wrong "down" costs the whole date.

## Consequences
Do not "fix" this to report down when curl is missing. A worker that does need a dead route fails and is classified as an outage by its own probe (see `wait-for-network-any-provider-and-wall-clock-cap`). `tests/run-all.sh` extracts `net_up()` with `sed -n '/^net_up() {/,/^}/p'`, so it must stay a top-level function ending in a column-0 `}`.
