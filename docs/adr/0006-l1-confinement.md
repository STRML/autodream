# 0006: L1 confinement: the sandbox, the stage and what a worker may write

Status: accepted · Governs: `adapters/claude/adapter.sh`, `bin/l1-confine.sh`, `bin/run.sh`

This record holds 14 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Who starts the L1 worker (decision 2 of the consolidation) (confinement)](#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement)
- [an L1 worker may write only its staging directory plus a default-deny list that holds the CLI's own cache](#an-l1-worker-may-write-only-its-staging-directory-plus-a-default-deny-list-that-holds-the-clis-own-cache)
- [engine-prefix builds the prefix from the adapter's own write list, split without a temp file](#engine-prefix-builds-the-prefix-from-the-adapters-own-write-list-split-without-a-temp-file)
- [every path is checked, and resolved, before it can reach a sandbox profile or a bind](#every-path-is-checked-and-resolved-before-it-can-reach-a-sandbox-profile-or-a-bind)
- [the sandbox probe runs a real confined shell and checks both sides of the boundary](#the-sandbox-probe-runs-a-real-confined-shell-and-checks-both-sides-of-the-boundary)
- [protected paths are denied after the writable ones, and bwrap binds protected paths read-only, stage last](#protected-paths-are-denied-after-the-writable-ones-and-bwrap-binds-protected-paths-read-only-stage-last)
- [an L1 worker runs under an OS sandbox that denies every write except its staging directory](#an-l1-worker-runs-under-an-os-sandbox-that-denies-every-write-except-its-staging-directory)
- [with bwrap a trailing-star write rule covers only files that exist at launch, and run-stats says so](#with-bwrap-a-trailing-star-write-rule-covers-only-files-that-exist-at-launch-and-run-stats-says-so)
- [L1 confinement setup builds the real prefix and state directory up front, and a refusal is a fatal, never a quiet unconfined engine](#l1-confinement-setup-builds-the-real-prefix-and-state-directory-up-front-and-a-refusal-is-a-fatal-never-a-quiet-unconfined-engine)
- [L1 confinement setup prepares only the engines that still have work](#l1-confinement-setup-prepares-only-the-engines-that-still-have-work)
- [a missing l1-confine.sh runs workers unconfined and says so, rather than failing the night](#a-missing-l1-confinesh-runs-workers-unconfined-and-says-so-rather-than-failing-the-night)
- [the isolated work bucket is exported to workers but is not on the confinement write list, so run.sh keeps wiping it](#the-isolated-work-bucket-is-exported-to-workers-but-is-not-on-the-confinement-write-list-so-runsh-keeps-wiping-it)
- [an L1 worker writes its answer only into a private staging directory, and the runner moves it out after the engine exits (#169)](#an-l1-worker-writes-its-answer-only-into-a-private-staging-directory-and-the-runner-moves-it-out-after-the-engine-exits-169)
- [Each L1 engine call writes only its own staging dir under an OS sandbox, and the runner copies the answer out](#each-l1-engine-call-writes-only-its-own-staging-dir-under-an-os-sandbox-and-the-runner-copies-the-answer-out)

## Background: Who starts the L1 worker (decision 2 of the consolidation) (confinement)

This section was moved here from the former CLAUDE.md. Its original title: "Who starts the L1 worker (decision 2 of the consolidation) (confinement)".

- **A worker writes only its staging directory (#169).** An L1 engine holds the Write tool, so it used to be able to write any path the user can: another session's `<hash>.json` and `.served`, a chunk answer between the merge and the check, a new `*.json` L2 would read, `$AUTODREAM_DIR/config`. No marker in the findings dir can tell the runner's writes from a worker's, so the access changed instead. `l1_attempt` makes `$AUTODREAM_DIR/staging/run-<pid>/<hash>.<answer name>/` (0700, with a private `tmp/` that becomes the engine's `TMPDIR`), tells the worker to write its answer there, runs the engine under `bin/l1-confine.sh engine-prefix` (a `sandbox-exec` profile on macOS, `bwrap` on Linux) and, after the engine has exited, renames the answer to `<answer>.stage` beside the findings path and tests that file: a rename does not follow a symlink, so the thing tested is the thing moved, and only a regular file is kept (a symlink is refused and named in the `.err`). A `.stage` left by a killed run is swept at the next start, `.chunks/` included. Everything after that, the `served` verdict, the validity check, the `.served` marker, runs on the runner's copy as before. The stage is reused by the retries of one run (the mock's per-answer state files live in it) and removed on success; the staging root goes when the rounds end, and a root whose run is dead is swept at the next start.
- **What the sandbox allows.** Writes are denied everywhere except the stage, the adapter's `l1-writes` list, and a few `/dev` nodes. The claude list is default deny: the CLI's own cache (`claude-cli-nodejs`) and whatever the operator names in `AUTODREAM_L1_WRITES_EXTRA` (absolute paths; one that is relative, holds a character a profile cannot hold, or is itself a symlink is refused). The isolated work bucket is not on it: it is the one directory every worker, the thread linker and a concurrent date's L2 share, and a confined call exits 0 with its AI-title write refused (`tests/l1-confine-real.sh --no-bucket`, 2026-11-21). `run.sh` still wipes it before L1, after L1 and after L2, because an unconfined engine can write it. Not on it, each a way for an injected worker to run code as the user later: `~/.claude.json` and its backups (MCP servers, allowed tools), `session-env` (hook env files a live session sources), settings, hooks, skills, plugins and the CLI install. `$AUTODREAM_DIR`, the findings dir and the dreams dir are denied after the state paths (a default install keeps `$AUTODREAM_DIR` under `~/.claude`) and the stage allow comes last. Reads, the network and exec are unchanged. `docs/plans/2026-11-21-l1-confine-write-list.md` has the table, the measurement and what to do when a confined call fails without something.
- **A host with no working sandbox says so.** `l1_confine_setup` runs `l1-confine.sh probe` once per run: it starts a confined shell, writes inside a stage and beside it, and trusts neither the tool's exit code nor its acceptance of the profile. `l1_confined: yes|partial|no`, `l1_confine_tool`, `l1_confine_reason` and `l1_confine_extra` go in run-stats, `l1_confined_<engine>` per engine, and a WARNING in the log when the answer is no without `AUTODREAM_L1_CONFINE=0`. The top-level line is `yes` only when every engine with sessions is confined, `partial` when some are not and `no` when none is, so a night with omp sessions never reads like a fully confined one. The probe builds a prefix with no paths, so setup then builds each engine's real prefix (`l1-confine.sh engine-prefix`, the same call every worker makes) with its own write list, the operator's additions and the protect list; a failure there (or a protected directory holding a colon, or a relative one) is a fatal before any worker starts: no stubs, no report, a banner, and the date is retried. A prefix that cannot be built at call time still fails that attempt and never runs it unconfined. An engine whose adapter has no `l1-writes` verb runs unconfined and reports `l1_confined_<engine>: no`; the claude and omp adapters both have one. omp cannot run on an empty list, so its adapter also has `l1-stage-env`: each confined omp worker gets a `HOME` inside its stage (and `PI_CONFIG_DIR` and `PI_CODING_AGENT_DIR` pinned to it), seeded with the files it only reads and one SQLite backup-API snapshot of each database with the OAuth credential rows left out, so every omp write lands there and no refresh token is rotated in a copy that is thrown away. Setup runs that verb once with the engine's model: an unreadable database is a fatal before L1, and a model whose only credential is OAuth leaves omp unconfined (`l1_confined_omp: no`, with the reason) instead of failing every worker. A setup failure before the engine starts (the state verb, the stage, the sandbox) is ledgered as `staging`, writes no stub, and when it is what the last round left missing it is a fatal (banner, `fatal:` in run-stats, the marker the next run reads), not an outage deferral: it heals nothing by waiting, and with no findings JSON `unassembled_dates` would never name the date. A network or provider deferral carries `l1_deferred_cause` in run-stats. The L1 overlay turns omp's memory backend off (`memory.backend: off`) and `mcp.json` is not seeded, because a worker that retained or consolidated memory would write a store every later session recalls from (`docs/plans/2026-11-21-omp-l1-writes.md`). The suite exports `AUTODREAM_L1_CONFINE=0` because the mock engines write capture files anywhere; the confinement tests turn it on and skip where `sandbox-exec` cannot start (it cannot inside another sandbox).
- **Verified by hand, not in CI:** the real `claude` call under the profile. `tests/l1-confine-real.sh` is the manual check (one real call, outside any other sandbox); `--measure` lists what an unconfined call writes under the claude-owned paths in `$HOME`, `--no-bucket` drops the work bucket from the list. Measured 2026-11-21 on the default-deny list: ALL PASS, with no `AUTODREAM_L1_WRITES_EXTRA` needed. An unconfined call writes only `~/.claude/plugins/{store,cache,known_marketplaces.json}` beyond that, and the confined call works without them. Unverified: a token refresh inside the sandbox. The serial warmup is unconfined and refreshes an expired token before any confined worker starts, so only a token that expires mid-run would hit it, and a login failure under confinement classifies as `provider` (retried), not as a stub for a size problem.

## an L1 worker may write only its staging directory plus a default-deny list that holds the CLI's own cache

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`l1-writes`, `nl_refuse`)

### Context

`run.sh` runs the worker under an OS sandbox that can write nothing else (#169, `bin/l1-confine.sh`), so this list is the whole of what the claude CLI may touch of its own. The table, the measurement and the procedure for a confined call that fails without something are in `docs/plans/2026-11-21-l1-confine-write-list.md`; docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "What the sandbox allows", summarizes it.

### Decision

Default deny: a path is listed only because a confined call needs it or because it is a cache no later run executes. Today that is the CLI's own cache (`~/Library/Caches/claude-cli-nodejs`, `~/.cache/claude-cli-nodejs`), which holds logs and nothing read as code. Deliberately not listed, each a way for a prompt-injected worker to run code as the user later: `~/.claude.json` and its backups (`mcpServers`, `allowedTools`, `enabledMcpjsonServers`), the config dir's settings, hooks, skills and plugins, `session-env` (sessionstart-hook env files a live session sources), and the CLI's install dir (auto-update writes executables there). The isolated work bucket, where an AI-title stub lands, is not listed either: it is the one directory every worker, the thread linker and a concurrent date's L2 share, and a confined call exits 0 with its write refused (`tests/l1-confine-real.sh --no-bucket`, measured 2026-11-21).

A host whose confined call fails without something else names it in `AUTODREAM_L1_WRITES_EXTRA` (colon-separated, absolute, a trailing `*` is a prefix) and accepts that path's exposure. The output is one path per line, so a path holding a newline would read as two; `HOME` or an extra entry that does is refused outright (exit 3), not split, because the second half could be a directory like `/Users/you`. Globbing is off while the extras are split, so an entry such as `~/.claude.json*` stays a prefix and does not expand to the files that exist.

### Consequences

Adding a path widens what an injected worker can persist. Check the "not listed" reasons above before adding one.

## engine-prefix builds the prefix from the adapter's own write list, split without a temp file

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`cmd_engine_prefix`)

### Context

Setup and every worker call must build the same prefix from the same list, or a list that cannot be confined is found only when a worker runs. The list also has to survive its own parsing: a temp file or loop that fails part-way would leave an empty list behind, and an empty list is a valid, narrower sandbox that silently drops state paths the engine needs.

### Decision

`engine-prefix <adapter.sh> <stage>` runs `<adapter.sh> l1-writes` and exits 1 with the reason when the adapter declares no write profile (exit 2) or fails for another reason (first 200 characters of its stderr, exit status in the message). The list is one path per line, split by `IFS` alone (globbing is off for the whole script) into the positional parameters, with no here-string and no loop, so there is no temp file whose failure could leave an empty list. An adapter refuses to print a path that holds a newline, since a line is the only separator there is. `IFS` is restored before the prefix is built.

### Consequences

An adapter whose `l1-writes` exits nonzero for any reason is unconfinable, not unconfined by accident: the runner treats that as a setup failure. Do not replace the split with a `read` loop or a here-string without keeping the property that a failure cannot yield a shorter list.

## every path is checked, and resolved, before it can reach a sandbox profile or a bind

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`safe_path`, `resolve_path`, `profile_path`, `check_writable`, `check_protect`, `check_stage`, `check_all`)

### Context

The profile is text handed to `sandbox-exec -p`, and the bwrap argv names paths directly. A path that holds a quote or a newline can close the string and add a rule; a glob character becomes a pattern; a symlink as a writable path grants its target; a relative path means something different in the engine's cwd. The checks were added by the #241 review follow-ups (#244, `docs/plans/2026-11-21-l1-confine-hardening.md`).

### Decision

Before any path is used, whatever the tool:

- A writable path must be absolute, made only of the characters a profile can hold (`A-Za-z0-9._/@+~=,:` space and `-`: no glob, no quote), and must not itself be a symlink. A trailing `*` marks a prefix and is stripped before the check.
- A protected path (from `L1_CONFINE_PROTECT`, colon-separated) must be absolute and profile-safe. `$AUTODREAM_DIR` sits under `~/.claude` on a default install, so it must be denied after the state paths that cover it.
- The stage must not be a symlink and must exist; when `L1_STAGE_ROOT` is set it must resolve under that root.
- The checked path is resolved again, as the kernel sees it, before it enters the profile (`profile_path`). `resolve_path` resolves the part that exists, so a symlinked parent (`/tmp`, `/var`, `~` on some hosts) compares as the kernel sees it, and keeps the tail of a path that does not exist yet. A regular file cannot be `cd`'d into, so its parent is resolved and its name kept. The second check exists because a symlink can lead to a name the profile text cannot hold, which the check on the supplied path never saw.
- Globbing is off for the whole script (`set -f`). The one place a prefix rule needs it, the bwrap loop that expands `${p%*}*`, turns it on for that loop and off again.

A refusal is a message on stderr and exit 1; `engine-prefix` and `prefix` print no argv in that case.

### Consequences

A new field that reaches a profile or a bind gets the same checks first, or it is an injection point. Checking only the supplied path, not the resolved one, was the gap the second check closes. `tests/l1-confine.sh` pins the refusals (quote, newline, symlink, relative path, glob in a protected path, stage outside the staging root).

## the sandbox probe runs a real confined shell and checks both sides of the boundary

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`cmd_probe`)

### Context

A sandbox tool can accept a profile and confine nothing, or start and refuse everything. Trusting its exit code or its acceptance of the profile reports "confined" for a host where workers can still write anywhere (#169), or reports "not confined" for a host that is fine.

### Decision

`l1-confine.sh probe` prints one line, `yes<TAB><tool>` or `no<TAB><reason>`, and always exits 0. It makes a temp directory with a `stage` and an `outside` directory, builds a prefix with no protected paths and no stage root, and runs a confined `/bin/sh` that writes a file inside the stage and then tries to write one in `outside`. The answer is `yes` only when the stage write landed and the outside write did not. Distinct `no` reasons: no tool on PATH, no probe directory, the tool could not build a profile, the tool rejected the profile or could not start (with its exit code and the first 200 characters of stderr), the stage was not writable, the outside write was not refused. The script that tries the outside write is written to exit 0 even when that write is refused, so a nonzero exit means the tool failed, not the write.

### Consequences

`run.sh` runs the probe once per run and reports `l1_confined` from it (`docs/adr/0006-l1-confinement.md#a-missing-l1-confinesh-runs-workers-unconfined-and-says-so-rather-than-failing-the-night`). The probe builds a prefix with no paths, so the real per-engine prefix is built separately at setup. The suite skips the real-sandbox cases where `sandbox-exec` cannot start (it cannot inside another sandbox).

## protected paths are denied after the writable ones, and bwrap binds protected paths read-only, stage last

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`emit_prefix`, `sb_profile`)

### Context

A default install keeps `$AUTODREAM_DIR` under `~/.claude`. A writable rule that covers a directory under `~/.claude` would then grant the engine the runner's own state.

### Decision

`L1_CONFINE_PROTECT` (colon-separated) names paths the engine cannot write even when a writable path covers them. Under `sandbox-exec` each is a `(deny file-write* (subpath ...))` placed after the writable allows, and the stage allow comes last. Under bwrap the writable paths are bound read-write, each protected path is then bound read-only over them, and the stage is bound last, so a protected path wins inside a writable directory and the stage wins inside a protected one.

bwrap binds an existing path, so a prefix rule binds the files that already match it (`~/.claude.json` itself, written in place) and cannot cover a temp file created later. `sandbox-exec` can. Symlinks matched by a prefix are skipped, so a prefix cannot grant a link's target.

### Consequences

The bwrap limit shows up in run-stats as `l1_confine_note` (`docs/adr/0006-l1-confinement.md#with-bwrap-a-trailing-star-write-rule-covers-only-files-that-exist-at-launch-and-run-stats-says-so`). Reordering the deny and allow lines changes which one wins; the order is the rule. The protect list is built and validated by the runner (`docs/adr/0006-l1-confinement.md#each-l1-engine-call-writes-only-its-own-staging-dir-under-an-os-sandbox-and-the-runner-copies-the-answer-out`).

## an L1 worker runs under an OS sandbox that denies every write except its staging directory

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`emit_prefix`, `sb_profile`, `tool_for`)

### Context

An L1 worker holds the Write tool, so until #169 it could write any path the user can: another session's findings, a chunk answer before the runner checked it, a new `*.json` in the findings dir, `$AUTODREAM_DIR/config`. No check on the files in the findings dir can tell the runner's writes from a worker's, because the worker can forge any marker the runner could leave. So the access is what changes, not the validation.

### Decision

The runner makes a staging directory per answer (`run.sh` does that, not this helper), tells the worker to write its answer there, runs the engine under an OS sandbox that can write only that directory plus the narrow list of state paths the engine itself needs, and copies the answer into the findings dir after the engine has exited. `bin/l1-confine.sh` builds the sandbox around the stage and is the only place that knows the two tools:

- `sandbox-exec` (macOS) gets a profile of `(allow default)` then `(deny file-write*)`, a short allow list of `/dev` nodes (`/dev/null`, `/dev/tty`, `/dev/dtracehelper`, `/dev/stdout`, `/dev/stderr`, `/dev/fd/N`), the writable paths, the protected paths as later denies, and the stage allow last so it wins inside a protected directory.
- `bwrap` (Linux) gets a read-only bind of `/` and read-write binds of the same list.
- `L1_CONFINE_TOOL=sandbox-exec|bwrap` picks the tool; unset prefers `sandbox-exec`, then `bwrap`; any other value is refused. A named tool that is not on PATH yields no prefix.

The profile denies writes only. Reads, the network and process exec are unchanged: the engine must read transcripts and reach its provider, and read access is not what #169 is about.

The subcommands are `probe`, `prefix <stage> [writable-path ...]` and `engine-prefix <adapter.sh> <stage>`; `prefix` prints a NUL-delimited argv to put in front of the engine command. A writable path is a directory (`subpath`), or a prefix when it ends in `*` (`~/.claude.json` and, under `sandbox-exec`, the temp files claude renames over it).

### Consequences

Setup and every worker call build the same prefix from the same list, so a list that cannot be confined is found before a worker starts (see `docs/adr/0006-l1-confinement.md#l1-confinement-setup-builds-the-real-prefix-and-state-directory-up-front-and-a-refusal-is-a-fatal-never-a-quiet-unconfined-engine`). The bwrap limit on prefix rules is in `docs/adr/0006-l1-confinement.md#with-bwrap-a-trailing-star-write-rule-covers-only-files-that-exist-at-launch-and-run-stats-says-so`. The write list and the work-bucket decision are in `docs/adr/0006-l1-confinement.md#an-l1-worker-may-write-only-its-staging-directory-plus-a-default-deny-list-that-holds-the-clis-own-cache` and `docs/adr/0006-l1-confinement.md#the-isolated-work-bucket-is-exported-to-workers-but-is-not-on-the-confinement-write-list-so-runsh-keeps-wiping-it`; the runner side is `docs/adr/0006-l1-confinement.md#each-l1-engine-call-writes-only-its-own-staging-dir-under-an-os-sandbox-and-the-runner-copies-the-answer-out` and docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A worker writes only its staging directory (#169)" and "What the sandbox allows". Widening the deny to reads or the network would break the engine; widening the allow list grants every worker the same write, so add a path only with a measurement (`tests/l1-confine-real.sh --measure`).

## with bwrap a trailing-star write rule covers only files that exist at launch, and run-stats says so

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_stat_lines`)

### Context
`bwrap` binds existing paths. A prefix rule (a trailing `*` in `AUTODREAM_L1_WRITES_EXTRA` or an adapter write list) therefore covers the files that exist when the sandbox starts and not one created later. `sandbox-exec` has no such limit.

### Decision
When `L1_CONFINE_USING` is `bwrap`, `l1_confine_stat_lines` adds `l1_confine_note: bwrap prefix rules bind existing files only` to the L1 section of `run-stats.txt`, after `l1_confine_extra`. `l1_confine_stat_lines` has one call site, the main run-stats block; the no-sessions stub block prints only `l1_confined: not_reached`, so the note is absent there. The line before it, `l1_confine_extra`, echoes `AUTODREAM_L1_WRITES_EXTRA` (or `none`) so a sandbox widened by the operator does not read like the default one.

### Consequences
A write that works under `sandbox-exec` on macOS can be refused on Linux for a file that did not exist at launch. Read the note before debugging a confined worker on Linux. Removing the line hides a real platform difference from the artifact.

## L1 confinement setup builds the real prefix and state directory up front, and a refusal is a fatal, never a quiet unconfined engine

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`)

### Context
The sandbox probe builds a prefix with no paths. The real prefix carries an engine's write list, the operator's `AUTODREAM_L1_WRITES_EXTRA` additions and the protect list, and a character the profile cannot hold in any of them fails every call. Found late, that costs a stub for every session instead of one stopped run. Likewise a state directory that cannot be prepared (omp's throwaway `HOME`) fails every worker. A model whose only credential is OAuth cannot run on a throwaway copy: a token refresh in the copy would lose the rotated token.

### Decision
For each engine with work, setup:
1. Runs `adapter.sh l1-writes`. Exit 2 means the adapter declares no write profile (the engine is recorded `l1_confined_<engine>: no` with a reason and a WARNING). Any other result goes on to step 2, so a write list the adapter refused is not an engine that quietly runs unconfined: it surfaces there as a fatal with the reason.
2. Builds the real prefix once with `l1-confine.sh engine-prefix` (which reads the same `l1-writes` list) against a `.setup-<engine>` stage; a failure, including a refused write list, sets `L1_CONFINE_FATAL` ("the <engine> engine's sandbox cannot be built") and stops the run before any worker starts.
3. Runs `adapter.sh l1-stage-env` once with the model the engine's sessions use. Exit 0 or 2 (no such verb) confines the engine. Exit 4 (a model a throwaway state cannot serve) leaves this engine unconfined with the reason and a WARNING. Any other exit is a fatal ("the <engine> engine's state directory cannot be prepared"). The reason in each fatal and WARNING is cut to 300 characters with newlines and tabs replaced by spaces.

### Consequences
The "(omp)" in the original comment on exit 2 is out of date: both the claude and omp adapters now declare `l1-writes`, so exit 2 reaches this branch only for an adapter with no such verb. Exit 2 from `l1-stage-env` means "no state directory needed" (claude). Do not turn a nonzero `l1-writes` exit into "unconfined": the denial is the safe answer. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A host with no working sandbox says so".

## L1 confinement setup prepares only the engines that still have work

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`, `l1_missing_engines`, `L1_SETUP_SKIPPED`, `l1_attempt`)

### Context
`l1_confine_setup` builds a real sandbox prefix and, for omp, a seeded state directory per engine. An engine whose sessions already have findings from an earlier run has no worker to start, so preparing it costs time and can raise a fatal for nothing.

### Decision
`needed=$(l1_missing_engines)` restricts `all_engines` to engines with sessions still missing a findings JSON. Every other engine is listed in `L1_SETUP_SKIPPED`. `l1_attempt` checks that list and fails the attempt (`l1_infra_fail`, ledgered `staging`) when a worker reaches a skipped engine anyway, so such an engine is never run unconfined by default. This applies only when the sandbox probe said yes (`L1_CONFINED=yes`); with confinement off or unavailable `L1_SETUP_SKIPPED` stays empty. When no engine has work at all, every engine is listed as skipped and `l1_confined` reads `n/a`.

### Consequences
Anything that makes a worker use an engine `l1_missing_engines` did not report (a changed source map, a late re-dispatch) fails closed instead of running unconfined. Keep `l1_missing_engines` and the dispatcher's engine choice in step. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A worker writes only its staging directory (#169)" and "A host with no working sandbox says so".

## a missing l1-confine.sh runs workers unconfined and says so, rather than failing the night

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`L1_CONFINER`; `l1_confine_setup` reads it)

### Context
Issue #169: an L1 engine holds the Write tool and could write any path the user can, so workers run under `bin/l1-confine.sh`. `find_lib` looks beside the runner and then in the repo's own `bin/`, because a merge swaps `run.sh` before `install.sh` links the new helpers, so a helper added by that merge can be absent.

### Decision
`L1_CONFINER` is resolved with `find_lib`. Empty means `l1_confine_setup` records the reason "l1-confine.sh not found" and workers run as before; run-stats reports `l1_confined: no` with the reason, and the log carries `WARNING: L1 workers run unconfined (l1_confined: no): l1-confine.sh not found` unless `AUTODREAM_L1_CONFINE=0` was set on purpose. Unlike `report-format.sh`, `err-cause.sh` and `failure-class.sh`, whose absence is fatal, this helper degrades: a night's triage is worth more than the sandbox on a host that predates it. A helper that exists but cannot build an engine's prefix fails that attempt and never runs unconfined. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A worker writes only its staging directory (#169)" and "A host with no working sandbox says so".

### Consequences
The unconfined mode is only acceptable because it is visible in run-stats and the log; keep it visible.

## the isolated work bucket is exported to workers but is not on the confinement write list, so run.sh keeps wiping it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`, `clean_work_bucket`)

### Context
Workers launch from `$WORK_DIR` so a Claude Code AI-title stub lands in `$WORK_BUCKET` and not in the real session bucket. That bucket is the one directory every worker, the thread linker and a concurrent date's L2 share.

### Decision
`l1_confine_setup` exports `AUTODREAM_WORK_BUCKET="$WORK_BUCKET"` (read only by `tests/l1-confine-real.sh` and the mock engine; no adapter reads it) but the bucket is not on the claude write list, so a confined worker cannot write it (a confined call exits 0 with its AI-title write refused, measured 2026-11-21 with `tests/l1-confine-real.sh --no-bucket`). An unconfined worker still can, which is why `run.sh` wipes the bucket before L1, after L1 and after L2.

### Consequences
Do not add the bucket to the write list to "fix" a refused title write: it would hand workers the shared directory. Do not drop the wipes while any engine can run unconfined. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "What the sandbox allows" and "The AI-title stub vector".

## an L1 worker writes its answer only into a private staging directory, and the runner moves it out after the engine exits (#169)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`)

### Context
An engine holds the Write tool, so it could write any path the user can: another session's `<hash>.json` and `.served`, a chunk answer between the merge and the check, a new `*.json` L2 would read, `$AUTODREAM_DIR/config`. No marker in the findings dir can tell the runner's writes from a worker's, so the access changed instead.

### Decision
- The answer is written in a stage of its own (`$L1_STAGE_ROOT/<hash>.<answer name>`), one per answer file and reused by the retries of one run, and moved to `$2` (through `$2.stage`, see the last point) once the engine has exited. The engine can then run under a sandbox that writes nowhere else. `$2` is cleared first: nothing an earlier attempt left there is this attempt's answer.
- A worker can leave a symlink where the private `tmp` goes. Unlinking follows nothing, so the runner removes it and makes the directory again, and one hostile worker cannot turn a retry into a failed night.
- An engine that keeps state it must write (omp) and runs confined gets a throwaway one inside the stage: `l1-stage-env` seeds it and names the environment that points the engine there. Exit 2 is "no such verb" (claude); any other failure is an attempt that cannot start safely. That verb's stderr goes to a file in the staging root, beside the stages and not in one, because this runs outside the sandbox and a worker that left a symlink inside its own stage on an earlier attempt would otherwise have the redirection truncate whatever the link points at.
- After the engine exits the runner is the only writer. It renames the answer to `<answer>.stage` first and only then tests it (a rename does not follow a symlink, so what is tested is the thing that was moved and nothing can be swapped in between). Only a regular, non-empty file is kept; a symlink is refused and named in the `.err`, because reading it would read whatever it points at.

### Consequences
Do not test the answer before the rename. See docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement, "A worker writes only its staging directory (#169)" and "What the sandbox allows".

## Each L1 engine call writes only its own staging dir under an OS sandbox, and the runner copies the answer out

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`, `L1_CONFINED` and related globals)

### Context
Issue #169. An L1 worker holds the Write tool, so it could write any path the user can. No marker in the findings dir can tell the runner's writes from a worker's, so the access had to change.

### Decision
Each engine call gets its own staging directory (`$AUTODREAM_DIR/staging/run-<pid>/...`), writes its answer there, and runs under an OS sandbox that can write only that directory and the narrow state paths the engine itself needs (the adapter verb `l1-writes`); the runner copies the answer into the findings dir after the engine has exited. Staging happens whether or not the sandbox does, so the copy is one code path. A host with no working sandbox runs the workers as before and says so in run-stats (`l1_confined: no`, with the reason); the probe checks that a write beside the staging directory is refused, so a tool that accepts a profile and confines nothing counts as no sandbox.

Setup details:
- A run killed mid-flight leaves its staging root behind. Only roots whose run is gone (`kill -0` fails) are removed, because the nightly and an `autodream-now` run for another date are alive at once.
- When every session already has findings, no worker starts and there is nothing to confine or prepare. Every engine is named in `L1_SETUP_SKIPPED`, so a findings file that vanishes before dispatch fails the attempt (`l1_attempt`) and does not start an unprepared worker with no sandbox.
- The protected directories (`$AUTODREAM_DIR`, `$FINDINGS_DIR`, `$DREAMS_DIR`) are joined with a colon, so one that holds a colon would be split into two paths and left unprotected, and a relative one protects nothing. Either is an `L1_CONFINE_FATAL`.

Setup sets globals and is never called inside `$(...)`.

See docs/adr/0003-adapters-and-engines.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation, "Who starts the L1 worker" (A worker writes only its staging directory (#169); What the sandbox allows; A host with no working sandbox says so).

### Consequences
Unverified: a token refresh inside the sandbox (see docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement). `tests/l1-confine-real.sh` is the manual check. The confinement tests skip where `sandbox-exec` cannot start.
