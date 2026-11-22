# tests-lib-project: the encoder is swept against every real on-disk bucket, counting only buckets that recorded a cwd

Status: accepted · Date: 2026-11-22 · Code: `tests/lib-project.sh` (the `$HOME/.claude` cross-check and the `sweep_root` loop)

## Context

Hand-written encoder cases cannot find a gap in the encoder that nobody thought of. An eyeball survey of dash-shaped bucket names found none for the space bug, because the broken form is also dash-shaped. The regression that motivated the suite: seanperkins/autodream-merge maps only `/`, so it produces `-Users-<u>-.claude` for a directory Claude stores as `-Users-<u>--claude`. The encoding itself is in `bin-a-lib-project-bucket-encoding`.

## Decision

The suite checks the encoder against the host's own `~/.claude/projects` corpus, and each check is inert where the corpus is absent.

- `$HOME/.claude` is checked only if its bucket exists, so the test is meaningful here and a no-op on a machine without that history.
- The sweep requires `encode_project` to reproduce each path-derived bucket name from a cwd recorded inside it. Buckets not starting with `-` are `CLAUDE_CODE_PROJECT_DIR_NAME` slugs (owner-repo), which override cwd encoding and would count as false misses, so the glob is `-*/`. It is anchored under `$sweep_root` and never left bare, since a name starting with `-` is an option to every tool that reads it.
- Every cwd in the sampled transcript is tried, not the first. Subagent records carry a different cwd, so `head -1` reported a false miss on a correct encoder while the test was being written.
- A bucket whose sampled transcript records no cwd (ai-title stubs and queue-operation envelopes carry none) is not a test case. Counting it as a miss failed the sweep on 50 buckets it had no evidence about.

## Consequences

A green result on a machine with no corpus proves nothing about the encoder, so the pinned literal cases remain the portable check. When the sweep reports a miss, read the first miss before touching the encoder: the sample or the cwd choice is as likely to be wrong.
