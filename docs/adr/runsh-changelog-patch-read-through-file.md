# runsh: the changelog patch is read through a file so git's own status is seen

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, `changelog_patch`, `changelog_step`)

## Context

In a `blob:none` cache `git log -p` fetches old blobs from the remote, and a failure there piped straight into the filters read as "No changelog commits in this window" (panel review of PR #173).

## Decision

`changelog_patch` writes `git log -p --reverse --since --until -- <path>` to a `mktemp` file under `${TMPDIR:-/tmp}`, run through `changelog_step` so git's stderr goes to the run log and a failure writes `Git log failed (<cause>)` into the source's section and fails the source. Only then do the `grep`/`awk` filters read the file. No scratch file is its own failure section.

## Consequences

Do not pipe `git log -p` straight into the filters. A failed log must never read as a quiet night. See CLAUDE.md, "Upstream changelog window".
