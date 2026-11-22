# rest: the omp skills inventory lists the active on-disk surface from fixed roots, standalone roots first, first name wins

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (header, `scan_skill`, `already_emitted`, the emit block)

## Context

The L2 prompt treats the output file as the authoritative active-skill list (`runsh-l2-adapter-inputs-skills-inventory-and-facts.md`). A skill that is on disk but disabled must not appear, and a list that claims more or fewer skills than are active misleads the coverage-gap findings. Some skills cannot be enumerated from the runner.

## Decision

- **Excluded:** skills named in `~/.omp/agent/config.yml` `skills.ignoredSkills`, and on-disk skills whose `SKILL.md` frontmatter sets `enabled:` to a false-family value. The built-in binary skills (compiled into the omp binary) and project-local `.claude/skills` are not enumerable from the runner and are deliberately absent. The output's own header says to reconcile those against the session skill surface.
- **Corpus:** every `$HOME/.claude*` bucket that exists (top-level `skills/*/SKILL.md` plus plugin skills found recursively under `plugins/`), and the standalone roots `$HOME/.agents/skills`, `$HOME/.config/opencode/skills` and `$HOME/.omp/agent/managed-skills`. The standalone roots are scanned first, then the buckets.
- **Dedup:** names are deduplicated, first occurrence wins, so the scan order above decides which copy of a name is reported.
- **Missing roots are normal.** An empty scan still writes a valid, header-only inventory.
- The script is read-only and uses `$HOME` throughout; it never expands `~`.

## Consequences

Reordering the roots changes which duplicate wins, and so which description L2 reads. A new skill root is a new loop in the emit block. An empty inventory is a real answer ("nothing active"), which is why failures exit 1 instead (`rest-omp-skills-inventory-ignored-skills-parse-fails-closed.md`).
