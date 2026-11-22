# 0031: adapter-omp suite: provenance, tool calls, skill reads and the overlay

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-omp.sh` (the nested, advisor and `isSidechain` groups), `tests/adapter-omp.sh` (the `tool_call_count` and `tools_used` group), `tests/adapter-omp.sh` (the `skills_invoked` and `skills_authored` groups; helpers `RS`, `RB`, `RR`, `RD`), `tests/adapter-omp.sh` (the overlay `--config` group, the `engine-bin` group)

## omp nested-session flags come from the path, and the test goes through normalize

### Context

An omp child (`<stamp>_<id>/__advisor.jsonl`, `<stamp>_<id>/<Name>.jsonl`) has no user turns and no `session_init`; its provenance is its path (docs/adr/0004-omp-adapter.md#background-the-omp-adapter-adaptersomp "The OMP adapter"). The old `isSidechain` rule keyed off `custom/agent` and `custom/subagent` records. omp writes neither, so the flag read false for every file and the noise gate's sidechain exemption never applied to a child (#114).

### Decision

- A child whose parent file is gone is still nested: the stamped directory name says so.
- The tests cover the path through `normalize` as well as raw `stats`, because that is the path the runner takes. The linearizer and `stats` are two files holding one rule, and a recorded `false` must not fall back to the filename, which on a normalized copy is a temp name. `autodream_meta` carries `nested` and `is_advisor` for that reason.
- `isSidechain` is asserted from provenance (advisor child, named child), never from a custom record.

### Consequences

A test that runs `stats` only on the raw file would pass with the normalize path broken. Keep both.

## omp tool calls are counted per file from one source, and the fixtures hold both shapes

### Context

omp records a tool call in two shapes: a `custom/tool_execution_start` record and a `toolCall` block inside an assistant message. docs/adr/0004-omp-adapter.md#background-the-omp-adapter-adaptersomp "The OMP adapter" states the rule: count the start records and fall back to the blocks only when the file has none. The fixtures matter because each alternative rule passes some real transcripts.

### Decision

- An advisor transcript has only the blocks (measured: 144 of 410 advisor files), so the fallback is exercised by a file with blocks and no start records.
- A main session holds each call as a record and as a block. The fixture holds both, and the assertion is that each call counts once. A union rule counts every main-session call twice.
- The rule is per file, not per call. A file with one start record and an unmatched block (not seen in the wild as a partial write, but 8 of 577 main transcripts hold blocks with no start record) reads the start records only, as it did before the fallback existed.
- An advisor whose every call was answered with `Tool "bash" not available` made attempts, not calls, and those must not clear the noise gate's `tool_call_count >= 5`. A real error from an available tool is still a call.

### Consequences

A fixture with only one shape cannot tell the per-file rule from a union. Keep the mixed and both-shapes files when adding cases.

## an omp skill read counts as use, matched by file, and the fixtures copy real shapes

### Context

omp has no Skill tool: the model loads a skill with `read skill://<name>` or a read of `<dir>/<name>/SKILL.md`. Of 739 transcripts modified since 2026-10-27, 2 held a `skill-prompt` record while 16 read `skill://<name>` and 18 read a SKILL.md path, so a detector that saw only `skill-prompt` read `skills_invoked_count` as 0 almost everywhere (docs/adr/0004-omp-adapter.md#background-the-omp-adapter-adaptersomp "The OMP adapter"). Authoring detection (#179) first matched by skill name.

### Decision

- The fixtures copy real shapes: a main session writes a read as a start record (`data.toolCallId`, `data.args.path`) and as a block (`id`, `arguments.path`); an advisor writes the block alone.
- A SKILL.md the session also edits is authoring, not use. A hashline edit's start record has no `args` (279 of 629 recent edit records); its path is only in the block's `[path#HASH]` header, and it is relative while the read is absolute. The session cwd resolves the relative path.
- The match is by FILE, not skill name. Two skills with one name in different roots do not mask each other; a worktree copy edited while the main checkout's copy is read is the 2026-10-30 aim-configs session. Shapes covered: hashline edit, edit and write with an absolute or `~` path, a read with a line selector, and a `~` path, `.`, `..` and a doubled slash naming the same file as the absolute path.
- A path that cannot be resolved (no cwd in the header, no `HOME` for `~`, a URL) falls back to the name match, as before #179. Two absolute paths are still compared as files.
- A SKILL.md fetched from the web (the 2026-09-27 forks-omp session) is being installed or inspected, not invoked (#185). An earlier fixture hid it only because the session also wrote the file; one that fetches without writing used to count. File-backed reads through omp's resolvers (`file://`, `memory://`, `skill://`) and plain paths still name a skill.

### Consequences

A fixture where the edit and the read use the same string cannot tell file matching from name matching. Keep the relative-header and cross-root cases.

## the omp L1 overlay cannot be replaced by the environment, and the engine-bin tests do not depend on the host

### Context

The L1 overlay (`adapters/omp/l1-no-advisor.yml`) turns omp's memory recall and the advisor off, because a worker that retained or consolidated memory would write a store every later session recalls from (docs/adr/0006-l1-confinement.md#background-who-starts-the-l1-worker-decision-2-of-the-consolidation-confinement "A host with no working sandbox says so", `docs/plans/2026-11-21-omp-l1-writes.md`).

### Decision

- `NO_ADVISOR_CFG` is ignored. Proving that a replacement overlay keeps memory off would need a YAML parser in the adapter, so there is none and every verb (`l1-argv`, `threads-argv`, `warmup-argv`, `l2-argv`) carries the shipped file. The test sets a hostile overlay (`memory: backend: mnemopi`) and checks all four verbs still pass the shipped path.
- The `engine-bin` fallback to the bare name `omp` is asserted only on a host that has none of the absolute candidates (`/opt/homebrew/bin/omp`, `/usr/local/bin/omp`). Those are real paths on a developer machine, so asserting it unconditionally made the suite depend on where omp happens to be installed.

### Consequences

Adding an overlay override means adding a validation step first, and updating the hostile-overlay test. Do not make the bare-name assertion unconditional.
