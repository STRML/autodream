# 0023: Install, scheduling and on-demand runs

Status: accepted · Governs: `bin/autodream-now.sh`, `bin/lib-install-dir.sh`, `install.sh`, `bin/session-stats.sh`, `bin/triage-candidates.sh`, `bin/threads.sh`, `portable.sh`, `lib-flock.sh` and 2 more

This record holds 35 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: The label is owned by a runner, not by a name (omp-autodream#14, issue #60)](#background-the-label-is-owned-by-a-runner-not-by-a-name-omp-autodream14-issue-60)
- [Background: The review triage LaunchAgent](#background-the-review-triage-launchagent)
- [Background: What goes in the plist PATH](#background-what-goes-in-the-plist-path)
- [Background: Rehearsing an install: `--dry-run`, `--adapters`, `--l2-engine`](#background-rehearsing-an-install---dry-run---adapters---l2-engine)
- [Background: Running / rerunning a date](#background-running--rerunning-a-date)
- [Background: Running on-demand without the 10-min cap (`autodream-now.sh`)](#background-running-on-demand-without-the-10-min-cap-autodream-nowsh)
- [autodream-now.sh derives its defaults and its date exactly as run.sh does](#autodream-nowsh-derives-its-defaults-and-its-date-exactly-as-runsh-does)
- [the one-shot copies the scheduled job's environment, never the caller's, and refuses when it cannot](#the-one-shot-copies-the-scheduled-jobs-environment-never-the-callers-and-refuses-when-it-cannot)
- [autodream-now.sh takes its install dir from the symlink's directory, not the repo's](#autodream-nowsh-takes-its-install-dir-from-the-symlinks-directory-not-the-repos)
- [the on-demand label borrows our base label and always carries an install hash](#the-on-demand-label-borrows-our-base-label-and-always-carries-an-install-hash)
- [autodream-now.sh refuses to launch while its label holds a live pid](#autodream-nowsh-refuses-to-launch-while-its-label-holds-a-live-pid)
- [RunAtLoad is the only trigger for the one-shot, with no kickstart](#runatload-is-the-only-trigger-for-the-one-shot-with-no-kickstart)
- [autodream-now.sh walks its own symlink chain by hand](#autodream-nowsh-walks-its-own-symlink-chain-by-hand)
- [--watch decides from run.sh's own outcome line keyed by this launch's token](#--watch-decides-from-runshs-own-outcome-line-keyed-by-this-launchs-token)
- [install.sh links the adapters tree whole and restores each adapter's exec bit](#installsh-links-the-adapters-tree-whole-and-restores-each-adapters-exec-bit)
- [the installer reads config values by sourcing the file, as run.sh does](#the-installer-reads-config-values-by-sourcing-the-file-as-runsh-does)
- [a dry run runs every read, replaces every write, and generates plists in a scratch directory](#a-dry-run-runs-every-read-replaces-every-write-and-generates-plists-in-a-scratch-directory)
- [PATH entries under a temp directory never reach the launchd plist](#path-entries-under-a-temp-directory-never-reach-the-launchd-plist)
- [an installed script finds a newer helper through its own symlink target](#an-installed-script-finds-a-newer-helper-through-its-own-symlink-target)
- [the schedule label comes from scheduler-label.sh, never from a name match](#the-schedule-label-comes-from-scheduler-labelsh-never-from-a-name-match)
- [install.sh never links over a missing source or a real directory, and says so](#installsh-never-links-over-a-missing-source-or-a-real-directory-and-says-so)
- [--adapters and --l2-engine write one managed config section, validated before any write](#--adapters-and---l2-engine-write-one-managed-config-section-validated-before-any-write)
- [the plist PATH carries every CLI the nightly runs, resolved config first](#the-plist-path-carries-every-cli-the-nightly-runs-resolved-config-first)
- [the review agent pins the first usable claude, config before PATH](#the-review-agent-pins-the-first-usable-claude-config-before-path)
- [the review agent passes yesterday's date, computed when the job fires](#the-review-agent-passes-yesterdays-date-computed-when-the-job-fires)
- [opting out of the review agent, or losing cmux or claude, boots out and deletes its plist](#opting-out-of-the-review-agent-or-losing-cmux-or-claude-boots-out-and-deletes-its-plist)
- [the review agent is provisioned only when cmux resolves the way review.sh resolves it](#the-review-agent-is-provisioned-only-when-cmux-resolves-the-way-reviewsh-resolves-it)
- [only the label refusal (exit 3) is survivable; every other schedule failure fails the install](#only-the-label-refusal-exit-3-is-survivable-every-other-schedule-failure-fails-the-install)
- [install decides which session roots are indexed once, and the nightly never asks](#install-decides-which-session-roots-are-indexed-once-and-the-nightly-never-asks)
- [the global /autodream skill is linked only when it cannot break the install or point at nothing](#the-global-autodream-skill-is-linked-only-when-it-cannot-break-the-install-or-point-at-nothing)
- [root-probe refuses a root path containing ':' and shell-quotes the rest](#root-probe-refuses-a-root-path-containing--and-shell-quotes-the-rest)
- [root-probe keeps a one-element empty-string sentinel when no root exists](#root-probe-keeps-a-one-element-empty-string-sentinel-when-no-root-exists)
- [an unasked Claude folder is held out of the scan until the user decides](#an-unasked-claude-folder-is-held-out-of-the-scan-until-the-user-decides)
- [scheduler-label reports a foreign holder of the default label as exit 3 and never guesses a plist](#scheduler-label-reports-a-foreign-holder-of-the-default-label-as-exit-3-and-never-guesses-a-plist)
- [a launchd plist is ours only when its ProgramArguments invoke this install's run.sh](#a-launchd-plist-is-ours-only-when-its-programarguments-invoke-this-installs-runsh)

## Background: The label is owned by a runner, not by a name (omp-autodream#14, issue #60)

This section was moved here from the former CLAUDE.md. Its original title: "The label is owned by a runner, not by a name (omp-autodream#14, issue #60)".

`bin/scheduler-label.sh` decides which launchd label an install owns, and `install.sh` and `bin/autodream-now.sh` both call it. They used to answer separately and wrong: any `*autodream*.plist` whose body mentioned `run.sh` was treated as ours, so installing a second autodream on a host with a first one adopted the first one's label and rewrote that job. Nothing failed loudly. The overwritten job's triage sat dead for 18 days, and https://github.com/STRML/cc-autodream/issues/66 is the same blackout seen from this side.

- **Ownership is the runner.** A plist is ours only when its `ProgramArguments` invoke a `run.sh` under this install's directory, compared with `pwd -P` so a trailing slash or a symlinked parent cannot cause a miss. A miss would be silent: a fresh label on every re-install.
- **Our own label wins**, even when it is not the default, so a renamed job keeps its name. Every plist in the LaunchAgents dir is read, not an `*autodream*.plist` glob: launchd keys a job by its Label, so a filename glob missed both our job renamed to `nightly.plist` and a foreign job holding the default label in `backup.plist`.
- **A conflict on the default name is refused.** `scheduler-label.sh` exits 3 and `install.sh` skips scheduling but still installs the symlinks. Any other nonzero from `install_schedule` (a plist failing `plutil -lint`, a bootstrap that did not take) fails the install.
- **The on-demand label carries a hash of the install dir** (`<label>.ondemand.<8 hex>`), because the `bootout` before each on-demand run evicts whatever holds the label and another install's on-demand plist lives in its own `AUTODREAM_DIR`, where no scan sees it.
- **The shipped template must be adoptable by this check.** It used `bash -lc "$HOME/.../run.sh"`, which runs but whose literal string never matches an install dir, so a job installed from the template got a second one beside it on the next `./install.sh`.

The default label is `com.<user>.autodream`; the review LaunchAgent takes `<label>-review` (see "The review triage LaunchAgent" below).

## Background: The review triage LaunchAgent

This section was moved here from the former CLAUDE.md. Its original title: "The review triage LaunchAgent".

`install.sh` provisions a second agent, `<nightly label>-review`, next to the nightly one: it runs `review.sh <yesterday>` at 08:00, 09:15, 12:15, 15:30 and 18:15 with `AUTODREAM_TRIAGE_SURFACE=cmux`, and review.sh's launch marker keeps it to one workspace per report. The date is a `$(date -v-1d ...)` evaluated at fire time (the installer refuses to write the plist if that expression was frozen). cmux and claude are resolved the way review.sh resolves them (config, then PATH, then `AUTODREAM_CMUX_DEFAULT` or the app bundle path) and pinned absolutely in the agent's environment; with either missing the agent is skipped and a previously provisioned one is booted out, so a machine that lost cmux does not keep firing a failing trigger. A refused nightly schedule provisions no review agent. `--no-review` (this run) or `AUTODREAM_REVIEW_AGENT=0` (environment, then config, so it survives a re-install) opts out the same way: the agent is not provisioned and a loaded one is booted out and its plist removed. `tests/install-review-agent.sh` drives the real installer against a sandbox HOME with a shimmed `launchctl`; `tests/install-path.sh` covers the opt-out and the plist PATH below.

## Background: What goes in the plist PATH

This section was moved here from the former CLAUDE.md. Its original title: "What goes in the plist PATH".

launchd has no login shell and the job runs with only the PATH install writes, so a CLI the job needs has to be reachable from it. `install.sh` resolves `claude`, `git`, `bash`, the `engine_bin` of every enabled adapter (`--adapters`, else `AUTODREAM_ADAPTERS` from the config) and the L2 engine's (`--l2-engine`, else `AUTODREAM_L2_ENGINE`; a host can scan claude and run L2 on omp) and puts their directories first. The config is read by sourcing it, as `run.sh` does, so `export KEY=value` and quotes read the same. An adapter's `<NAME>_BIN` from the config wins over the PATH lookup, so `omp` under `~/.bun/bin` is reachable without being on the installer's PATH; one only in the installer's environment does not count, because launchd will not carry it and the adapter would then look for the bare engine name on PATH. Two things here were learned on a real host:

- **A shell's temp PATH entries must not be baked in.** cmux puts `$TMPDIR/cmux-cli-shims/<uuid>` first on PATH in every terminal it opens, and the installer used to copy that directory, and the shim `claude` in it, into both plists. They are gone after the session. `ephemeral_dir` drops any PATH entry under `$TMPDIR`, `/tmp` or `/var/folders` before the tools are resolved, and says so. `AUTODREAM_EPHEMERAL_DIRS` replaces the prefix list; set but empty, it turns the check off, which the install suites need because every fake tool they make lives under `$TMPDIR`. A DEV cmux build under `DerivedData` is not ephemeral and is left alone.
- **omp is not on the usual PATH.** A bun install puts it in `~/.bun/bin`, which no default PATH carries. Without the adapter's directory in the plist the omp worker cannot start and the night's omp sessions are lost without an error (`FATAL: omp not found` in the run log, no report from that source).

The PATH is fixed when the plist is written, so enabling an adapter afterwards by editing the config needs a re-install, or `<NAME>_BIN` in the config (read by `run.sh` at run time, independent of the plist). `--no-review` stops where a refused label stops: the review label is `<our label>-review`, and on a refused label that is another install's agent, which this installer must not boot out or remove (`tests/install-path.sh` pins it).

## Background: Rehearsing an install: `--dry-run`, `--adapters`, `--l2-engine`

This section was moved here from the former CLAUDE.md. Its original title: "Rehearsing an install: `--dry-run`, `--adapters`, `--l2-engine`".

`install.sh --dry-run` runs the same code with every write replaced by a `[dry-run]` line: the links, the config sections, the plists (generated and `plutil`-linted in a scratch directory, then shown with the path they would be written to) and each `launchctl` call. What only reads still runs, so a dry run reports the refusal a real install would hit (a foreign job holding the label, a non-empty real directory where a link goes) and still exits 0 for the survivable one. `tests/install-dry-run.sh` asserts the sandbox tree is identical afterwards and that `launchctl` was never invoked. `--adapters <names|all>` and `--l2-engine <name>` write one managed `# adapters (managed by install.sh)` section into the config, replaced in place on re-install and left alone when the flags are absent; both are validated against `adapters/` before anything is written (exit 64). run.sh sources the config with the caller's environment winning, so an exported variable still beats it.

## Background: Running / rerunning a date

This section was moved here from the former CLAUDE.md. Its original title: "Running / rerunning a date".

```
~/.claude/autodream/run.sh 2026-05-29        # process a date
AUTODREAM_FORCE=1 ~/.claude/autodream/run.sh 2026-05-29   # rebuild despite an existing report
```
To reprocess cleanly (e.g. after the corpus changed), delete that date's findings dir AND report first, then run; otherwise idempotency reuses old findings and the guard skips. Env knobs are documented in `docs/run-knobs.md` and the README.

## Background: Running on-demand without the 10-min cap (`autodream-now.sh`)

This section was moved here from the former CLAUDE.md. Its original title: "Running on-demand without the 10-min cap (`autodream-now.sh`)".

A full run routinely exceeds 10 minutes, so launching `run.sh` from a foreground/background context that has a time cap (a Claude Code background Bash task, an ssh session that may drop) gets it killed mid-flight. `bin/autodream-now.sh` sidesteps this by handing the run to **launchd**, which owns the process — no time cap, survives the caller disconnecting.

```
~/.claude/autodream/autodream-now.sh                  # yesterday, now
~/.claude/autodream/autodream-now.sh 2026-05-29 --force   # specific date, rebuild
~/.claude/autodream/autodream-now.sh 2026-05-29 --watch   # tail this run's log; exit 0 on a complete report, 1 if the run ends without one
~/.claude/autodream/autodream-now.sh 2026-05-29 --dry-run # print plist + commands, run nothing
```

How it works: it writes a transient one-shot LaunchAgent (`<base-label>.ondemand`, `RunAtLoad`) into `$AUTODREAM_DIR`, `bootout`s any prior instance, then `bootstrap`s it so launchd runs `run.sh <date>` once and the job exits. `RunAtLoad` is the *only* trigger — it deliberately does not also `kickstart`, or a fast run (e.g. the idempotency no-op) would fire twice. It never touches the scheduled nightly job. Everything is auto-detected: it resolves its own symlink to find `run.sh`, picks the scheduled plist whose `ProgramArguments` reference `run.sh` (not the sibling `*-review` job) to borrow its label namespace, and detects uid + the `claude`/`git` dirs for the agent's PATH — so it is not specific to one user or host. It refuses to launch while the label holds a live pid (`launchctl print` shows `pid =`): every on-demand run shares the one label, so the `bootout` would kill the in-flight run (#78). Wait for it, or `launchctl bootout` it yourself. The default date is computed with plain `date -v-1d`, exactly like run.sh (no TZ override). `--force` maps to `AUTODREAM_FORCE=1`; the caller's `AUTODREAM_DIR`/`DREAMS_DIR` are passed through. Every other variable comes from the scheduled job's own `EnvironmentVariables` (`scheduler-label.sh --plist` finds the job this install owns), never from the caller's shell: a host whose nightly runs on a non-default Claude profile sets `CLAUDE_CONFIG_DIR` there, and a one-shot built from PATH alone ran the CLI logged out, so every L2 attempt wrote "Not logged in". The caller's shell is skipped on purpose, because a terminal inside another Claude profile would bill that login. The plist is written mode 600, since it now carries that environment. `--watch` judges the report with `report_finishes()` and only for a file this run wrote, and stops when launchd shows the job ran and holds no process; the old `-s` test said "ready" for the degraded capture run.sh keeps between L2 attempts. Progress is in `$AUTODREAM_DIR/logs/run-<date>.log`; the agent's own stdout/stderr go to `logs/ondemand.{out,err}.log`.

When you (the agent) need to kick off a run, prefer this over a background Bash task — fire it, then poll `dreams/<date>.md` instead of holding a long task open. A non-empty file is not a finished one: check for the `autodream:open-questions=` marker (`report_finishes`), and while a run is going even that is not enough, because between L2 attempts `run.sh` keeps a capture with the marker and the questions block but no `AUTODREAM_REPORT_END` sentinel at the report path (a killed run leaves it there). `--watch` therefore asks the runner instead of inferring: `autodream-now.sh` puts a per-launch `AUTODREAM_RUN_TOKEN` in the one-shot plist, `run.sh` appends `<token> delivered` (a validated report, the no-sessions stub included) or `<token> noop` (the idempotency guard left a finished report alone) to `logs/run-<date>.outcome`, and `--watch` exits 0 on one of those and 1 when the job has finished without one. A log line, a report's mtime (whole seconds) and a completeness predicate evaluated in the watcher (another questions epoch; the runner also accepts a legacy report with no marker) were each tried and each gave a wrong answer. The one-shot copies the scheduled job's `EnvironmentVariables` and refuses to launch (exit 65) when it cannot read them, because launching without them is the logged-out run this exists to prevent; values keep their trailing newlines, and `jq` is looked up on the job's own PATH first.

## autodream-now.sh derives its defaults and its date exactly as run.sh does

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`DREAMS_DIR`, `TARGET`)

### Context

`--watch` and the generated plist have to point where `run.sh` writes, and the one-shot has to process the same day `run.sh` would pick for "yesterday". Two scripts with separate defaults can silently disagree, as the install-dir copies did (#112).

### Decision

`DREAMS_DIR` defaults to `$HOME/.claude/dreams`, the default `run.sh` uses, and the same env overrides are honored so a customized install (different `AUTODREAM_DIR` or `DREAMS_DIR`) still works. With no date argument, `TARGET` comes from `pdate_yesterday`: plain system-local BSD date, no `TZ` override, so it cannot disagree with `run.sh` about which day yesterday is.

### Consequences

A new default or a changed date rule in `run.sh` needs the same change here. Adding a `TZ` override on either side would shift "yesterday" for one of them.

## the one-shot copies the scheduled job's environment, never the caller's, and refuses when it cannot

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`xml_escape_into`, the `SCHED_PLIST` block, the plist write)

### Context

A login setting lives in the scheduled job's `EnvironmentVariables`: a host whose nightly runs on a non-default Claude profile sets `CLAUDE_CONFIG_DIR` there. A one-shot plist built from `PATH` alone ran the CLI on the default profile; with no login there, every L2 attempt wrote "Not logged in · Please run /login" and the date stayed unassembled.

### Decision

- The environment is the scheduled job's, minus the keys the script sets itself (`PATH`, `AUTODREAM_DIR`, `DREAMS_DIR`, `AUTODREAM_FORCE`, `AUTODREAM_RUN_TOKEN`). The caller's shell environment is deliberately not copied: a terminal inside another Claude profile would run the job under that login.
- `scheduler-label.sh --plist` applies the same ownership rule the label uses, so a plist that merely shares the label is never read. No scheduled job means nothing is inherited.
- A scheduled job whose environment cannot be read (no `plutil`, no `jq` on the job's own `PATH` or the caller's, a plist that will not convert, a failing `jq`) refuses the launch with exit 65: copying nothing would start the run logged out again. A key the plist does not have is an empty environment, not a failure.
- `jq` is looked up on the job's own `PATH` first, because the caller's `PATH` may lack `/opt/homebrew/bin`. `AUTODREAM_JQ_BIN` names the `jq` to use; the tests point it at a failing one.
- The pairs travel NUL-separated, so no value can be split or unescaped on the way through. `xml_escape_into` keeps trailing newlines: a command substitution would strip them, so the text carries a sentinel `x` through `sed`.
- The plist is written with `umask 077`, because the body now carries an environment that can hold more than paths. launchd only refuses group- or world-writable agent plists, so mode 600 loads.

### Consequences

docs/adr/0023-install-and-scheduling.md#background-running-on-demand-without-the-10-min-cap-autodream-nowsh, "Running on-demand without the 10-min cap", describes the same behavior from the outside. `tests/autodream-now.sh` pins the refusal and the copy. Do not simplify the escaper to `$(...)`, and do not source the caller's environment to save the plist read.

## autodream-now.sh takes its install dir from the symlink's directory, not the repo's

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`resolve_install_dir` call), `bin/lib-install-dir.sh`

### Context

`scheduler-label.sh` decides ownership by comparing a plist's runner dir against the install dir. A hardcoded default never matched a custom-path install (`./install.sh /custom`), so the `.ondemand` label silently left that install's namespace.

### Decision

The script resolves the install dir with `resolve_install_dir "${BASH_SOURCE[0]}"`, the same idiom as its siblings. `BASH_SOURCE` is left unresolved on purpose: the symlink's own directory is the install dir, while `BIN_DIR` (resolved through the symlink chain) points at the repo.

### Consequences

Do not pass `SELF` or `BIN_DIR` to the resolver: they name the repo, which carries no install marker. See `docs/adr/0001-runner-lifecycle.md#one-resolver-decides-the-install-dir-from-the-scripts-unresolved-path` for the resolution order.

## the on-demand label borrows our base label and always carries an install hash

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`BASE_LABEL`, `INSTALL_REAL`, `LABEL`)

### Context

The transient label should sit in the same namespace as this install's scheduled job. `scheduler-label.sh` owns that decision for `install.sh` too, and it will not hand back a label belonging to another autodream install. The `bootout` before each run evicts whatever holds the on-demand label, and another install's on-demand plist lives in its own `AUTODREAM_DIR`, where no scan can see it. Two installs share a base label whenever one holds the default or neither has a scheduled job, so no check on the base label can rule the collision out.

### Decision

`BASE_LABEL` comes from `scheduler-label.sh`. A conflict on the default name is not fatal here, because the script only borrows the namespace. The on-demand label is `<base>.ondemand.<8 hex of a sha1 of the resolved install dir>`, always. `pwd -P` keeps the hash the same for a trailing slash or a symlinked path, so `bootout` still finds this install's prior run.

### Consequences

The label's hash must be computed from `pwd -P`, or `bootout` misses the prior run. docs/adr/0023-install-and-scheduling.md#background-the-label-is-owned-by-a-runner-not-by-a-name-omp-autodream14-issue-60, "The label is owned by a runner, not by a name", has the incident that shaped `scheduler-label.sh`.

## autodream-now.sh refuses to launch while its label holds a live pid

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (the `launchctl print` block before the plist write)

### Context

Every on-demand run for an install shares one label, and the `bootout` that precedes a launch kills the process behind it. Launching a second date while the first was still running evicted the first mid-run, with no report and no error (#78).

### Decision

Before the plist is rewritten, `launchctl print` is captured and parsed for `pid = N`. A loaded job with a live pid is in flight: the script prints the date that holds the label and exits 75. A loaded job with no pid has finished and is safe to boot out. A failed `print` means the label is not loaded, so there is nothing to protect. The check runs before the plist is rewritten because the holder's date is read back out of the old plist. The output is captured first and parsed afterwards, because a pipeline under `pipefail` could lose a pid it had read.

### Consequences

Moving the check below the plist write loses the holder's date. A user who really wants to replace the run stops it first with the `launchctl bootout` command the message names.

## RunAtLoad is the only trigger for the one-shot, with no kickstart

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (the `launchctl bootout` and `bootstrap` calls)

### Context

The script boots out any finished instance of its label and then bootstraps the one-shot plist, whose `RunAtLoad` starts `run.sh`.

### Decision

`RunAtLoad` is the only trigger, so the run fires exactly once. The script does not also `launchctl kickstart`: a fast run (the idempotency no-op, for instance) would execute twice.

### Consequences

docs/adr/0023-install-and-scheduling.md#background-running-on-demand-without-the-10-min-cap-autodream-nowsh, "Running on-demand without the 10-min cap", says the same. Adding a kickstart "to be sure" duplicates runs.

## autodream-now.sh walks its own symlink chain by hand

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`resolve`)

### Context

macOS has no `readlink -f`. `install.sh` symlinks this helper into `$AUTODREAM_DIR`, so the script has to resolve through the link to find the real `bin/` and the `run.sh` beside it.

### Decision

`resolve` follows `readlink` one hop at a time until the path is no longer a symlink, joining a relative target to the link's directory.

### Consequences

Replacing it with `readlink -f` works on Linux and breaks on macOS, where this script runs.

## --watch decides from run.sh's own outcome line keyed by this launch's token

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`RUN_TOKEN`, `job_finished`, `outcome_of_this_run`, `exit_on_outcome`, `LOG_START`)

### Context

Did this run deliver, and is the run over, are two separate questions. Inferring the first from the filesystem was wrong every way it was tried:

- a report file that looks complete: `run.sh` keeps a marker-bearing capture with no `AUTODREAM_REPORT_END` sentinel at the report path between L2 attempts, and a killed run leaves it there;
- the file's mtime: it is a whole second, so a report written in the launch second reads as new;
- a log line: the log also holds model text;
- a completeness predicate evaluated in the watcher: another config's questions epoch applies, and the runner accepts a legacy report before that epoch that has no marker.

A watcher that only waited for delivery watched a run whose every attempt failed for the full 90 minutes.

### Decision

Each launch gets `RUN_TOKEN` (`<epoch>.<pid>.<random>`), passed in the plist. `run.sh` appends `<token> delivered` or `<token> noop` to `logs/run-<date>.outcome`, and `--watch` reads that and nothing else, so an earlier run's line is never read as this one's.

The run is over when launchd shows no pid and `runs` is at least 1 (`runs = 0` means not started yet). An unloaded label means there is nothing to wait for. After the job finishes the outcome is read once more, because the line can land just before the job exits.

The log for a date accumulates every earlier attempt's lines, so `LOG_START` is the log size taken before `bootstrap`, and the tail starts after it.

### Consequences

docs/adr/0023-install-and-scheduling.md#background-running-on-demand-without-the-10-min-cap-autodream-nowsh, "Running on-demand without the 10-min cap", says the same. `tests/autodream-now.sh` covers the verdicts. A new way of ending a run has to write an outcome line, or `--watch` reports the run as ended without delivering.

## install.sh links the adapters tree whole and restores each adapter's exec bit

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the `adapters` link and the `chmod +x`)

### Context

`run.sh` resolves `adapters/<name>/adapter.sh` relative to its own directory, so the whole tree has to be reachable from the install target. Without the link the installed runner silently takes the legacy inline enumeration path, gets no preflight, and still reports `adapters_enabled`.

`_adapter_ok` requires `-x` on `adapter.sh`, and the loader treats a non-executable adapter as a refusal, not as "adapters absent". A distribution path that loses the exec bit (a zip, a restrictive umask) therefore becomes a hard FATAL nightly with no report.

### Decision

The installer links the directory `adapters/`, not individual files, and runs `chmod +x adapters/*/adapter.sh` next to the `bin/*.sh` chmod.

### Consequences

A new per-adapter file needs no installer change. A new adapter entry point that must be executable needs its own chmod here.

## the installer reads config values by sourcing the file, as run.sh does

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`cfg_get`)

### Context

The plist and the review agent depend on values like `CMUX_BIN`, `CLAUDE_BIN`, `AUTODREAM_REVIEW_AGENT` and `<NAME>_BIN`. `review.sh` and `run.sh` read them by sourcing the config as Bash. A sed or raw read would take literal quote characters from `CMUX_BIN="$HOME/bin/cmux"`, fail the `-x` test, and wrongly skip (and unload) the review agent for a perfectly valid config.

### Decision

`cfg_get VAR` sources the config in a throwaway `bash -c` with `AUTODREAM_DIR` set to the target and the variable unset first, so `export KEY=value`, quotes, `$HOME`, `~` and later assignments all resolve as at run time. A caller strips any stray double quotes that survive.

### Consequences

Cost: one subshell per read. A value only in the installer's environment is not read here on purpose (launchd will not carry it).

## a dry run runs every read, replaces every write, and generates plists in a scratch directory

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`dry`, `DRY_SCRATCH`, `show_plist`, `lctl`)

### Context

A rehearsal that skips the checks proves nothing. docs/adr/0023-install-and-scheduling.md#background-rehearsing-an-install---dry-run---adapters---l2-engine, "Rehearsing an install", has the contract and the test (`tests/install-dry-run.sh`).

### Decision

With `--dry-run` the same code path runs. Every write becomes a `[dry-run]` line. Anything that only reads (the label ownership check, the cmux and claude lookups, the validations in `link`) still runs, so the dry run reports the refusals a real install would hit. The plists are generated and `plutil`-linted in one scratch directory under `TMPDIR`, removed on every exit path, so the dry run shows exactly what would be written without touching the real LaunchAgents directory. The ownership check still reads the real one.

### Consequences

A new write in the installer must go through `dry`, `lctl` or the scratch directory, or the "tree is identical afterward" test fails.

## PATH entries under a temp directory never reach the launchd plist

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`ephemeral_dir`, `install_schedule`)

### Context

A directory under a temp location belongs to the shell that ran the installer: a tool shim (cmux puts `$TMPDIR/cmux-cli-shims/<uuid>` first on PATH in every terminal it opens) or a per-session scratch dir. It is gone by the time launchd runs the job, so a PATH entry or a `CLAUDE_BIN` taken from one rots the schedule with no error. docs/adr/0023-install-and-scheduling.md#background-what-goes-in-the-plist-path, "What goes in the plist PATH", records the incident on a real host.

### Decision

`ephemeral_dir` matches a directory against a prefix list (`$TMPDIR`, `/tmp`, `/private/tmp`, `/var/folders`, `/private/var/folders`), comparing physical paths. `install_schedule` drops matching entries from `PATH` first and resolves every tool against what is left, naming what it skipped. `AUTODREAM_EPHEMERAL_DIRS` replaces the list; set but empty it turns the check off, which the install test suites need because their fake tools live under `TMPDIR`. A development build under `DerivedData` is not ephemeral.

### Consequences

Any new place the installer takes a binary path from must go through the same check (`config_bin_dir` does).

## an installed script finds a newer helper through its own symlink target

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh`, `bin/triage-candidates.sh`, `bin/threads.sh` (the `portable.sh` and `lib-flock.sh` sourcing)

### Context

`install.sh` symlinks each script into `~/.claude/autodream/`. Updating the checkout updates every installed script at once, but a helper added by the update (`lib-flock.sh`, `portable.sh`) has no link until `install.sh` runs again. The nightly must not stop in between. docs/adr/0001-runner-lifecycle.md#background-which-code-actually-ran-runner_commit, "Which code actually ran", describes the same exposure.

### Decision

Each script first looks for the helper beside itself. If it is missing, it resolves its own symlink and looks beside the target (the checkout).

### Consequences

A new helper needs a link in `install.sh` for the normal case. This fallback only covers the window between a merge and the next install.

## the schedule label comes from scheduler-label.sh, never from a name match

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`), `bin/scheduler-label.sh`

### Context

Matching a plist on the string `run.sh` alone took over another install's job and left it dead for 18 days (omp-autodream#14, https://github.com/STRML/cc-autodream/issues/60). docs/adr/0023-install-and-scheduling.md#background-the-label-is-owned-by-a-runner-not-by-a-name-omp-autodream14-issue-60, "The label is owned by a runner, not by a name", is the full record.

### Decision

`install_schedule` asks `bin/scheduler-label.sh` for the label. It reuses this install's own prior label (so a re-install is idempotent), never adopts a plist that runs someone else's `run.sh`, and exits 3 rather than overwrite a foreign job holding the default name. The installer returns that code unchanged.

### Consequences

See `bin-b-install-schedule-exit-codes` for what the caller does with exit 3.

## install.sh never links over a missing source or a real directory, and says so

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`link`)

### Context

- A link to a file the checked-out tree does not have looks installed and does nothing at 03:15. That is the overlap-stats.sh dangle of 2026-07-24, which cost a night of data.
- `adapters/` was the first directory the installer links. With a real directory at the destination, `ln -s` silently creates `$dst/<basename>` (a nested `adapters/adapters`) and prints the same success line. The loader then finds an empty directory, rejects the nested link on containment, and every nightly run fails.
- Warning and returning 0 on that case reported a successful install while `adapters_root()` pointed at a directory the loader accepts nothing from: the "loader accepted no adapters" fatal on every nightly afterward, a total outage behind one line of output.

### Decision

- A missing source is a loud warning, the old link is left alone, and `link` returns 0 (one stale helper must not abort the rest of the install).
- A non-empty real directory at the destination, or one that cannot be removed, is a hard failure (`return 1`). An empty one is removed and linked. The dry run applies the same non-empty check, so it reports the refusal a real install would hit.

### Consequences

Adding a directory link means it inherits this refusal. Do not downgrade the directory case to a warning to make an install "succeed": the failure moves to 03:15.

## --adapters and --l2-engine write one managed config section, validated before any write

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`valid_adapter`, the adapters and L2 engine block)

### Context

docs/adr/0023-install-and-scheduling.md#background-rehearsing-an-install---dry-run---adapters---l2-engine, "Rehearsing an install", describes the flags. Two failure modes shaped them:

- A typo written into the config makes the nightly enable nothing and refuse to scan, so every name is checked against `adapters/` (and a safe character set) before anything is written, exit 64.
- Re-running with one flag must not drop the host's other choice, and `run.sh` sources the config with the caller's exported variables winning, so the section never overrides a caller.

### Decision

The section is replaced in place (strip from the marker through its keys, append anew), so a re-install converges. An absent flag leaves the section alone, and when only one flag is given the other key keeps its present value, read back from the config.

### Consequences

The marker text `# adapters (managed by install.sh)` is matched by the strip awk. A new key in this section must be added to that awk's key list.

## the plist PATH carries every CLI the nightly runs, resolved config first

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`adapter_bin_dirs`, `adapter_bin_dirs_one`, `x_browser_bin_dirs`, `config_bin_dir`, `install_schedule`)

### Context

launchd has no login shell, so a CLI outside the usual directories is unreachable unless its directory is in the plist PATH (omp under `~/.bun/bin` is the real case; without it the omp worker cannot start and the night's omp sessions vanish with only a FATAL in the run log). `agent-browser` is a node script (`#!/usr/bin/env node`), so launchd needs the directory of `node` too. docs/adr/0023-install-and-scheduling.md#background-what-goes-in-the-plist-path, "What goes in the plist PATH", has the history.

### Decision

- The PATH is seeded with the directories of `claude`, `git`, `bash` and `rsync`, then the engine of every enabled adapter and of the L2 engine, then (with `AUTODREAM_X_FETCH=browser`) `agent-browser` and `node`, then the usual system directories.
- `<NAME>_BIN` or `X_BROWSER_BIN` from the config wins when it names an absolute, executable, non-temp file, as the adapters resolve it at run time. The installer's own environment does not count.
- An adapter name reaches an indirect expansion, so it must match the character set `--adapters` enforces; a hand-edited config cannot put anything else there.
- `claude`'s resolved path is remembered as `CLAUDE_BIN_ABS` for the review agent (see `bin-b-install-review-claude-bin`).

### Consequences

The PATH is fixed when the plist is written, so enabling an adapter afterward needs a re-install (or `<NAME>_BIN` in the config).

## the review agent pins the first usable claude, config before PATH

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`, `CLAUDE_BIN_ABS`, `eff_claude`)

### Context

`review.sh` preflights the exact binary path and aborts when `CLAUDE_BIN` is not executable. Its default, `$HOME/.local/bin/claude`, is wrong when claude lives elsewhere, so the installer must pass the real one. A config value is the user's explicit choice (a wrapper or custom claude) and `review.sh` restores env over config at run time, so the plist must not override it. A directory passes `-x` but `exec <dir>` fails at once and leaves a dead workspace (auditor 7.2 and 7.3).

### Decision

Candidates are tried in order: config `CLAUDE_BIN`, then the `claude` found on the cleaned PATH (`CLAUDE_BIN_ABS`). The first that is a regular file and executable wins. A config value that points at nothing therefore does not disable the agent while a working claude is on PATH. No usable candidate means the agent is skipped with a message.

### Consequences

The same `-f` and `-x` test applies to any new binary pinned in the plist.

## the review agent passes yesterday's date, computed when the job fires

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the review plist in `install_schedule`)

### Context

`review.sh` with no date picks the newest report. At 08:00 that is not necessarily yesterday's: a still-running overnight report makes the job triage an older one. docs/adr/0023-install-and-scheduling.md#background-the-review-triage-launchagent, "The review triage LaunchAgent", describes the agent.

### Decision

- The plist runs `/bin/bash -c 'exec "$1" "$(date -v-1d +%Y-%m-%d)"' triage <review.sh>`. The `$(...)` and `$1` are escaped in the installer's heredoc so the plist bakes the expression, not a frozen date. `review.sh` then fails fast with "no autodream report found" when yesterday's report has not landed, which is better than silently triaging the wrong day.
- After writing the plist the installer greps for both literal strings (`$(date -v-1d +%Y-%m-%d)` and `exec "$1"`) and aborts if either is missing. If the escaping ever regresses and one expression is pre-expanded, the install fails loudly instead of provisioning a job with the wrong path or date.

### Consequences

Editing the heredoc's quoting means keeping those two greps true.

## opting out of the review agent, or losing cmux or claude, boots out and deletes its plist

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`, `review_off`)

### Context

`--no-review` is per run, like `--no-schedule`. `AUTODREAM_REVIEW_AGENT=0` (environment or config) is what makes the choice survive re-installs, which would otherwise provision the agent again. A machine that had cmux or claude at install time and lost one would keep a stale scheduled job firing a failing trigger forever. Booting the job out is not enough: launchd loads every plist in LaunchAgents at login, so a plist left on disk brings the failing job back at the next login.

### Decision

When the agent is opted out or cannot be provisioned, the installer boots out `<label>-review` and removes its plist (in a dry run, it prints the removal instead). Opt-out values are `0`, `no`, `off`, `false`, in lower or upper case.

### Consequences

docs/adr/0023-install-and-scheduling.md#background-the-review-triage-launchagent, "The review triage LaunchAgent", and `tests/install-review-agent.sh` pin the behavior. A refused label never reaches this code, so another install's review agent is not touched.

## the review agent is provisioned only when cmux resolves the way review.sh resolves it

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`, the `CMUX_FOUND` lookup)

### Context

The review job exists to open a popup in its own cmux workspace. Without cmux a headless inline fallback would run claude with no terminal. macOS GUI installs usually put cmux at `/Applications/cmux.app/Contents/Resources/bin/cmux`, not on PATH, so a PATH-only check would wrongly skip the agent. The launchd PATH is fixed, so a non-default cmux (for example `~/bin/cmux`) would pass the install check and then be unfindable at run time.

### Decision

Resolve in `review.sh`'s order: config `CMUX_BIN` (if executable), then PATH (minus temp entries), then `AUTODREAM_CMUX_DEFAULT` or the app-bundle path. The resolved absolute path is written into the plist as `CMUX_BIN`. A relative path is refused: launchd runs with no working directory, so a relative value that passed `-x` here would fail every trigger. No cmux means the agent is skipped.

### Consequences

If `review.sh` changes how it finds cmux, change this lookup in step. `tests/install-review-agent.sh` pins the order.

## only the label refusal (exit 3) is survivable; every other schedule failure fails the install

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule` and its caller)

### Context

A foreign job holding our label leaves the symlinks installed and the run still works by hand, so the install can finish. Any other failure (a plist failing `plutil -lint`, a bootstrap that did not take) would print "everything is in place" over a silently broken schedule, the state that went unnoticed for 18 days (see `bin-b-install-label-ownership`).

The caller runs `install_schedule || schedule_rc=$?`, and that form disables `set -e` for the whole function body. A bootstrap failure left to errexit would therefore print `scheduled:` over a job that was never bootstrapped.

### Decision

- Inside `install_schedule` the `launchctl bootstrap` result is checked explicitly and returns 1 on failure; the `bootout` before it is `|| true` (RunAtLoad is false, so bootstrap arms the schedule without firing a run).
- The caller treats exit 3 as "schedule not installed, everything else in place" and any other non-zero as a hard failure with that exit code.

### Consequences

New steps inside `install_schedule` need their own `|| return` guards; errexit does not protect them.

## install decides which session roots are indexed once, and the nightly never asks

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the session-roots block)

### Context

autodream scans every `$HOME/.claude*/projects` that has a session store. The nightly run is unattended, so it cannot ask which folders to index. docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, "Session roots: one dir is not the corpus", records the blackout this prevents and the semantics of an unasked folder.

### Decision

- At install time `root-probe.sh` records each folder's decision in `root-choices.conf`: `--ask` on a TTY, `--default-index` otherwise (CI, an automated shell), so a non-interactive install silently covers everything and the log line says what was chosen.
- The `SESSION_ROOTS` line is a managed section of `config` that `run.sh` sources. The install removes the old section (the marker line and any `SESSION_ROOTS=` lines under it) before writing the new one, so a re-install converges instead of stacking definitions.

### Consequences

See docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus for why an unasked folder is held out of the report. Changing the marker text means changing the awk that strips it.

## the global /autodream skill is linked only when it cannot break the install or point at nothing

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the `SKILL` block)

### Context

A skill nobody asked for must not fail the install. Claude Code reads `~/.claude/skills`, and the skill calls the scripts at `~/.claude/autodream` unless `AUTODREAM_DIR` says otherwise. The user may already own an `/autodream` skill.

### Decision

- A custom install directory links the skill only when `AUTODREAM_SKILLS_DIR` says where the user wants it, because a skill linked from a custom target cannot find the scripts. Otherwise the installer prints how to opt in.
- A link or directory already at the skill's place is the user's: only an earlier link to this repo's skill is replaced. Anything else is reported to stderr and left, and a failed link is a warning, not an install failure.

### Consequences

`tests/install-skill.sh` pins each branch. A new skill link should follow the same "not ours, leave it" rule.

## root-probe refuses a root path containing ':' and shell-quotes the rest

Status: accepted · Date: 2026-11-21 · Code: `bin/root-probe.sh` (`consolidated_roots`, `--write-config`)

### Context

`SESSION_ROOTS` is colon-separated, and the scan side (`scan_roots` in `run.sh`) splits on `:` after the config has been sourced. `$AUTODREAM_DIR/config` is sourced by bash, so a root with spaces or shell metacharacters changes meaning unless quoted.

### Decision

- `consolidated_roots` skips any root containing `:` and says so on stderr, because the scan would split it into two paths.
- `--write-config` writes `SESSION_ROOTS=` through `printf '%q'`, so the sourced value is the exact joined list. The colon limit survives that quoting: `%q` protects the shell read, not the later split on `:`.

### Consequences

A profile directory with a colon in its path is never indexed, and the only trace is the stderr line. Supporting it needs a different separator on the scan side, which every `SESSION_ROOTS` consumer would have to change together.

## root-probe keeps a one-element empty-string sentinel when no root exists

Status: accepted · Date: 2026-11-21 · Code: `bin/root-probe.sh` (`roots=("")`, the `[ -n "$r" ] || continue` guards)

### Context

macOS ships bash 3.2. Under `set -u` there, `"${roots[@]}"` on an empty array is an unbound-variable error, and a host with no `$HOME/.claude*/projects` at all has an empty `roots`.

### Decision

After discovery, an empty `roots` becomes `("")`. Every loop over `roots` skips the empty entry with `[ -n "$r" ] || continue`, so every expansion is safe and the empty entry never reaches output.

### Consequences

A new loop over `roots` needs the same `-n` guard. Replacing the sentinel with an `${roots[@]+...}` expansion at each loop is possible but touches every site, and a missed one only fails on bash 3.2 with no roots.

## an unasked Claude folder is held out of the scan until the user decides

Status: accepted · Date: 2026-11-21 · Code: `bin/root-probe.sh` (`choice`, `--consolidated`, `--unindexed`, the `WRITE` block)

### Context

autodream used to scan only `$HOME/.claude/projects`. Sessions recorded under another profile's bucket (`~/.claude-nous`, `~/.claude-ds4`, ...) were invisible to the nightly report, and the triage count fell from 132 to 1 sessions a night over 2026-08-03..06 with no error. docs/adr/0002-session-enumeration.md#background-session-roots-one-dir-is-not-the-corpus, "Session roots: one dir is not the corpus", records the fix and its semantics.

### Decision

- Each folder is `index`, `ignore` or `unasked`. The primary `$HOME/.claude/projects` is always `index` and always scanned. Everything else takes its state from `root-choices.conf`, and a folder with no line is `unasked`.
- Only `--ask` and `--default-index` write choices. The nightly run passes neither, so it never writes. An `unasked` folder stays out of `--consolidated` and shows in `--unindexed`, which feeds the "found a folder we're not indexing" line in the report. Scanning it would make that flag a lie.
- `--ask` on a TTY prompts per folder. Without a TTY, and under `--default-index`, every unasked folder becomes `index` (logged to stderr), so a fresh install covers everything silently.
- `--consolidated` lists the primary first, then the other `index` folders.

### Consequences

Editing or deleting a line in `root-choices.conf` is how a user changes a choice. Writing choices from the nightly path would silence the flag it exists to raise.

## scheduler-label reports a foreign holder of the default label as exit 3 and never guesses a plist

Status: accepted · Date: 2026-11-21 · Code: `bin/scheduler-label.sh` (conflict branch, `--plist` mode)

### Context

Two callers read this script and need different things. `install.sh` writes the plist and must not overwrite another install's job. `autodream-now.sh` only borrows the label as a namespace and always adds a per-install hash. Both use the same ownership rule (see `docs/adr/0023-install-and-scheduling.md#a-launchd-plist-is-ours-only-when-its-programarguments-invoke-this-installs-runsh`).

### Decision

- Label mode prints the base label on every path, a conflict included. The `-review` and `.ondemand` siblings suffix it.
- Exit 3 means a plist running a different install holds the default label. stdout still carries the label. A caller that would write the plist aborts on it. autodream-now ignores the status.
- `--plist` prints the path of the scheduled plist this install owns, and exits 1 when there is none. autodream-now reads the job's environment from that file, so "none" must never fall back to a plist that only shares the label.

### Consequences

Dropping the label from stdout on a conflict breaks autodream-now. Returning a label-matching plist from `--plist` would put another install's environment into an on-demand run. docs/adr/0023-install-and-scheduling.md#background-the-label-is-owned-by-a-runner-not-by-a-name-omp-autodream14-issue-60, "The label is owned by a runner, not by a name", covers the install.sh side (skip scheduling, keep the symlinks).

## a launchd plist is ours only when its ProgramArguments invoke this install's run.sh

Status: accepted · Date: 2026-11-21 · Code: `bin/scheduler-label.sh` (`runner_dir_of`, `norm_dir`, the plist scan loop)

### Context

`install.sh` and `bin/autodream-now.sh` each derived "which label is ours", and both got it wrong the same way: any plist whose body mentioned `run.sh` counted as ours. Installing a second autodream on a host that already ran one adopted the first one's label and rewrote that job in place. Nothing failed loudly. The overwritten job's triage sat dead for 18 days (omp-autodream#14, the cause of https://github.com/STRML/cc-autodream/issues/60).

docs/adr/0023-install-and-scheduling.md#background-the-label-is-owned-by-a-runner-not-by-a-name-omp-autodream14-issue-60, "The label is owned by a runner, not by a name", records the same decision.

### Decision

- The runner decides ownership. `runner_dir_of` reads `ProgramArguments:0..5` (the array is short: bash, the script, at most a `-c` form) and returns the directory of the first `*/run.sh`. The plist is ours when that equals the install dir. The label it carries and `AUTODREAM_DIR` do not count, because a hand-written plist may have no environment block but always names its program.
- `norm_dir` compares `pwd -P` of both sides, with a trailing slash stripped. A mismatch there is invisible: it yields a fresh label on every re-install instead of an error.
- The scan reads every plist in the LaunchAgents dir and goes by its `Label`, never by filename. launchd keys a job by Label. A foreign job holding the default label in `backup.plist` is still the job `install.sh` would boot out, and our own job renamed to a file without "autodream" in its name must still be found.
- A plist whose Label ends in `.ondemand` is skipped, by Label. `autodream-now` writes that sibling into `$AUTODREAM_DIR`, so the glob normally never sees one. The skip covers a hand-dropped copy, where adopting it would nest a second `.ondemand` suffix. A foreign job holding the default label in `backup.ondemand.plist` is still a conflict (Codex review of 0129fc0).
- Our own prior plist wins over any conflict, even when its label is not the default, so a re-install is idempotent.
- The default label held by anything that is not our runner, including a job with no `run.sh` at all, is a conflict.

### Consequences

A runner invoked as something other than a path ending in `/run.sh` is not recognised. `tests/scheduler-label.sh` pins each rule above, so change one only together with its test. The exit-status contract callers rely on is in `docs/adr/0023-install-and-scheduling.md#scheduler-label-reports-a-foreign-holder-of-the-default-label-as-exit-3-and-never-guesses-a-plist`.
