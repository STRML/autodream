# runsh: the changelog patch is read through a file so git's own status is seen

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, `changelog_patch`, `changelog_step`)

## Context

In a `blob:none` cache `git log -p` fetches old blobs from the remote, and a failure there piped straight into the filters read as "No changelog commits in this window" (panel review of PR #173).

## Decision

`changelog_one` makes a `mktemp` file under `${TMPDIR:-/tmp}` and runs `changelog_patch`, which writes `git log -p --reverse --since --until -- <path>` to it, through `changelog_step`, so git's stderr goes to the run log and a failure writes `Git log failed (<cause>)` into the source's section, removes the scratch file and fails the source. Only then do the `grep`/`awk` filters read the file. Failing to make the scratch file is its own failure section (`No scratch file for the changelog diff`).

## Consequences

Do not pipe `git log -p` straight into the filters. A failed log must never read as a quiet night; `test_changelog_log_failure_is_not_a_quiet_night` pins it with a git shim that fails only `log -p`. See CLAUDE.md, "Upstream changelog window".
