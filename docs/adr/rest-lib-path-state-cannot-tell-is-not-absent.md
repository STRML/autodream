# rest: path_state has three answers, and "absent" is believed only under a searchable ancestor

Status: accepted · Date: 2026-11-22 · Code: `bin/lib-path-state.sh` (`path_state`)

## Context

`[ -e p ]` answers false for a path that exists but cannot be reached: a symlink whose target sits in a directory this user cannot search, or a path under an unsearchable parent. Code that reads false as "not there" then skips state it should have refused to run without. The omp L1 adapter and its store-unchanged test used `-e`/`-f` and a discarded `find` error as negatives and so treated "could not look" as "nothing there" (`docs/plans/2026-11-21-feat_omp-l1-writes-redesign.md`, section C).

## Decision

`path_state <path>` prints nothing and returns 0 (present), 1 (absent) or 2 (cannot tell). Present is `-e`. A symlink at the path that `-e` cannot follow is 2. Otherwise it walks up to the nearest ancestor that exists (or is a symlink), stopping at `/` or `.`, and returns 1 only when that ancestor is a searchable directory (`-d` and `-x`); anything else is 2.

## Consequences

Every existence check that gates a security decision has three outcomes, and "could not look" fails. The adapter (`adapters/omp/adapter.sh`) and `tests/lib-store-unchanged.sh` use it at each such site; `tests/l1-confine.sh` pins the five cases (file, missing under a searchable directory, dangling symlink, symlink into a locked directory, path under a locked directory). Do not collapse 2 into 1 at a caller.
