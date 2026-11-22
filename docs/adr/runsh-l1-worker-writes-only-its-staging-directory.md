# runsh: an L1 worker writes its answer only into a private staging directory, and the runner moves it out after the engine exits (#169)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`)

## Context
An engine holds the Write tool, so it could write any path the user can: another session's `<hash>.json` and `.served`, a chunk answer between the merge and the check, a new `*.json` L2 would read, `$AUTODREAM_DIR/config`. No marker in the findings dir can tell the runner's writes from a worker's, so the access changed instead.

## Decision
- The answer is written in a stage of its own (`$L1_STAGE_ROOT/<hash>.<answer name>`), one per answer file and reused by the retries of one run, and copied to `$2` once the engine has exited. The engine can then run under a sandbox that writes nowhere else. `$2` is cleared first: nothing an earlier attempt left there is this attempt's answer.
- A worker can leave a symlink where the private `tmp` goes. Unlinking follows nothing, so the runner removes it and makes the directory again, and one hostile worker cannot turn a retry into a failed night.
- An engine that keeps state it must write (omp) gets a throwaway one inside the stage: `l1-stage-env` seeds it and names the environment that points the engine there. Exit 2 is "no such verb" (claude); any other failure is an attempt that cannot start safely. That verb's stderr goes to a file in the staging root, beside the stages and not in one, because this runs outside the sandbox and a worker that left a symlink inside its own stage on an earlier attempt would otherwise have the redirection truncate whatever the link points at.
- After the engine exits the runner is the only writer. It renames the answer to `<answer>.stage` first and only then tests it (a rename does not follow a symlink, so what is tested is the thing that was moved and nothing can be swapped in between). Only a regular, non-empty file is kept; a symlink is refused and named in the `.err`, because reading it would read whatever it points at.

## Consequences
Do not test the answer before the rename. See CLAUDE.md, "A worker writes only its staging directory (#169)" and "What the sandbox allows".
