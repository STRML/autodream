# bin-a: a provider refusal that retrying cannot clear is detected narrowly, so a talkative transcript cannot defer a date

Status: accepted · Date: 2026-11-21 · Code: `bin/failure-class.sh` (`provider_is_permanent`)

## Context

Z.ai code 1113 "Insufficient balance or no resource package" refused every worker on 2026-10-01 and 2026-10-02. A refusal like that does not clear by retrying, unlike a transient 429 or 5xx. A permanent refusal is ledgered and gets no metadata stub, and the date is deferred (CLAUDE.md, "A dead network or a refusing provider defers the date").

## Decision

`provider_is_permanent` looks only at `worker_text_of`. A line must read like an error report (`error`, `http`, `status`, `code`, `429` or `402`) and must also match a no-balance signature (insufficient balance, quota or funds, no resource package, credit balance too low, or the JSON code 1113). DeepSeek says "Error code: 402 - Insufficient Balance". A transient 429 or 5xx is not permanent and keeps its stub.

## Consequences

The error-report requirement stops a transcript that merely talks about balances from deferring a date. A new provider's wording needs both an error-looking line and a signature added here.
