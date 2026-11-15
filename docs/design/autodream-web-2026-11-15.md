# Autodream web: "my life in AI"

Status: design, revised after an adversarial Fable review (findings F1 to F11), awaiting
Sam's approval (2026-11-15).

## Intent

Sam wants one always-on page on this Mac that shows his life in AI: what happened
lately across his projects and agents, every past dream, the threads he dropped and the
ideas he deferred, how autodream itself is doing, and stats over time. He wants to act
from it: resume a dropped thread in a new session, close one that is dead, reopen one
closed by mistake. (Sam, 2026-11-15: "a whole dream / AI progress dashboard, complete
with stats"; "so this kind of becomes 'my life in ai' in a way".)

The first screen answers "what happened lately" (Sam's choice over stats-first,
worklist-first and ops-first). It runs on this Mac only (Sam's choice).

## Goals

- A local web server, started by launchd and kept alive, reachable from this Mac only.
- Five views: Lately (home), Dreams, Threads, Progress, Stats.
- Working Resume, Close and Reopen on threads.
- Data read from what autodream already writes; no second pipeline.

## Non-goals

- Access from other machines or the phone.
- A database, a frontend build step, or new runtime dependencies.
- Editing dreams or findings from the page.

## Anti-goals

- A page or process other than Sam's browser on this Mac that can start a session,
  change the index, or read his goals and transcript paths.
- A second writer to `threads.jsonl`. Every change goes through `threads.sh`.
- A third definition of report parsing, "dropped", or the thread renderer.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | **Python stdlib `ThreadingHTTPServer` + static JS files** (picked) | `python3` is already required. No packages, no build. |
| B | Bun or Node app with a framework | A toolchain and a build step for five views. |
| C | Static site regenerated nightly, plus an action endpoint | Cannot show a run in progress; still needs a server for the buttons. |

## Shape

```
 launchd: <nightly label>-web  (KeepAlive, ThrottleInterval 60)
   └─ bin/autodream-web.py  bound to 127.0.0.1:<port>, ThreadingHTTPServer
        GET  /login?t=<token>        sets the session cookie, redirects to /
        GET  /                       web/index.html + web/app.js + web/threads.js
        GET  /api/lately?days=7      timeline by project and day
        GET  /api/dreams             dates; /api/dreams/<YYYY-MM-DD> → markdown
        GET  /api/threads            thread list with dropped computed
        GET  /api/progress           live run state
        GET  /api/stats              per-night series
        POST /api/threads/<id>/{close,reopen,resume}  → threads.sh
 autodream-web open                  prints or opens http://127.0.0.1:<port>/login?t=<token>
```

## Security (F2, F3, F4)

The server binds `127.0.0.1` and refuses any other address.

| Layer | Rule |
|---|---|
| Credential | A random token in `$AUTODREAM_DIR/web-token` (0600). `GET /login?t=<token>` sets an `HttpOnly; SameSite=Strict; Path=/` cookie and redirects. Every request, GET included, needs that cookie; nothing else carries the token. `autodream-web open` (a local command) opens the login URL. |
| Host | Every request must have `Host: 127.0.0.1:<port>`, or the server answers 421. This blocks DNS rebinding. `localhost` is redirected to `127.0.0.1`. |
| CSRF | POSTs also need `Origin: http://127.0.0.1:<port>` and a constant `X-Autodream: 1` header, which a cross-site form cannot send. |
| CSP (HTTP header) | `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`. No inline script. |
| Rendering | Dreams, goals, titles and log lines are untrusted (they quote transcripts and model output). Markdown is rendered to DOM nodes with `textContent`; an allowlist of block and inline tags; links only `http:`/`https:`; HTML comments hidden; `<repo>`-style text printed literally. |
| Inputs | Thread ids match `^t-[0-9a-f]{8}$`; dream dates match `^\d{4}-\d{2}-\d{2}$` (the dreams dir also holds `.stale-*` files). Actions run `threads.sh` with an argv list and a timeout, never a shell string. |
| Output | `/api/stats` returns an allowlist of run-stats keys; `login_*` and other account lines never leave the server. |

Cookies ignore ports, so another local server on 127.0.0.1 would receive this cookie.
That server is already code running as Sam on this Mac, which this design does not
defend against; the cookie only keeps web pages out.

## Resume (F1)

`threads.sh resume --launch` currently runs `exec claude` in the caller, which from a
launchd process would open no window. It gains the cmux surface `review.sh` already uses
(`workspace create --cwd --command` with `%q` quoting and an exit-code check). `CMUX_BIN`
and `CLAUDE_BIN` are pinned in the web agent's plist, as for the review agent. A thread
already being resumed (a marker under `$AUTODREAM_DIR/resume/` younger than 2 minutes)
is not launched twice. With cmux unavailable, the response says so and returns the brief
to copy.

## Data (F5, F6, F7, F8, F11)

| View | Source | Rule |
|---|---|---|
| Lately | findings JSON + stats sidecar per session; `threads.jsonl`; newest dream | Top-level sessions only (80% of last week's 935 sessions are nested workers). Goal = `underlying_goal`, else first `notable_initiatives`. Temp-dir and worktree buckets fold into their repo, with the same rule the linker uses. Nights before 2026-07-17 have no outcome and before 07-20 no goal: they show "not measured", never zero. Open-question count comes from `bin/report-format.sh`, not a new parser. |
| Dreams | `dreams/YYYY-MM-DD.md` | Rendered client-side under the allowlist above. |
| Threads | `threads.sh list --json` | Today it takes 15.5 s for 596 threads (`threads_annotate` spawns processes per thread). It becomes one jq call, and "dropped" gets one definition shared by `threads.sh` and `threads-render.py`. The Threads view reuses `threads.html`'s rendering code with the buttons wired, not a second UI. |
| Progress | `locks/run-<date>.lock` (pid and start) for liveness and elapsed time; the last log line shown as text | Phase parsing is cut: the log has no dates and a killed run's last line stays forever. |
| Stats | `run-stats.txt` (allowlisted keys), sidecars, `categories.tsv` | "Dropped vs done over time" is cut: the index has no per-status dates. "Finished that day" means a done thread whose `last_seen` is that day, and the page says so. |

**Cache.** An in-memory map per night, keyed by the mtime and size of each file the
summary read (the dir mtime misses in-place appends to `run-stats.txt`). A full rebuild
reads 15,833 findings JSONs and 12,568 sidecars (25.4 MB) in 3.75 s warm, measured; the
last 7 nights take 0.14 s. No on-disk cache.

## Running (F9)

- `install.sh` provisions `<nightly label>-web` like the review agent, skipped when the
  nightly label is refused, with opt-out `--no-web` / `AUTODREAM_WEB=0`.
- Port `AUTODREAM_WEB_PORT` (default 8765). A taken port posts `notify.sh --warning` once
  and the agent exits 0, so launchd stops instead of respawning forever.
- Every subprocess has a timeout. A Close that hits the flock's 3-second retry budget
  answers "busy, retry" (409), never a silent no-op.

## Failure matrix

| State or input | What happens | How it can fail | What the caller is told |
|---|---|---|---|
| Request without the cookie | 401, link to run `autodream-web open` | Leaks data | Nothing returned |
| Host other than 127.0.0.1:port | 421 | DNS rebinding reads data | Nothing returned |
| POST without Origin or `X-Autodream` | 403 | CSRF | Nothing runs |
| Page framed by another site | Blocked by `frame-ancestors 'none'` | Clickjacked Resume | Not reachable |
| Dream or goal holds HTML or script | Rendered as text | Script runs | Not reachable; a test feeds it through |
| `threads.sh` lock busy | 409 "busy, retry" | Lost click | Message on the button |
| Resume clicked twice | Second within 2 minutes refused | Two sessions | "Already resuming" |
| Resume with cmux down | No launch | Silent | Error plus the brief |
| Port in use | `notify.sh --warning`, exit 0 | Respawn loop | Banner |
| Night half-written during a run | Summary rebuilt when any file's mtime or size changes | Stale numbers | none |
| Night predates outcomes or goals | Shown as not measured | Read as zero | "not measured" |
| Server killed | launchd restarts it | Down | Page shows "server not reachable" |

## Delivery

1. Faster `list --json` with one "dropped" definition; resume through cmux. Useful on
   their own and needed by everything after.
2. Server, auth, Lately and Dreams, read-only.
3. Threads view with Close, Reopen and Resume.
4. Progress and Stats.

## Left to the builder

- The markdown allowlist renderer (in `web/app.js`).
- Chart drawing (inline SVG, no library).
