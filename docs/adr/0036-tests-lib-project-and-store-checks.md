# 0036: lib-project and lib-store suites must not pass vacuously

Status: accepted · Date: 2026-11-22 · Code: `tests/lib-project.sh` (the `declare -F` loop, the collation check, the `session_hash` stub-digest cases), `tests/lib-project.sh` (the `$HOME/.claude` cross-check and the `sweep_root` loop), `tests/lib-store-unchanged.sh` (`store_snapshot`, `store_unchanged`, `store_verdict`), used by `tests/l1-confine.sh` and `tests/l1-confine-real.sh`

## the suite guards against passing with no implementation and against a mutation-blind digest fixture

### Context

Three ways this suite could pass while testing nothing:

- With `encode_project` or `canonical_project` undefined, every comparison is empty-equals-empty and the suite is green against no implementation.
- A check of a hard-coded pattern does not exercise `session_hash`. Putting `[0-9a-f]` back into the function would pass it. Verified on this host: under bash 3.2 with an en_US.UTF-8 collation `A` matches `[0-9a-f]`, and under bash 5.3 it does not. The nightly runs `#!/bin/bash`, which is 3.2. The same behaviour made an uppercase adapter basename pass on CI and never locally (see `docs/adr/0002-session-enumeration.md#the-artifact-key-is-a-validated-12-character-hex-prefix-of-sha1-and-nothing-derives-it-any-other-way`).
- Under that collation the order runs `...eEfFgG...`, so `F` sorts after `f` and falls outside `a-f`, while `A` through `E` fall inside. A digest starting `ABCDEF` is rejected by the range form too, for the wrong reason. Verified character by character on this host.

### Decision

- The suite fails at once, and says the rest would be vacuous, when either function is not defined.
- The collation check runs under `/bin/bash` with `LC_ALL=en_US.UTF-8`, the shell and locale that expose the behaviour.
- The function itself is driven through a stub `shasum` whose digest is `ABCDE0123456789abcdef0123456789abcdef012`. It starts `ABCDE` and deliberately not `ABCDEF`, so the range form would accept it and the test fails against the regression it exists to catch. A 3-character digest must fail too: 12 characters is the contract, not a maximum.
- The range form's behaviour is printed as a `note`, not asserted. Asserting that the range is broken would fail the day a shell fixes it. What must hold is that our pattern rejects uppercase.

### Consequences

Do not lengthen the stub digest's uppercase prefix to `ABCDEF` or beyond, and do not turn the note into an assertion. Re-run under `/bin/bash` 3.2 after changing the hex class.

## the encoder is swept against every real on-disk bucket, counting only buckets that recorded a cwd

### Context

Hand-written encoder cases cannot find a gap in the encoder that nobody thought of. An eyeball survey of dash-shaped bucket names found none for the space bug, because the broken form is also dash-shaped. The regression that motivated the suite: seanperkins/autodream-merge maps only `/`, so it produces `-Users-<u>-.claude` for a directory Claude stores as `-Users-<u>--claude`. The encoding itself is in `docs/adr/0002-session-enumeration.md#a-project-key-is-the-physical-path-with-every-byte-outside-a-za-z0-9--mapped-to-a-dash-derived-once-in-lib-projectsh`.

### Decision

The suite checks the encoder against the host's own `~/.claude/projects` corpus, and each check is inert where the corpus is absent.

- `$HOME/.claude` is checked only if its bucket exists, so the test is meaningful here and a no-op on a machine without that history.
- The sweep requires `encode_project` to reproduce each path-derived bucket name from a cwd recorded inside it. Buckets not starting with `-` are `CLAUDE_CODE_PROJECT_DIR_NAME` slugs (owner-repo), which override cwd encoding and would count as false misses, so the glob is `-*/`. It is anchored under `$sweep_root` and never left bare, since a name starting with `-` is an option to every tool that reads it.
- Every cwd in the sampled transcript is tried, not the first. Subagent records carry a different cwd, so `head -1` reported a false miss on a correct encoder while the test was being written.
- A bucket whose sampled transcript records no cwd (ai-title stubs and queue-operation envelopes carry none) is not a test case. Counting it as a miss failed the sweep on 50 buckets it had no evidence about.

### Consequences

A green result on a machine with no corpus proves nothing about the encoder, so the pinned literal cases remain the portable check. When the sweep reports a miss, read the first miss before touching the encoder: the sample or the cwd choice is as likely to be wrong.

## "did the store change" compares two full snapshots, and a store that vanishes is a failure

### Context

A check that lists files newer than a marker sees none of three changes: a file that is gone, a file that is new in a way the marker misses, and a file reached only through a symlinked directory below the root. "Changed" has to include all three.

A store the snapshot cannot read must not read as unchanged either. A store that disappears during the call is the loudest change there is, not a case to skip.

### Decision

- `store_snapshot <dir> <out>` writes one `size mtime_ns path` line per regular file, following symlinks at every level, sorted. It returns 0 (written), 1 (could not scan) or 2 (no such directory) and prints a reason on 1 and 2.
- `store_unchanged <before> <after>` is a diff of two snapshots: 0 when identical, 1 with the differences printed.
- `store_verdict` holds the whole decision in one place. A store absent before the call is a skip (2). One that could not be scanned before is a failure (1). One that was there before and is gone, unreadable or different after is a failure.
- "Cannot tell" from `path_state` and an unreadable directory both return 1. They are never a pass.

### Consequences

Do not replace the snapshot with `find -newer`. A new outcome for the real check goes into `store_verdict`, not into a caller.
