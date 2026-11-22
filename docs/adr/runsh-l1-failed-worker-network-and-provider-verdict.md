# runsh: a failed L1 worker gets a three-state network verdict from its own engine's host and a provider-refusal verdict, ledgered append-only per round

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt` failure path; `l1-netdown.txt`; `bin/failure-class.sh` `provider_is_permanent`)

## Context
Without a reachability check, a failure caused by a sleeping Mac is indistinguishable from a transcript the worker could not digest, and the oversized gate would count it as evidence it is not. An absent `curl` exits 127; the first version read that as "no route", so a host without curl would have excluded every worker failure from the oversized gate, permanently and invisibly. An omp worker on deepseek failing while api.anthropic.com answers is not "network up", and the reverse is not an outage. A bare hash in the ledger was wrong: the ledger is truncated once per run, so a round-1 outage entry survived into round 5 and excluded a round-5 failure with a completely different cause. A reachable network is not a working provider: a billing refusal (Z.ai code 1113, 2026-10-01 and 10-02) answers curl fine, so `netdown` was false and the stub consumed the session permanently.

## Decision
- One `curl` (5 s) runs only on the failure path, to the host the failing engine talks to (`AUTODREAM_L1_PROBE_URLS`, resolved before any model ran, keyed by source), never a fixed host.
- Three states: exit 126/127 is "cannot tell" (`unknown`: never ledgered and never suppresses the stub); an empty or `000` code is `true` (down); anything else is `false`.
- When the network is not down, `provider_is_permanent` on the `.err` (no balance or quota, Z.ai 1113, DeepSeek 402) sets `netdown=provider`: no stub, the session is left for a later run. A transient 429 or 5xx keeps its stub.
- Every classified failure is appended as `<hash> <round> <state>` and a line is never rewritten. Readers take the highest round per hash, so the last attempt counts. Append-only also keeps the parallel xargs subshells from racing, as for `l1-timeouts.txt`.

## Consequences
See CLAUDE.md, "A dead network or a refusing provider defers the date; it never publishes a short corpus". A new permanent-refusal wording goes into `failure-class.sh` with a matrix row.
