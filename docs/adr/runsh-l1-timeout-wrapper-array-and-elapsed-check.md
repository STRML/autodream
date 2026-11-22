# runsh: the L1 worker timeout is a wrapper array set outside the pipe, and a timeout is recognised by exit code plus elapsed time

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `l1wrap`; `l1_attempt`: `l1start`, timeout check)

## Context
A worker that never exits holds its `xargs -P` slot forever (2026-08-19 and 2026-08-22 each sat wedged for days). A brace group in a pipeline runs in a subshell, so an assignment made inside it is invisible to the right-hand side. GNU `timeout` propagates the child's own status, so a worker that exits 124 by itself, or that the OOM killer SIGKILLs at second zero, looks like a real timeout (verified against coreutils 9.11: a self-killed child returned 137 after 0s under a 100s bound). `t0` is taken before validation, the noise gate and slimming, so a large transcript can burn real time before `timeout` is launched.

## Decision
- `l1wrap=("$TIMEOUT_BIN" -k "$L1_KILL_GRACE" "$AUTODREAM_L1_TIMEOUT")` is an array set outside the brace group, so the wrapper cannot silently disappear. A path with spaces is safe in an array.
- `l1start` is stamped inside `l1_attempt`, right before the engine starts, never reused from `t0`.
- A timeout is declared only when `TIMEOUT_BIN` is set, the exit code is 124 or 137, and elapsed time is at least `AUTODREAM_L1_TIMEOUT`. 137 is 128+SIGKILL, which is what the `-k` grace period escalates to. Second resolution leaves a one-second boundary window against a twenty-minute bound.
- A timeout appends a line to the `.err` and the hash to `l1-timeouts.txt`. The ledger exists because the `.err` is truncated by the next retry and deleted whenever the worker succeeds or leaves output, so a timeout that later succeeds would vanish from the stats; the ledger is per-run and append-only.
- A timeout removes the findings file: a worker killed mid-write leaves truncated JSON that would read as success, delete the errlog and feed partial input to L2. The session retries like any other failure.

## Consequences
Without GNU `timeout` (macOS ships none) the run degrades to unbounded and says so (`l1_timeout_bin: none`). See CLAUDE.md, "A hung worker, a cold token and a deterministic failure".
