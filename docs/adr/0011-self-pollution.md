# 0011: Self-pollution: workers must not become sessions

Status: accepted · Governs: `bin/prune-self-sessions.sh`, `bin/run.sh`

This record holds 10 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Self-pollution (the eating-its-own-tail bug)](#background-self-pollution-the-eating-its-own-tail-bug)
- [Background: The AI-title stub vector (second-order self-pollution)](#background-the-ai-title-stub-vector-second-order-self-pollution)
- ["is this session ours" is decided by the first user turn, in one script every caller asks](#is-this-session-ours-is-decided-by-the-first-user-turn-in-one-script-every-caller-asks)
- [an AI-title stub is ours only if the file has no user turn and the title paraphrases our triage prompts](#an-ai-title-stub-is-ours-only-if-the-file-has-no-user-turn-and-the-title-paraphrases-our-triage-prompts)
- [transcript copies a killed worker left behind are removed by the parent after the round, not by a trap in the worker](#transcript-copies-a-killed-worker-left-behind-are-removed-by-the-parent-after-the-round-not-by-a-trap-in-the-worker)
- [L1 workers launch from the isolated work dir so an AI-title stub lands in the work bucket](#l1-workers-launch-from-the-isolated-work-dir-so-an-ai-title-stub-lands-in-the-work-bucket)
- [A missing or failing self-session pruner falls back to the raw session list](#a-missing-or-failing-self-session-pruner-falls-back-to-the-raw-session-list)
- [temp files left by a killed run are swept by the runner, not by the adapter or a trap](#temp-files-left-by-a-killed-run-are-swept-by-the-runner-not-by-the-adapter-or-a-trap)
- [The isolated work bucket is wiped after L1 as well as after L2](#the-isolated-work-bucket-is-wiped-after-l1-as-well-as-after-l2)
- [workers launch from an isolated cwd so Claude Code's AI-title stubs land in a bucket the runner owns and wipes](#workers-launch-from-an-isolated-cwd-so-claude-codes-ai-title-stubs-land-in-a-bucket-the-runner-owns-and-wipes)

## Background: Self-pollution (the eating-its-own-tail bug)

This section was moved here from the former CLAUDE.md. Its original title: "Self-pollution (the eating-its-own-tail bug)".

Every `claude --print` call used to persist its own session JSONL into `~/.claude/projects/-Users-<you>/`. So a run that triaged ~190 sessions left ~190 worker transcripts, and the NEXT night's run enumerated those as "sessions" to triage. On a real day, ~90% of the corpus was autodream looking at itself (215 enumerated vs. 21 real on 2026-05-29).

Three defenses, all in place:
1. **Root cause**: `--no-session-persistence` on every call. New runs leave no transcript.
2. **Enumeration filter**: after `find`, the session list is piped through `bin/prune-self-sessions.sh --filter`, which drops any session whose first user turn is one of autodream's own inlined prompts (markers: `Session transcript to analyze (literal absolute path)`, `Findings directory to aggregate (literal absolute path)`, legacy `SESSION_PATH=` / `FINDINGS_DIR=`). This catches transcripts left by runs predating the fix.
3. **Backlog cleanup**: `bin/prune-self-sessions.sh` (dry-run lists, `--delete` removes). `prune-self-sessions.sh` is the single source of truth for the "is this ours?" predicate; run.sh resolves it relative to itself (`BASH_SOURCE`).

The predicate is anchored to the FIRST user message so a human session that merely *discusses* autodream is not a false positive.

## Background: The AI-title stub vector (second-order self-pollution)

This section was moved here from the former CLAUDE.md. Its original title: "The AI-title stub vector (second-order self-pollution)".

`--no-session-persistence` suppresses the full transcript but NOT Claude Code's **AI-title generation**: a fire-and-forget background call that writes a one-line `{"type":"ai-title",...}` stub into the launch cwd's project bucket. Because workers ran from `cd "$HOME"`, those stubs landed in the real `-Users-<you>` bucket and polluted session history / `search-sessions` — 339 of them accumulated 2026-05-25…06-02 (titles like "Analyze Claude session findings", "Aggregate daily findings into report"). Whether a stub lands is version/timing-dependent (the `--print` process sometimes exits before the async write flushes — current builds often drop it, older ones flushed it), so the fix must not assume the binary's current behavior.

Two defenses:
1. **cwd isolation + wipe (run.sh)**: both layers now launch from `$AUTODREAM_DIR/work` (`WORK_DIR`), not `$HOME`. Claude maps cwd → `~/.claude/projects/<cwd with / and . → ->`, so any stub lands in the isolated `WORK_BUCKET` instead of the real bucket. `clean_work_bucket` (`rm -rf "$WORK_BUCKET"`) runs before L1 and after L2, so stubs never accumulate. Workers read/write only by absolute path, so cwd is functionally irrelevant — L1 cd's inside the worker subshell; L2 cd's inside a subshell so the change does not leak into the notify/pin steps. **Watch the apostrophes**: the L1 worker body is a single-quoted `bash -c '...'`, so a `'` in a comment there silently breaks quoting (it still passes `bash -n`).
2. **Pruner title predicate (`is_self_title`)**: catches orphan stubs in the real bucket left by runs predating defense 1. Gated on (a) NO user turn anywhere in the file — a real session keeps its title alongside its conversation turns, so it is never a title-only orphan and is never matched — AND (b) the title paraphrases our L1/L2 prompts (session triage → findings, aggregate findings → report). Tuned against the real backlog: spares terminal-tab-title stubs and unrelated headless orphans (e.g. "GCU Rush firmware development").

## "is this session ours" is decided by the first user turn, in one script every caller asks

Status: accepted · Date: 2026-11-21 · Code: `bin/prune-self-sessions.sh` (`SELF_RE`, `first_user_turn`, `is_self`, `--is-self`, `--filter`)

### Context

Every `claude --print` worker used to persist its own session JSONL, and the next night triaged them as real sessions (~190 self-generated files a night, about 90% of the corpus, per the script's help text; docs/adr/0011-self-pollution.md#background-self-pollution-the-eating-its-own-tail-bug, "Self-pollution", has the full account). The enumeration filter must drop those without ever dropping a human session that merely discusses autodream, for example one that mentions `SESSION_PATH=` mid-conversation.

### Decision

- A session is ours when its first user turn starts with one of our inlined prompts: `Session transcript to analyze (literal absolute path)`, `Findings directory to aggregate (literal absolute path)`, or the legacy `SESSION_PATH=` and `FINDINGS_DIR=` framings from earlier runs. The pattern is anchored to the start of the message content, which is what keeps a discussion of autodream from matching.
- Two transcript shapes carry user content. Claude stores a string (`{"type":"user",...,"content":"..."}`). OMP stores an array of items (`{"type":"message","message":{"role":"user","content":[{"type":"text","text":"..."}]}}`). The anchor `(content":"|text":")` matches both.
- `first_user_turn` finds the first record of either shape, with `grep -m1` over both patterns. Assistant and tool records never match, so callers always get the first user turn.
- The predicate lives only here. The adapter contract asks the question about one file through `--is-self`, and `run.sh` calls `--filter`. Exposing the predicate beats letting each adapter carry its own copy of the marker list: a marker added to `SELF_RE` must not have to be remembered in a second place.

### Consequences

A new prompt framing that autodream sends to a worker must be added to `SELF_RE`, or its sessions will be triaged as real. `tests/run-all.sh` covers the helper under `# prune-self-sessions helper: list / filter / delete`.

## an AI-title stub is ours only if the file has no user turn and the title paraphrases our triage prompts

Status: accepted · Date: 2026-11-21 · Code: `bin/prune-self-sessions.sh` (`is_self_title`)

### Context

Claude Code's async title generation writes a one-line `{"type":"ai-title",...}` record into the worker's session bucket even under `--no-session-persistence`, which only suppresses the full transcript. These stubs carry no conversation, so the first-user-turn rule (see `docs/adr/0011-self-pollution.md#is-this-session-ours-is-decided-by-the-first-user-turn-in-one-script-every-caller-asks`) never catches them. docs/adr/0011-self-pollution.md#background-the-ai-title-stub-vector-second-order-self-pollution, "The AI-title stub vector", covers how they accumulated.

### Decision

- A file matches only if it is an orphan: no user turn anywhere. A real session is one file holding its title alongside its turns, so it always has a user turn and is never matched. Only headless calls that did not persist a transcript leave a title-only orphan.
- The title must also describe session triage or findings aggregation. The model-generated titles paraphrase our L1 and L2 prompts, for example "Analyze Claude session findings", "Triage coding session for findings" and "Aggregate daily findings into report". A real headless orphan about an unrelated task (for example "GCU Rush firmware development") is spared.
- Three patterns cover the variants: the L2 aggregator (`aggregate.*findings`, `findings.*(into|report)`); L1 phrasings of "session triage ... findings", where the verb may follow the noun; and L1 "a verb acting on a session or transcript, producing findings, triage or analysis", which needs both halves to match.
- The patterns were tuned against the real backlog: they catch the L1 and L2 title variants and spare terminal-tab-title stubs and unrelated work-session orphans.

### Consequences

Loosening a pattern risks deleting someone's real headless output; tightening it leaves stubs in the session history. Check any change against a real backlog, both for what it catches and for what it must spare. `tests/run-all.sh` covers the helper under `# prune-self-sessions helper: list / filter / delete`.

## transcript copies a killed worker left behind are removed by the parent after the round, not by a trap in the worker

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1`, after the `xargs` call)

### Context
A worker killed mid-round never reached its own cleanup. What it leaves is transcript text: the chunk inputs and, with chunking on, a slim that is now the whole conversation. A trapped TERM is deferred until the foreground engine exits (the adapter says what that cost: see `docs/adr/0003-adapters-and-engines.md#the-stats-and-slim-wrappers-install-no-signal-trap-and-a-killed-runs-temp-file-is-swept-by-the-runner`), so a trap in the worker would trade a stale file for a worker that ignores SIGTERM. `FANOUT` workers (8 by default) create their own subdirectory in `.chunks` at once; one removing it between another's two `mkdir` steps would make that chunker fail for no reason.

### Decision
After the `xargs` pass every worker has returned, so any chunk input, slim, day or norm copy still on disk is a leftover. Gated on `L1_CHUNKING=1`, the parent removes `.chunks/*/in`, `*.slim.jsonl`, `*.slim.jsonl.cap`, `*.day.jsonl` and `*.norm.jsonl`, then the empty `.chunks` directory (that one only here, never in a worker). Chunk answers stay for the retry. With chunking off nothing changes from what it always left.

### Consequences
Do not add a worker-side trap, and do not remove `.chunks` from a worker. See docs/adr/0007-l1-chunked-triage.md#background-reading-a-long-session-chunked-triage, "Cleanup without a trap".

## L1 workers launch from the isolated work dir so an AI-title stub lands in the work bucket

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `cd "$WORK_DIR"`)

### Context
Claude Code writes an AI-title stub into the launch cwd's project bucket. Workers that ran from `$HOME` polluted the real session history (339 stubs between 2026-05-25 and 2026-06-02).

### Decision
The worker does `cd "$WORK_DIR"` (best effort) before the engine call, so any stub lands in `$WORK_BUCKET`. All paths used afterwards are absolute, so the `cd` is safe.

### Consequences
A relative path added to the worker after this line would resolve against the work dir. See docs/adr/0011-self-pollution.md#background-the-ai-title-stub-vector-second-order-self-pollution, "The AI-title stub vector (second-order self-pollution)", and the work-bucket write-list ADR.

## A missing or failing self-session pruner falls back to the raw session list

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `PRUNE --filter` step)

### Context
Autodream's own headless worker and aggregator transcripts must not be re-triaged. New runs leave none (`--no-session-persistence`), but runs predating that fix littered `~/.claude/projects/`. The prune helper owns the "is this ours?" predicate. See docs/adr/0011-self-pollution.md#background-self-pollution-the-eating-its-own-tail-bug, 'Self-pollution'.

### Decision
If `$PRUNE` is executable, `sessions.txt.raw` is filtered through `"$PRUNE" --filter` into `sessions.txt`. If the helper is missing, or the filter fails, `sessions.txt.raw` is copied unchanged.

### Consequences
- The fallback is deliberate: failing open re-triages some of autodream's own transcripts left by runs predating the fix, while failing closed would silently drop real sessions from the night.
- Do not change the fallback to an error without deciding which loss is worse.

## temp files left by a killed run are swept by the runner, not by the adapter or a trap

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sweep_killed_leftovers`)

### Context
A run killed mid-flight (this pipeline's normal failure) leaves the temp its adapter was writing, `<out>.tmp.XXXXXX`, and slim-transcript.sh's `<dst>.pre.jsonl`. The adapter cannot clean up after its own death: a signal trap defers the signal until the delegate returns and hangs the run (see `docs/adr/0003-adapters-and-engines.md#the-stats-and-slim-wrappers-install-no-signal-trap-and-a-killed-runs-temp-file-is-swept-by-the-runner`: measured, the test hung 120 s and left orphaned `slim-transcript.sh` processes). Issue #57.

### Decision
The cleanup lives in the runner, where a killed process cannot skip it: the next run removes `*.tmp.??????`, `*.pre.jsonl`, `*.stage` and `.chunks/*/*.stage` directly under the findings dir (the `.stage` files one level down in `.chunks/<hash>/`) and logs the count; the sweep grew `.stage` with #169. It is called before the nothing-to-triage exit, so a night with no sessions still sweeps (see `zero-session-night-writes-full-run-stats-and-still-cleans-up`). Nothing reads these names (the findings glob is `*.json` and slim output is read by exact path), so this is about not accumulating them; a stale temp from a killed run is not a partial result anyone should read. It runs under the per-date lock, so no live writer of these files exists. The test is `-e` or `-L`, not `-f`: a symlink or a directory is what a worker leaves as its answer, and `-f` would skip both.

### Consequences
Do not move the sweep outside the per-date lock; a live writer's temp would be deleted. The guarantee is only as strong as the lock: if the locks dir cannot be created the run proceeds unlocked with a WARNING. A new temp-file suffix in the findings dir has to be added to the glob list here.

## The isolated work bucket is wiped after L1 as well as after L2

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `clean_work_bucket` after the round loop)

### Context
The work bucket is L2's launch directory and an unconfined L1 worker can still write it (a confined one cannot: it is not on the write list), so whatever an unconfined worker left there must not be there for L2 to read. See docs/adr/0011-self-pollution.md#background-the-ai-title-stub-vector-second-order-self-pollution, 'The AI-title stub vector' (wipe before L1, after L1 and after L2) and 'What the sandbox allows'.

### Decision
`clean_work_bucket` runs here, right after the retry rounds and the stage-root removal, and not only after L2.

### Consequences
- Removing this call lets a worker plant files for L2 in its launch directory.

## workers launch from an isolated cwd so Claude Code's AI-title stubs land in a bucket the runner owns and wipes

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`WORK_DIR`, `WORK_BUCKET`, `clean_work_bucket`; `probe_roots` for the primary-dir keying)

### Context
Claude Code writes a one-line `{"type":"ai-title",...}` stub into the launch cwd's session bucket even under `--no-session-persistence` (that flag only suppresses the full transcript). Run from `$HOME`, those stubs polluted the user's real session history. See docs/adr/0011-self-pollution.md#background-the-ai-title-stub-vector-second-order-self-pollution, "The AI-title stub vector (second-order self-pollution)" (339 stubs between 2026-05-25 and 06-02).

### Decision
- Every `claude --print` worker reads and writes by absolute path, so its cwd is functionally irrelevant; it is pointed at `$AUTODREAM_DIR/work` (`WORK_DIR`) purely to redirect the session bucket. Claude maps the launch cwd to `~/.claude/projects/<cwd with / and . replaced by ->`, so `WORK_BUCKET` is that path under `PROJECTS_DIR`.
- `clean_work_bucket` (`rm -rf "$WORK_BUCKET"`) runs before L1, after L1 and after L2, so stubs never accumulate.
- `WORK_BUCKET` stays keyed off the PRIMARY projects dir even when extra session roots are scanned: the lean workers run under the default config, so their stubs land in the default bucket, which the isolation and the wipe are built around. Scanning extra roots does not change that.

### Consequences
Do not key the bucket off a scanned root. A worker's cwd must stay `$WORK_DIR`; a new engine that ignores the cwd convention would put stubs back in a real bucket.
