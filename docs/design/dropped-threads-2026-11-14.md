# Dropped threads: a cross-day index of work Sam started and never finished

Status: design, awaiting Sam's approval (2026-11-14).

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

When a dropped thread turns up, Sam should be able to resume it: start a new session
already briefed on the goal, where the work stopped, and which transcripts hold the
detail. (Claude's call, 2026-11-14, taken as a two-way door.)

## Goals

- Keep a persistent thread index, updated nightly, that links sessions across days
  into threads and gives each thread a status.
- Add a "Dropped threads" section to the morning report: the top few, each with the
  reason it counts as dropped.
- Ship a CLI to list, search, close and resume threads.
- Capture ideas Sam deferred mid-session ("later", "we should also", "park that") as
  threads of their own.
- Give Sam a place to explore threads and ideas: a Claude Code session that knows the
  index, and a local HTML dashboard it opens (Sam, 2026-11-14: "a session I can open,
  maybe in cc, maybe with a local html dashboard it renders, so I explore ideas").
- Run the linker on the engine Sam picks: Haiku by default, local DeepSeek through
  the omp adapter as an option.

## Non-goals

- A separate always-on daemon. The nightly launchd job is the daemon, and a thread
  index one day stale is fine.
- Re-reading transcripts. L1 already reads every session and writes
  `underlying_goal`, `outcome` and `notable_initiatives`, and the index is built from
  those fields.
- A served web app. The dashboard is a static file regenerated each night; nothing
  listens on a port.

## Anti-goals

Any of these makes the feature a failure even if it runs:

- A list so long that Sam stops reading it. The report shows at most 5, ranked.
- Threads built from subagent and workflow sidecars. A `debugger` subagent's
  `not_achieved` belongs to its parent session. Only top-level sessions form threads.
- A thread Sam closed coming back the next night because a new session reworded its
  goal.
- An L1 or linker worker that can forge, close or rewrite a thread it was not given.
  The repo's rule holds here too: the runner writes state, and models only propose.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | **Incremental LLM linker, nightly, per project** (picked) | One small call per project that had sessions that night. The call gets the project's open threads and tonight's goals, assigns each goal to a thread or starts a new one, and says whether any thread is now finished. It is cheap, it handles rewording, and the state stays small. Links come from a model judgment, so some will be wrong; `close` and `merge` in the CLI correct them. |
| B | Embedding similarity over goals, clustered per project | Deterministic, with no model call per night. Short goals reworded across days ("fix 404 on cache export", later "mlx-serve export endpoint") cluster poorly, and the threshold would need tuning per project. It could become a pre-filter for A later. |
| C | Separate daemon that re-reads transcripts with local DeepSeek | Independent of autodream, but it repeats L1's read of every session and needs its own session roots, sleep handling, retries and self-pollution defenses. Rejected. |

## Delivery order

Everything below ships; the order keeps each PR testable on its own.

1. Thread index, linker, `threads.sh` list/search/close/reopen/merge/resume, and the
   report section.
2. `threads.html` and `threads.sh explore`.
3. `deferred_ideas` in L1, and `threads.sh backfill`.

## The linker's engine

The linker gets a new adapter verb, `threads-argv`, shaped like `l2-argv` but with no
tools at all: its input arrives on stdin and its answer leaves on stdout. Reusing
`l1-argv` would grant `Read Write` under `bypassPermissions`, which would let a model
write `threads.jsonl`. The omp adapter gets the same verb, so local DeepSeek can run
it.

## Design

```
 L1 (existing) ─▶ findings/<date>/<hash>.json   new field: deferred_ideas[]
 rollup.sh (existing) ─▶ rollup.tsv             nested (runner), outcome (L1 model)
        │
        ▼
 bin/threads.sh link <date>          new; runs after rollup, before L2
   for each project with top-level sessions tonight:
     input  = the project's open threads + tonight's goals and deferred ideas
     engine = AUTODREAM_THREADS_ENGINE (default: the L1 engine)
     tools  = none; input on stdin, assignments on stdout (like L2)
     output = validated by the runner, the only writer
        │
        ▼
 $AUTODREAM_DIR/threads/threads.jsonl    one row per thread, one rename per write
 findings/<date>/dropped-threads.md      top 5; L2 reads it by exact path
        │
        ▼
 L2 copies it into "Dropped threads"     as it copies triage-candidates.md today
 threads.sh [query] [--dropped] [--project p]
 threads.sh close|reopen|merge <id> ...
 threads.sh resume <id>                  prints a brief; --launch starts claude with it
```

### The thread record

| Field | Source |
|---|---|
| `id` | `t-<8 hex>`, assigned by the runner, never by a model |
| `project` | derived by the runner from the real session path (the `pin-projects.tsv` rule), never from a findings JSON or `rollup.tsv`, which copies the model's value when python3 is missing |
| `kind` | `work` or `idea` |
| `title` | proposed by the model, capped at 120 characters by the runner |
| `goal` | the newest `underlying_goal`, or the idea text |
| `sessions[]` | `{date, hash, session_path, outcome}`; `session_path` from `sessions.txt` |
| `status` | `open`, `done`, `closed_by_sam` |
| `last_seen` | date of the newest linked session |
| `updated_by` | `linker` or `sam` |

### Status rules

The runner applies these rules. A model's output never sets a status directly.

- A thread becomes `done` only when the linker says a session finished it AND that
  session's `outcome` is `fully_achieved` or `mostly_achieved`. Both are model
  judgments, but from two separate calls (the linker and that session's L1 worker),
  so one call cannot close a thread alone.
- A thread counts as dropped when it is `open`, its `last_seen` is older than
  `AUTODREAM_THREADS_DROPPED_DAYS` (default 7), and its newest outcome is not
  `fully_achieved`. Dropped is computed at read time and never stored.
- `closed_by_sam` is sticky. The linker sees closed threads as id and title only, so
  it can attach a reworded session to one instead of starting a new thread. Only
  `reopen` changes its status.

The report ranks dropped threads by kind (`work` before `idea`), then by the number of
linked sessions (effort already spent), then by how recently the thread went quiet.
It shows at most 5.

### Deferred ideas

SESSION_TRIAGE.md gains a `deferred_ideas` field: up to 3 one-line things the user
raised in the session and explicitly put off, each with a verbatim quote under 200
characters. The prompt tells L1 to leave the field empty rather than infer an idea.
Each idea becomes a `kind: idea` thread through the same linker, so a later session
that does the work closes it.

### Backfill

Work threads backfill from the findings already on disk (173 date directories since
2026-05-25), oldest first, with one linker pass per project per date. Backfill never
runs by itself: Sam starts it with `threads.sh backfill FROM TO [--engine E]
[--max-calls N]`, which prints the call count before it starts and stops at the
budget. Local DeepSeek is the suggested engine for it, since it costs nothing per
call. Deferred ideas cannot be backfilled without re-triaging every session; that
is a separate opt-in run.

### Resume brief

`threads resume <id>` prints the goal; each linked session's date, outcome and
`notable_initiatives`; the last session's findings; and the transcript paths.
`--launch` opens a claude session with the brief as its first prompt. The `review.sh`
rules apply: never inline a whole report, and never launch with a one-word prompt.

### Explore: a session plus a dashboard

```
 threads.sh explore
   │
   ├─▶ threads.sh render ─▶ $DREAMS_DIR/threads.html   static, one file, no server
   │                         open in the browser
   │
   └─▶ claude session (cmux split, as review.sh does)
         first prompt: what the index holds, where it lives, the CLI verbs
         tools: Read on threads.jsonl and findings; Bash for `threads.sh ...`
         Sam asks: "what did I drop on mlx-serve?", "which ideas cluster?",
                   "close t-3fa1, it's dead", "resume t-91c0"
         after any close/reopen/merge it re-renders the HTML
```

The dashboard:

```
 ┌ Threads ─────────────────────────── [search______] [project ▾] ┐
 │ Dropped (12)   Open (40)   Ideas (18)   Done (131)              │
 ├─────────────────────────────────────────────────────────────────┤
 │ ⚠ mlx-serve cache export 404          local-llm   3 sess  9d    │
 │   last: not_achieved · "find why export returns 404"            │
 │   [copy resume command]  [copy close command]                   │
 │ ⚠ idea: per-pack prefix warmup        local-llm   1 sess  14d   │
 │   "we should also warm the prefix cache per pack, later"        │
 │ ...                                                             │
 └─────────────────────────────────────────────────────────────────┘
```

The page is read-only: its buttons copy a CLI command, so every state change still
goes through the CLI and its lock. Search and filters run client-side over the thread
data embedded in the page. `threads.sh render` runs at the end of each nightly run
and after every CLI write. The page is a local file, not a published Artifact, per
the house rule for reports Sam reads.

The session is the place for questions the page cannot answer, such as grouping
ideas by theme or reading a transcript to decide whether a thread is dead. The
`autodream-band` mod can also gain a `/threads` command that starts the same session
in place.

## Failure matrix

| State or input | What happens | How it can fail | What the caller is told |
|---|---|---|---|
| No top-level sessions tonight | Linker skipped; dropped set recomputed | none | Report section built from the current index |
| Linker engine down or refusing | That project's threads untouched | Stale links | run-stats `threads_link_failed: N`; report says the index was not updated for that project |
| Linker output malformed, or names an unknown thread id | That project's assignments discarded | Wrong link | `threads_rejected: N` in run-stats, log line |
| Linker closes a thread whose session outcome is not achieved | Close ignored | False `done` | `threads_close_refused: N` |
| `threads.jsonl` exists but cannot be read | No write, no report section | Index frozen | Banner, and run-stats `threads_state: unreadable`; never read as empty |
| Rebuild of an older date (`AUTODREAM_FORCE=1`) | Refused by a watermark, as in `question-streaks.sh` | History rewritten | `threads_skipped: older_date` |
| Two runs at once (nightly and `autodream-now.sh`) | `mkdir` lock; the second run skips | Lost update | `threads_skipped: locked` |
| Sam runs `close` during a nightly run | CLI takes the same lock | Lost close | CLI waits, then fails loudly |
| A session is re-triaged with a different goal | Link keyed by `(date, hash)` and replaced | Duplicate thread | none; the update is idempotent |
| Render fails (bad record, disk full) | Previous `threads.html` kept; written by temp file and rename | Stale page | Page header shows its generation time; run-stats `threads_render: failed` |
| Thread text holds HTML or script | Escaped on render; data embedded as JSON in a non-executing script tag | Script injection from a transcript quote | Not reachable; a test feeds `</script>` through a goal |
| A worker forges `project` or `session_path` in a findings JSON | Project comes from the session path, path from `sessions.txt` | Thread filed under another project | Not reachable by construction, python3 or not; a test forges both |
| Linker tries to write a file | It has no tools | State written by a model | Not reachable; the adapter verb grants none |

Each row becomes a red E2E test in `tests/run-all.sh`, with a mock linker, before the
code it covers exists.

## Left to the builder

- Prompt wording for the linker and for `deferred_ideas`.
- CLI flag names. The entry point is a new `bin/threads.sh`, linked into
  `$AUTODREAM_DIR` by `install.sh`; the `autodream` skill can call it.
- Batch size when a project has more open threads than fit one call. A starting
  point: the 40 most recent open threads in full, plus up to 40 closed ones as id
  and title.
