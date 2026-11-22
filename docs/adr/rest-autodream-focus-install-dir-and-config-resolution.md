# rest: the focus writer resolves its install dir, config and helpers the way the collector does

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (top-level resolution of `AUTODREAM_DIR`, `AUTODREAM_CONFIG`, `TAGS_FILE`, `_pp`, `LINEARIZE`; the `path` verb)

## Context

`bin/vault-notes.sh` reads pending tags from `$AUTODREAM_DIR/config`'s view of the world, so a tags file named only in that config is the file the nightly run reads. A writer that looked only at its own environment would write one file while the collector read another, and the tag would never reach a report. The Claude mod and the OMP picker cannot source a shell file, so they ask the script where the file is (`autodream-focus.sh path`) instead of resolving it themselves; see `docs/adr/bin-b-mods-focus-tags-file-asks-writer.md`.

CLAUDE.md, "The focus mod", records the rule that the script reads `$AUTODREAM_DIR/config` the way the collector does and that the caller's exports win.

Installed copies of the script are symlinks into the repo's `bin/`, so a sibling helper sits next to the link in an installed tree and next to the link's target in a repo checkout.

## Decision

- `AUTODREAM_DIR` is the environment's value, else the script's own directory when it carries an install marker (`config` or `PROMPT.md`), else `$HOME/.claude/autodream`.
- The config (`AUTODREAM_CONFIG`, default `$AUTODREAM_DIR/config`) is sourced with `set -a` so its keys are exported, with errexit and nounset off so a bad line cannot kill the script, and the `export -p` snapshot taken before is replayed after, so the caller's exports beat the file. Same two guards the collector and `run.sh` use.
- `TAGS_FILE` is `AUTODREAM_TAGS_FILE`, else `$AUTODREAM_DIR/tags.jsonl`. The `path` verb prints it.
- `portable.sh` and `adapters/omp/linearize.sh` are looked for next to the script path first (installed link tree), then next to `readlink` of it (checkout).
- Environment the script reads: `AUTODREAM_DIR`, `AUTODREAM_TAGS_FILE`, `CODEX_HOME` (default `$HOME/.codex`), `PI_CODING_AGENT_DIR` (OMP's agent directory, default `$HOME/.omp/agent`; `OMP_AGENT_DIR` was a first guess and is wrong).

## Consequences

A new key the collector learns to read from the config needs the same handling here, or the two disagree on which file is the tags file. The OMP extension (`extensions/omp/focus-core.ts`, `tagsPath`) mirrors this order as its fallback; see `docs/adr/rest-omp-focus-extension-is-a-thin-command.md`.
