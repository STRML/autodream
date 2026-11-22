# runsh: The network probe trusts the HTTP status line, written to a header file, and is bounded by a timeout binary

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`net_up`)

## Context
A network filter can hold curl in `close()` after the reply has already arrived (found at the 2026-10-03 cutover: Little Snitch on this host). curl then prints nothing and its own `--max-time` cannot interrupt a `close()`, so the probe read a healthy network as down and the run waited out the whole cap.

## Decision
curl writes the status line to a header file (`-D "$hdr"`) the moment it arrives, so a reply counts (`grep '^HTTP/'`) even when curl never gets to report it. A `TIMEOUT_BIN` (`-k 2 <limit>`) bounds the stall when one exists. curl's own `--max-time` is `min(5, limit)`, so it never exceeds the probe's limit and a host without a timeout binary is bounded too.

## Consequences
Keep all three signals (status code, header file, curl exit status) in `net_up`; dropping the header file reintroduces the false "down".
