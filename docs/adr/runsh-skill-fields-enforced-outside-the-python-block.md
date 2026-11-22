# runsh: The mechanical skill fields are enforced from the sidecars with jq, outside the optional-python3 block

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `SKILLS_ENFORCED` loop)

## Context
The prompt asks the worker to copy `skills_invoked`, `skills_invoked_count`, `skills_invoked_counts` and `skills_authored` from the precomputed stats, but asking is not enforcing. Gating enforcement on an optional interpreter meant that on a host without `python3` the pipeline quietly returned to believing whatever the model wrote, the exact failure this replaced. `jq` is already a hard dependency of the script, so this cannot silently degrade. See CLAUDE.md, 'Skill fields are measured, not guessed'.

`compute_session_stats` regenerates every sidecar each run, so a sidecar that is missing, unreadable, or lacks any of the four skill keys means `session-stats.sh` did not measure this session's skills, and whatever skill fields the findings JSON carries are the worker's own guess. Checking one key was not enough: copying the keys that exist would leave the worker's guesses for the rest. A sidecar with missing keys passes generation's type check and only breaks here. Codex reviews of 0129fc0, cd309b6 and 33bf9b1.

## Decision
- The loop runs on every valid findings JSON (`L1_FINDINGS_OK` under `jq -s`). If the sidecar lacks any of the four keys, all four are deleted from the findings JSON and counted in `SKILLS_DROPPED`; otherwise the four are overwritten from the sidecar (`SKILLS_ENFORCED`).
- Rewrites that fail (full disk, unwritable dir), whether the delete or the overwrite, are counted in `SKILLS_FAILED`: the worker's own skill fields survive in those files, so the count has to be visible or L2 ranks guesses as measurements. `SKILLS_DROPPED` and `SKILLS_FAILED` reach run-stats as `skills_unmeasured` and `skills_enforcement_failed`.

## Consequences
- Keep this step independent of python3.
- Never keep a subset of the worker's fields when the sidecar is incomplete.
