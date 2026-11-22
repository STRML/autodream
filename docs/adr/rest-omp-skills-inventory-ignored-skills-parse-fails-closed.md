# rest: the ignoredSkills parse follows exact YAML block-list rules, and a failed parse aborts instead of reporting an empty ignore list

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (`CLEAN_ITEM`, the `ignored=` block, `in_ignored`)

## Context

An empty ignore list would wrongly claim every on-disk skill is active, including ones the operator explicitly disabled. The config may also be absent, which is normal and means an empty set. python3 is present on macOS; an awk fallback exists for hosts without it.

## Decision

The block list under `ignoredSkills:` is parsed with these rules, identical in the python and awk paths:

- Only items indented deeper than the `ignoredSkills:` key line are list items.
- Blank lines inside the block keep parsing.
- A same-or-less-indented non-blank line (a sibling key) ends the block.
- Inline comments (`- skill # note` becomes `skill`) and surrounding quotes are stripped from each item.

python3 is the primary parser and a strict awk implementation the fallback. A python3 failure prints `python3 parser failed for <config>` on stderr and exits 1, so the nightly's `||` writes its unavailable sentinel. Only "neither parser present" degrades to "no ignores", and it logs that on stderr. A config that does not exist is an empty ignore set.

## Consequences

The three outcomes are different on purpose: absent config (empty set), parser failure (abort), no parser (empty set with a logged warning). Merging the last two into one quiet fallback brings back the false "all skills active" inventory. `CLEAN_ITEM` is awk text spliced into the awk program, so edits to it follow awk quoting, not shell (the single quote is the `\047` escape). The python and awk bodies carry their own inline comments because they are program text inside a string, not shell comments.
