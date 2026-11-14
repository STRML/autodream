# Dropped threads: a cross-day index of work Sam started and never finished

Status: approved by Sam 2026-11-14; revised the same day after an adversarial Fable
review (findings numbered F1 to F12 below).

## Intent

Sam wants three things from his transcripts:

1. A recap of each day, with suggestions.
2. A way to find threads he dropped: projects he started and never finished, and
   ideas he raised and never followed up.
3. To run it locally, on Haiku or the local DeepSeek.

The recap already exists as `dreams/<date>.md`. The other two do not. Autodream judges
each session alone, in one night. It can say that a session's goal was `not_achieved`,
but it cannot say that nothing in the nine days since picked the goal back up. That
second half is what makes a thread dropped, and it needs memory across days.

When a dropped thread turns up, Sam should be able to resume it in a new session
already briefed on the goal, where the work stopped, and which transcripts hold the
detail. He also wants a place to explore: a Claude Code session that knows the index,
and a local HTML dashboard it opens (Sam, 2026-11-14: "a session I can open, maybe in
cc, maybe with a local html dashboard it renders, so I explore ideas").

## Goals

- Keep a persistent thread index, updated nightly, that links Sam's sessions across
  days into threads and gives each thread a status.
- Add a "Dropped threads" section to the morning report.
- Ship a CLI to list, search, close, reopen and resume threads.
- Ship `threads.html` and an explore session.
- Capture ideas Sam deferred mid-session as threads of their own.
- Run the linker on an engine Sam names: Haiku by default, local DeepSeek as an option.

## Non-goals

- A separate always-on daemon. The nightly launchd job is the daemon.
- Re-reading transcripts. L1 already writes `underlying_goal`, `outcome` and
  `notable_initiatives` for every session, and the index is built from those fields.
- A served web app. The dashboard is a static file; nothing listens on a port.

## Anti-goals

Any of these makes the feature a failure even if it runs:

- A list so long that Sam stops reading it. The report shows at most 5.
- Threads built from sessions Sam did not drive: subagents, workflow workers, review
  rounds, scripted probes.
- A thread Sam closed coming back because a new session reworded its goal.
- A model that can write the index, or transcript text that can act on Sam's machine
  through the resume brief, the explore session or the HTML page.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | **Nightly LLM linker over L1's facets** (picked) | One call a night over every new eligible session. It handles reworded goals and keeps state small. Links come from a model judgment, so some will be wrong; `close` and `reopen` correct them. |
| B | Embedding similarity over goals | Deterministic, but short goals reworded across days cluster poorly and need a tuned threshold. Could pre-filter A later. |
| C | Separate daemon re-reading transcripts with local DeepSeek | Repeats L1's whole read plus its sleep, retry and self-pollution defenses. Rejected. |

## Delivery order

Everything below ships. The order keeps each PR testable on its own.

1. Thread index, linker, `threads.sh` list/search/close/reopen/resume/backfill, and
   the report section. Once it merges, Claude runs the backfill on local DeepSeek, so
   the index holds past work before the explorer exists.
2. `threads.html` and `threads.sh explore`.
3. `deferred_ideas` in L1. Ideas from before this PR exist only in transcripts, so
   recovering them means re-triaging old sessions. That stays a separate opt-in run,
   and its cost is measured on a sample and quoted to Sam before it starts.

Cut: `merge` (use close plus the linker), and a `/threads` command in the
`autodream-band` mod.

## Which sessions form threads (F1, F2, F10)

Measured over 2026-11-01 to 11-13 (479 top-level triaged sessions): 224 have one user
message, 122 read as review rounds, and storage buckets split one repo across
harnesses (`-Users-samuelreed-git-oss-local-llm` and `-git-oss-local-llm`). So:

- **Eligible** means top-level (`nested` false in the runner's data), at least 2 user
  messages (`user_message_count` from the stats sidecar), and a session cwd outside
  `$TMPDIR`, `/tmp`, `/private/tmp` and any `scratchpad` directory. 254 of the 479
  pass the message test. A session whose sidecar is missing is not eligible and is
  counted in `threads_unmeasured`.
- **Goal** is `underlying_goal`, else the first entry of `notable_initiatives`, which
  is a string rather than an array in omp findings and must be read as either.
- **Repo** is a hint, not a partition. The runner derives it from the session cwd:
  a worktree path (`.claude/worktrees/<name>`, `.worktrees/<name>`) maps to its main
  repo, and the claude and omp bucket encodings map to the same path. A session whose
  cwd it cannot resolve gets an empty repo.
- **Session path and repo come from the runner**, held in memory from before L1 (the
  `SESSION_ROWS` pattern `triage-candidates.sh` uses). Never from `sessions.txt`, a
  findings JSON or `rollup.tsv`, all of which an L1 worker can rewrite
  (`bin/run.sh:3691`).

## The linker (F1, F5, F6, F11)

```
 eligible sessions from the last 14 days not yet in the index
        +  open threads (id, title, repo, goal, last_seen), last 90 days
        +  closed threads (id, title, repo only)
        │
        ▼  one call, stdin → stdout, no tools, hard timeout
 assignments: {hash, thread: <id>|new, title?, finished: bool}
        │
        ▼  runner validates each assignment alone; a bad one is dropped, not the batch
 lock → re-read threads.jsonl → merge → write temp → rename → unlock
```

- **One call a night**, across all repos. When the input passes
  `AUTODREAM_THREADS_MAX_INPUT` bytes, split it into calls by repo hint, never by
  storage bucket.
- **Catch-up, no watermark.** Each night links every eligible `(date, hash)` from the
  last 14 days that the index lacks. A failed or skipped night is filled by the next
  one, a rebuild of an older date is harmless, and backfill uses the same path.
  Records are keyed by `(date, hash)`, so a re-triaged session replaces its link.
- **Engine.** `AUTODREAM_THREADS_ENGINE` names an adapter and
  `AUTODREAM_THREADS_MODEL` a model; the defaults are `claude` and
  `claude-haiku-5-5`. Each adapter gets a `threads-argv` verb with no tools. A test
  proves the verb cannot write: the mock tries to write a file and the file must not
  appear. The omp warmup drops `--tools` under `yolo` (`adapters/omp/adapter.sh:125`),
  so the omp verb must pass an explicit empty tool list, verified against the CLI
  before PR 1 merges.
- **Bounded.** `AUTODREAM_THREADS_TIMEOUT` (default 300 seconds) through the same
  `timeout` wrapper as L1. Any failure is logged and counted, and the report is
  written anyway.
- **The lock covers only the merge.** No model call runs under it, so the
  `question-streaks.sh` lock's 120-second stale reclaim (`bin/question-streaks.sh:188`)
  is safe to copy. The CLI takes the same lock for close and reopen.

## The thread record

| Field | Source |
|---|---|
| `id` | `t-<8 hex>`, assigned by the runner |
| `kind` | `work` or `idea` |
| `repo` | runner hint, may be empty |
| `title` | model-proposed, capped at 120 characters, control characters stripped |
| `goal` | newest eligible session's goal |
| `sessions[]` | `{date, hash, session_path, outcome}`, path from the runner |
| `status` | `open`, `done`, `closed_by_sam` |
| `done_by` | `linker` or `sam` |
| `last_seen` | maximum date across `sessions[]` |

## Status rules (F3, F9)

- **done:** the linker marks a session `finished` AND that session's `outcome` is
  `fully_achieved` or `mostly_achieved`. Both are model judgments, from two calls.
  Every thread closed this way that night is listed in the report, so a wrong close is
  visible.
- **dropped** (computed at read time, never stored): `open`, `last_seen` older than
  `AUTODREAM_THREADS_DROPPED_DAYS` (default 7), and the newest outcome is
  `not_achieved`, `partially_achieved` or `unclear_from_transcript`. A thread whose
  newest outcome is `mostly_achieved` stays open and quiet, without being reported as
  dropped. Fable's simulation put this near 4 a week.
- **closed_by_sam** is sticky. The linker sees closed threads as id and title, so a
  reworded session attaches instead of spawning a new thread; only `reopen` changes
  the status.

**Report ranking:** threads that crossed into dropped since the last report first,
then the rest by linked-session count. Two of the five slots are reserved for ideas
when any exist, so ideas are not starved by a long work list.

## Backfill (F11)

`threads.sh backfill FROM TO [--engine E] [--model M] [--max-calls N]` runs the same
catch-up over a past range, oldest first, prints its call count before starting and
stops at the budget. Goals exist from 2026-07-17, so that is the useful floor. Only
dates from 2026-11-01 have `rollup.tsv`, so backfill reads `nested` and
`user_message_count` from the stats sidecars directly. A date without sidecars is
skipped and named in the output.

## Resume and explore (F8)

```
 threads.sh resume <id>            prints the brief
 threads.sh resume <id> --launch   claude, default permission mode, cwd = repo or $HOME
 threads.sh explore                renders threads.html, opens it, starts claude in a
                                   cmux split with tools Read + Bash(threads.sh *)
```

The brief carries runner facts (dates, outcomes, repo, transcript paths), the goal and
title inside a fenced block labelled as data from transcripts, and an instruction to
Read the transcripts for detail. It never inlines `evidence_excerpt` or findings text.
Unlike `review.sh` (`bin/review.sh:461`), neither command passes
`bypassPermissions`. The review.sh launch rules still apply: no whole report inlined,
no one-word prompt.

## The dashboard (F9)

```
 ┌ Threads ─────────────────────────── [search______] [repo ▾] ────┐
 │ Dropped (4)   Open (40)   Ideas (18)   Done (131)                │
 ├──────────────────────────────────────────────────────────────────┤
 │ ⚠ mlx-serve cache export 404          local-llm   3 sess  9d     │
 │   last: not_achieved · "find why export returns 404"             │
 │   [copy resume command]  [copy close command]                    │
 └──────────────────────────────────────────────────────────────────┘
```

- One static file, `$DREAMS_DIR/threads.html`, written by temp file and rename at the
  end of each nightly run and after every CLI write. A failed render keeps the old
  page, and the header shows the generation time.
- Thread data is embedded as JSON in a `type="application/json"` script tag with `<`
  escaped, and rendered with `textContent` only.
- A CSP meta tag: `default-src 'none'; script-src 'self' 'unsafe-inline';
  style-src 'unsafe-inline'; connect-src 'none'`.
- Copy buttons build commands only from ids matching `^t-[0-9a-f]{8}$`.
- It is a local file, not a published Artifact, per the house rule for reports Sam
  reads.

## Deferred ideas (F12)

SESSION_TRIAGE.md gains `deferred_ideas`: up to 3 things the user raised in the
session and explicitly put off, each with a verbatim quote under 200 characters, empty
rather than inferred. `bin/merge-chunks.sh` merges fields by explicit rule
(`bin/merge-chunks.sh:83-86`), so it gets a rule for this field (concatenate, dedupe,
cap 3) and a test. Ideas reach the linker as `kind: idea` candidates.

## Failure matrix

| State or input | What happens | How it can fail | What the caller is told |
|---|---|---|---|
| Nothing triaged tonight (early return, `bin/run.sh:3677`) | Catch-up and render still run on that path | Section missing | Report section from the current index |
| No eligible sessions tonight | No linker call; dropped set recomputed | none | `threads_linked: 0` |
| Linker engine down, refusing or timed out | Index untouched; next night catches up | Stale links for a day | `threads_link: failed`, report notes the index is a night behind |
| One assignment malformed, unknown id, or unknown hash | That assignment dropped, the rest kept | Wrong link | `threads_rejected: N` |
| Linker marks finished but outcome not achieved | Link kept, close ignored | False done | `threads_close_refused: N` |
| Linker auto-closes a thread wrongly | Thread listed under "closed tonight" | Silent false done | Visible in the report; `reopen` fixes it |
| `threads.jsonl` exists but cannot be read | No write, no render | Index read as empty | Banner, `threads_state: unreadable` |
| Two runs at once, or a CLI write during a run | Lock held only for the merge; the loser retries 3 times then skips | Lost update | `threads_skipped: locked`; CLI fails loudly |
| A session re-triaged with a new goal | Its `(date, hash)` link replaced | Duplicate thread | none |
| Rebuild of an older date | Catch-up links only what is missing | History rewritten | none |
| A worker rewrites `sessions.txt` or a findings JSON's `project`/`session_path` | Path and repo come from the runner's in-memory rows | Thread misfiled | Not reachable; a test forges all three |
| The linker verb tries to write a file | It has no tools | A model writes state | Not reachable; a test proves it |
| Session sidecar missing | Session not eligible | Real work skipped | `threads_unmeasured: N` |
| Render fails | Old page kept | Stale page | Header time; `threads_render: failed` |
| Thread text holds `</script>` or HTML | Escaped and set with `textContent` | Script injection | Not reachable; a test feeds it through |
| Resume brief built from a goal holding instructions | Goal quoted as data; default permission mode | Injected session acts | Every tool call still asks Sam |

Each row becomes a red E2E test in `tests/run-all.sh`, with a mock linker, before the
code it covers exists.

## Left to the builder

- Prompt wording for the linker and for `deferred_ideas`.
- CLI flag names. The entry point is a new `bin/threads.sh`, linked into
  `$AUTODREAM_DIR` by `install.sh`.
- `AUTODREAM_THREADS_MAX_INPUT`'s default, from a measured night.
