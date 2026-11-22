# bin-b: counts use `grep -c ... || true`, never `|| echo 0`

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`count_matches`)

## Context

With zero matches, `grep -c` prints `0` and exits 1. A fallback `|| echo 0` then fires too, and the substitution captures the two-line string `0\n0`. The arithmetic that follows dies, and under `set -e` that took the whole `collect` down, writing no `operator-notes.md`. The input is not hypothetical: it is `notes.md` after the user deletes the notes a report said were addressed, leaving only the header `autodream-note.sh` writes. `status` printed nonsense on the same file.

## Decision

`count_matches` takes grep's stdout, ignores its status with `|| true`, and defaults an empty result (a missing file prints nothing) to `0`. `collect` and `status` both count through it.

## Consequences

Do not inline a new count as `$(grep -c ... || echo 0)`. CLAUDE.md, "Bash traps this feature hit", lists this first.

`vault_subdir` has the same trap in a different shape. A function that ends on a failed `[ -n "$VAULT_DIR" ]` returns that status, and `dir=$(vault_subdir inbox)` then aborts the script under `set -euo pipefail`, which is the no-vault case and the most common one. It is written `[ -z "$VAULT_DIR" ] || printf ...` so it returns 0 on both paths; do not rewrite it as `[ -n ... ] && printf ...`.
