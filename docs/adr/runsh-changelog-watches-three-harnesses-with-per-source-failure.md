# runsh: the changelog window watches Claude Code, Codex and OMP, each with its own path, cache and failure line

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_sources`, `changelog_window`, `changelog_one`)

## Context

See CLAUDE.md, "Upstream changelog window". There is no remote `git blame` or `log`, so a persistent local cache is kept (not a tmpdir) and nightly cost is one delta fetch (the original comment said `git pull`; an owned cache now fetches and resets, see `changelog-owned-cache-follows-remote-by-reset`). git is the only dependency. The user works across three harnesses, and a release note only earns its place in the report when it lands in a tool in use. OMP is a monorepo with no root CHANGELOG; the CLI's log is at `packages/coding-agent/CHANGELOG.md`. The window matches the session scan exactly, so each release is reported once.

## Decision

`changelog_sources` prints `name|remote|path|cache-dir` records: Claude Code, Codex and OMP. The path is per source, never assumed. Each source has its own cache, its own clone/pull and its own `## <name>` section, so a dead remote writes an explicit failure line into its own section and never an empty file that reads like a quiet night upstream. An explicit `CHANGELOG_REMOTE` selects a SINGLE source and suppresses the defaults: back-compat for the old one-repo knob and load-bearing for the test suite, whose changelog test points it at a local fixture; a default list that still ran would have the suite cloning three real remotes, breaking the promise that it never touches the network. `AUTODREAM_CHANGELOG_SOURCES` (`;`-separated) overrides the whole set. The OMP default is `STRML/oh-my-pi`, the fork this host runs, which is rebased onto upstream on every sync, so it carries the build in use; to watch upstream itself set `AUTODREAM_CHANGELOG_SOURCES`. The Claude Code cache defaults to `$AUTODREAM_DIR/cache/claude-code` (`CLAUDE_CODE_REPO` overrides it). `AUTODREAM_CHANGELOG=0` disables the whole check, and a missing `git` skips it. Any failure is recorded in the output, never aborts the pipeline.

## Consequences

Do not hardcode `CHANGELOG.md` for a new source. Keep the `CHANGELOG_REMOTE` suppression, or the suite goes to the network. A new source needs its own cache directory under `$AUTODREAM_DIR/cache` to be treated as owned, see `changelog-cache-ownership-resolved-physically`.
