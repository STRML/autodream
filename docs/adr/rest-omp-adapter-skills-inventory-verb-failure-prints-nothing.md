# rest: the omp skills-inventory verb prints names and descriptions, and a failure prints nothing and exits 1

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`skills-inventory`), `adapters/omp/skills-inventory.sh`

## Context

L2 treats the inventory as the authoritative list of active skills (`runsh-l2-adapter-inputs-skills-inventory-and-facts.md`). An empty inventory would claim no skills are installed, so the caller must be able to tell "failed" from "none". The claude adapter prints the name alone; omp knows each description too. `skills-inventory.sh` writes a file that starts with four comment lines.

## Decision

The verb prints one active skill per line: the name and, when known, a TAB and its description. A consumer that wants only names takes field 1. It runs the script into a `mktemp` file, drops the `#` header lines with `grep -v '^#'`, removes the temp, and exits with the script's status. A failure prints nothing and exits 1, so the caller writes its `unavailable` sentinel instead of an empty inventory.

## Consequences

Letting a failed script fall through to an empty listing would make L2 file coverage gaps for every skill.
