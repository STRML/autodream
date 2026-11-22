# runsh: L2's skills inventory and per-harness facts come from the adapters, and facts are taken only for sources that had sessions, from the pre-model source map

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`write_adapter_inputs`)

## Context
L2 needs to know which skills are installed and what each contributing harness offers, so its remedies exist for the harness the evidence came from (a `permissions.allow` entry means nothing to omp). An empty inventory would claim no skills are installed. A worker could rewrite a file under the findings dir.

## Decision
- `skills-inventory.txt` is the union of every enabled adapter's `skills-inventory` output (a name, optionally a TAB and a description), deduplicated by name with the first winning. If every adapter fails, the file says `# skills-inventory.txt unavailable` and PROMPT.md tells L2 not to file coverage gaps from it.
- `adapter-facts.md` holds one `## Source: <name>` section with that adapter's `facts.md`, only for sources that actually had sessions tonight, taken from `AUTODREAM_SOURCE_MAP` captured before any model ran, never from a file a worker could have rewritten.
- A new harness adds `adapters/<name>/facts.md` and a `skills-inventory` verb, not code here.

## Consequences
See CLAUDE.md, "What L2 is told about each harness".
