# runsh: run.sh sources the config in a nounset-off, `set -a` block and replays the caller's exported environment

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `AUTODREAM_CONFIG` block after `AUTODREAM_DIR`)

## Context
run.sh historically ignored `~/.claude/autodream/config`; only review.sh sourced it. That was fine while every key was review-only, and stopped being fine when a key had to reach the nightly run (`AUTODREAM_VAULT_DIR`). The script runs under `set -u`, and sourcing a user-edited file under nounset makes ANY unbound reference in it (for example a typo'd `X_CREDS_FILE=$AUTODREAM_HOME/x-credentials`, meaning AUTODREAM_DIR) abort the shell before LOG_DIR or `log()` exist, so nothing reaches the run log and no report is produced. `|| echo WARNING` cannot catch that, because nounset kills the shell instead of making `.` return non-zero. run.sh never sourced the file before the vault-notes feature, so a typo that used to be harmless would silently cost a night.

## Decision
See CLAUDE.md, "run.sh sources the config now". In the code:
- The block runs after AUTODREAM_DIR is resolved, so AUTODREAM_DIR itself must come from the environment, not the config (it names the config's own location).
- The caller's exported environment is snapshotted (`export -p`), the config is sourced, and the snapshot is replayed with `eval`, so names the caller set win and names only the config sets survive. The config uses plain `KEY=value`, so a bare `.` would let it clobber a variable the caller deliberately exported (tests set env; `AUTODREAM_VAULT_DIR= run.sh` must disable the vault).
- `set -a` wraps the source: helper scripts are separate processes, so a config key that stays an unexported shell variable reaches nothing.
- Pass 1 sources the config in a throwaway subshell under `set -u`, only so bash's own error (which names the unbound variable) can be surfaced as a WARNING. A subshell dying from `set -u` does not kill this shell and touches no real state.
- Pass 2 sources for real with nounset off, so a bad reference degrades to an empty expansion for that one reference and every other key (before or after the bad line) is still set and exported.

## Consequences
Both helper scripts that source the config need the same guard (fixing only run.sh left them dying). Keep the probe subshell: removing it loses the diagnostic naming the bad variable. Keep `set -a` and the snapshot replay together.
