# bin-a: the network probe URL is derived from the model each layer calls, and an unknown provider means "cannot answer"

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`provider_probe_url`)

## Context

`net_up` probes one URL per engine layer. L1 on the omp adapter runs `deepseek/...` and L2 on omp runs `anthropic/...`, so a probe pinned to `api.anthropic.com` read a dead deepseek route as healthy and a dead anthropic one as a deepseek outage.

## Decision

The provider is the part of the model id before the slash. The claude adapter has no provider prefix: it always talks to Anthropic, even with no model named (the CLI's own default). `AUTODREAM_NETUP_URL_<PROVIDER>` (upper-cased, non-alphanumerics to `_`) pins one provider's probe URL. Otherwise a fixed table maps `anthropic`, `deepseek`, `neuralwatt`, `zai`/`z-ai` and `runinfra` to their API hosts. A model with no slash, or a provider not in the table, exits 1 with no output, which the caller reads as "cannot answer", not "down".

## Consequences

A new provider needs a row in the `case` and a test. Do not make an unknown provider fall back to the Anthropic URL: that is the false reading this function replaced.
