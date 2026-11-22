# rest: the frontmatter reader resolves name, description and enabled by fixed rules, and a skill is ignored by name or by directory name

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (`read_frontmatter`, `strip_comment`, `scan_skill`)

## Context

`SKILL.md` frontmatter in the wild uses single-line values, block scalars (`>`, `>-`, `|`, `|-`) and inline comments. A skill's frontmatter `name:` routinely differs from the directory it lives in, and an operator disables a skill by whichever spelling they see.

## Decision

`read_frontmatter` reads the file head up to the closing `---` into `FM_NAME`, `FM_DESC` and `FM_ENABLED`, and stops at the closing delimiter.

- **name:** a single line, or a block scalar whose value is the first following indented line. A name left empty, or a block scalar whose value never came and is followed by a column-0 key, resolves to the directory basename. In that empty-block case the column-0 line is not swallowed: it is a real key and is processed normally.
- **description:** a single line, or a folded block (`>`/`>-`) in which all following more-indented lines are joined with single spaces. A column-0 line ends the fold and is processed as a key.
- **enabled:** only a false-family value (`false`, `False`, `0`, `no`) disables the skill. The first token is taken, which drops an inline comment.
- Inline YAML comments (`value # note`) are stripped from name and description the same way the config parse strips them from ignore lists (`strip_comment` cuts at the first ` #`).
- `scan_skill` skips a skill when its resolved name OR its on-disk directory name is in `ignoredSkills`.

## Consequences

Checking only the resolved name would leave a skill active that the operator disabled by its directory name. Treating an empty block-scalar name as a value would emit `>-` as a skill name (`scan_skill` also clears a name that is still a block-scalar marker). A reader that swallowed the column-0 line after an empty `name: >-` would lose the next key, for example `description:`.
