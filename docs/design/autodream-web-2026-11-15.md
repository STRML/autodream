# Autodream web: "my life in AI"

Status: design, awaiting Sam's approval (2026-11-15).

## Intent

Sam wants one always-on page on this Mac that shows his life in AI: what happened
lately across his projects and agents, every past dream, the threads he dropped and the
ideas he deferred, how autodream itself is doing, and stats over time. He wants to act
from it, not only read it: resume a dropped thread in a new session, close one that is
dead, reopen one closed by mistake. (Sam, 2026-11-15: "a whole dream / AI progress
dashboard, complete with stats"; "so this kind of becomes 'my life in ai' in a way".)

The first screen answers "what happened lately" (Sam's choice over stats-first,
worklist-first and ops-first).

## Goals

- A local web server, started by launchd and kept alive, on this Mac only.
- Five views: Lately (home), Dreams, Threads, Progress, Stats.
- Working Resume, Close and Reopen buttons on threads.
- Data read from what autodream already writes; no second pipeline.

## Non-goals

- Access from other machines or the phone (Sam chose "This Mac only").
- A database server, a frontend build step, or new runtime dependencies.
- Editing dreams or findings from the page.

## Anti-goals

- A web page that can start a session or change the index when another local page or
  process asks it to. The buttons run code on this Mac.
- A second writer to `threads.jsonl`. Every change goes through `threads.sh`, which owns
  the flock.
- A page that is slow to open because it re-reads 28,000 findings files on each load.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | **Python stdlib HTTP server + one vanilla-JS page** (picked) | `python3` is already required by the renderer and the lock. No packages, no build. The server reads files and calls `threads.sh`; the page fetches JSON. |
| B | Bun or Node app with a framework | Nicer components, at the cost of a toolchain and a build step for five views. |
| C | Static site regenerated nightly, plus a small action endpoint | Cannot show a run in progress, and still needs a server for the buttons. |

## Shape

```
 launchd: com.<user>.autodream-web  (KeepAlive, RunAtLoad)
   └─ bin/autodream-web.py  127.0.0.1:<port>
        ├─ GET  /                     web/index.html (one page, five views, vanilla JS)
        ├─ GET  /api/lately?days=7    timeline by project and day
        ├─ GET  /api/dreams           list of dates; /api/dreams/<date> → markdown
        ├─ GET  /api/threads          threads.sh list --json (+ dropped computed)
        ├─ GET  /api/progress         live run phase from logs/run-<date>.log, lock state
        ├─ GET  /api/stats            per-night series from run-stats + rollups
        └─ POST /api/threads/<id>/{close,reopen,resume}
                                      → threads.sh close|reopen|resume --launch
```

### Data

| View | Source on disk |
|---|---|
| Lately | `findings/<date>/rollup.tsv` (status, project, outcome, duration, models) plus each findings JSON's `underlying_goal` and `notable_initiatives`; `threads.jsonl` for what dropped or finished that day; the newest `dreams/<date>.md` for its top patterns and open questions |
| Dreams | `dreams/*.md` (173 today), rendered client-side from markdown |
| Threads | `threads.sh list --json`, the same data `threads.html` embeds |
| Progress | `logs/run-<date>.log` tail (phase lines like `L1 round`, `L2 aggregation attempt`), the per-date run lock, `run-stats.txt` of the last finished night |
| Stats | `run-stats.txt` per night (sessions, triaged, gated, errors, elapsed), `rollup.tsv` (outcomes, models, projects), `categories.tsv` (findings), `threads.jsonl` (dropped vs done over time) |

`rollup.tsv` exists only from 2026-11-01. For older nights the server derives the same
row from the findings JSON and its stats sidecar, which is what `rollup.sh` reads.

**Cache.** The server builds a per-night summary (`web-cache/<date>.json`) the first
time it needs a night, keyed by the night's findings-dir mtime, so a rebuilt night is
re-read and an unchanged one never is. First start reads every night once; later starts
read only new or changed nights.

### Lately (home)

```
 ┌ Lately ─────────────────────────── [7 days ▾] ──────────────────────┐
 │ Last night's dream · 2026-11-14 · 3 open questions   [read]          │
 │   1. ...top pattern...   2. ...   3. ...                             │
 ├──────────────────────────────────────────────────────────────────────┤
 │ Sat 11-14                                                            │
 │   local-llm      5 sessions  ✓ 3  ◐ 1  ✗ 1   "Reach 2M-token context…" │
 │   rush/GCU       2 sessions  ✓ 2             "Upgrade cars to 5.1.0"  │
 │   + 2 threads dropped · 1 idea deferred · 9 finished                 │
 │ Fri 11-13 …                                                          │
 └──────────────────────────────────────────────────────────────────────┘
```

Each project row expands to its sessions (goal, outcome, model, transcript path). Thread
titles link to the Threads view.

### Security (this Mac only)

- Binds `127.0.0.1` only. A non-loopback bind is refused at startup.
- **Token.** `install.sh` writes a random token to `$AUTODREAM_DIR/web-token` (mode 0600).
  The server sets it in an `HttpOnly; SameSite=Strict` cookie on `GET /` and every POST
  must carry it in an `X-Autodream-Token` header the page reads from a `<meta>` tag.
  Another local page cannot read the token, so it cannot forge a POST.
- **Origin and Host.** POSTs require `Origin` and `Host` to be the server's own
  `http://127.0.0.1:<port>`, which blocks DNS rebinding and cross-site requests.
- **No shell.** Actions run `threads.sh` with an argv list, never a shell string, and the
  id must match `^t-[0-9a-f]{8}$`.
- **Rendering.** Dreams and thread text are untrusted (they quote transcripts). Markdown
  is rendered to DOM nodes with `textContent` for text and an allowlist of tags; no raw
  HTML passes through. The CSP from `threads.html` applies, with `connect-src 'self'`.

### Resume

`POST /api/threads/<id>/resume` runs `threads.sh resume <id> --launch`, which already
opens a cmux split in the default permission mode with the goal quoted as data. The
server returns once cmux reports the split; the session itself runs outside the server.
If cmux is not running, the response says so and offers the brief to copy.

### Running

- `install.sh` provisions the agent like the review agent: generated plist, resolved
  `python3`, opt-out with `--no-web` or `AUTODREAM_WEB=0`.
- Port: `AUTODREAM_WEB_PORT` (default 8765). If it is taken, the server logs and exits
  nonzero, and launchd's throttle keeps it from spinning.
- `threads.html` stays as the static fallback.

## Failure matrix

| State or input | What happens | How it can fail | What the caller is told |
|---|---|---|---|
| Port in use | Server exits nonzero at start | Spin restart | launchd ThrottleInterval; log names the port |
| A night's findings are malformed | That night's summary marks the bad rows | Whole page fails | The day shows "N sessions unreadable" |
| `threads.jsonl` unreadable | Threads view shows the error | Buttons act on bad state | `threads.sh` refuses writes; the page shows its message |
| Two clicks on Close at once | Both go to `threads.sh`, which serializes on the flock | Lost update | The second sees the new state |
| POST without token or with a foreign Origin | 403 | Forged action | Nothing runs |
| Nightly running while the page is open | Progress view polls the log every 10 s | Stale view | Phase and elapsed time shown |
| Cache stale after a night is rebuilt | mtime key changes, summary is rebuilt | Old numbers | none |
| Dream markdown carries HTML or script | Rendered as text through the allowlist | Script injection | Not reachable; a test feeds it through |
| Resume when cmux is down | `threads.sh` fails | Silent no-op | The page shows the error and the brief |
| Server killed | launchd restarts it | Down | Page shows "server not reachable" |

## Delivery

1. Server, cache, Lately and Dreams, read-only. Installable and useful on its own.
2. Threads view with Close/Reopen/Resume and the token/Origin checks.
3. Progress and Stats.

## Left to the builder

- Markdown renderer (a small allowlist renderer in the page, or a vendored minimal one
  with no network loads).
- Chart drawing (inline SVG, no library).
- Exact cache file format.
