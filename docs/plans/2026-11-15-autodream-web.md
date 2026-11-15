# Autodream web implementation plan

**Goal:** Ship the approved local “my life in AI” dashboard through four PRs.

**Architecture:**

```text
launchd <nightly-label>-web
  └─ Python ThreadingHTTPServer, 127.0.0.1:8765
       ├─ existing findings, sidecars, reports, run artifacts
       ├─ threads.sh                 sole thread-state writer
       └─ static HTML/CSS/JS
            Lately → Dreams → Threads → Progress → Stats
```

**Tech Stack:** Python 3 standard library, existing jq and Bash 3.2, static JavaScript, inline SVG charts. No packages, database, or frontend build.

**Spec path:** [docs/design/autodream-web-2026-11-15.md](/Users/samuelreed/git/oss/cc-autodream/.claude/worktrees/autodream-web/docs/design/autodream-web-2026-11-15.md). Approved by Sam 2026-11-15 ("Approve, build all four"). Drafted by Codex Sol, signed off by the Claude main loop.

**Global Constraints:**

- All paths below are relative to `/Users/samuelreed/git/oss/cc-autodream/.claude/worktrees/autodream-web`.
- This is a plan only. No implementation, tests, commits, or file changes have been performed.
- Shell runs under `/bin/bash`; date/stat operations use `bin/portable.sh`. Tests use short `TMPDIR=/tmp`, outside checkouts, and portable fixture cleanup. Never call `/usr/bin/trash` in tests.
- Every subprocess has a timeout. HTTP actions use fixed executable paths and argv arrays with `shell=False`.
- Read existing artifacts. Preserve `threads.sh` as the sole thread-state writer, the shared report reader, and the existing thread UI.
- `tests/autodream-web-browser.py` is never registered in `tests/run-all.sh` and never runs in CI (Linux runners have no Chrome). It skips with exit 0 and a `SKIP: no Chrome` line when Chrome is missing, and is run locally before each PR in this plan merges. Every security and data assertion lives in the urllib-based suites, which CI runs.
- Honor all spec cuts: local access only; read-only dreams/findings; no phase parsing; no historical dropped/done series; no on-disk cache.

**Review Focus:**

```text
1. Cookie, Host, Origin, CSP, and untrusted rendering boundaries.
2. One dropped predicate; atomic state writes; bounded busy responses.
3. cmux quoting, launch acknowledgement, and concurrent resume dedup.
4. Artifact provenance, cache invalidation, and unmeasured history.
5. launchd ownership, opt-outs, restart behavior, and portable tests.
```

### Test conventions for all four PRs

Server tests launch the **real server** with port `0`, read its assigned port, and make requests with Python’s `urllib.request`. `HTTPError` responses remain inspectable. Use isolated fixture directories and mocked external executables only for cmux, Claude, notifications, and launchctl.

Proposed test-client interfaces:

```python
start_server(fixture_dir, port=0) -> ServerProcess
request(method, path, *, cookie=None, host=None,
        origin=None, headers=None, body=None) -> Response
# Response: status, headers, text, json

run_threads(args, env) -> CompletedProcess
```

Add `tests/autodream-web.sh` to the existing `_suites` registry in `tests/run-all.sh`; register new shell integration functions with `_run test_name`. Python tests use `unittest`. Browser checks use the installed Chrome through a standard-library test driver, without adding project dependencies. Keep HTTP transcripts and browser evidence under the suite’s temporary directory.

Red runs must reach the intended assertion. An import error or missing executable alone does not establish a regression. Green runs include the affected existing suites and `git diff --check`.

## PR 1: Faster thread listing and cmux resume

### Task 1.1: Consolidate dropped status and remove per-thread processes

**Files:** `bin/threads.sh`, `bin/threads-status.jq` (new), `bin/threads-render.py`, `install.sh`, `tests/threads-state.sh`, `tests/run-all.sh`.

**Interfaces:**

```text
threads.sh list [--status STATUS] [--kind KIND] [--repo PATH] [--json]
threads.sh search QUERY [--json]
threads_annotate(as_of)

bin/threads-status.jq:
  thread_display_status($as_of; $dropped_days)
  annotate_threads($as_of; $dropped_days)
```

Retain the existing list JSON array and derived `.status == "dropped"` behavior. The stored JSONL status remains unchanged. The renderer retains its `.display_status` field.

The shared predicate selects the latest relevant session by `(date, hash)`, requires stored status `open`, accepts only `not_achieved`, `partially_achieved`, or `unclear_from_transcript`, and uses a **strictly older than seven days** cutoff by default. Historical reports select sessions through their report date.

- [ ] **Failing tests:** Extend existing dropped-status coverage with deliberately inconsistent `last_seen`, same-day hash ties, future sessions in historical reports, and a large list fixture.

  ```python
  # test_threads_dropped_status_has_one_contract
  assert statuses["eight_days_old"] == "dropped"
  assert statuses["seven_days_old"] == "open"
  assert statuses["mostly_achieved"] == "open"
  assert statuses["closed_by_sam"] == "closed_by_sam"
  assert cli_status == html_display_status == report_status
  assert persisted_state_bytes == before_bytes

  # test_threads_list_uses_one_jq_process
  assert len(rows) == 600
  assert jq_invocations == 1
  ```

  Count jq invocations through a transparent executable shim that runs the real jq. This pins the spec’s process-budget requirement.

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp /bin/bash tests/threads-state.sh
  TMPDIR=/tmp /bin/bash tests/run-all.sh
  ```

  Expected: current annotation exceeds one jq invocation; inconsistent `last_seen` can make CLI and renderer disagree.

- [ ] **Implement:** Put the predicate and bulk annotation in `bin/threads-status.jq`. Make list/search perform validation, annotation, filtering, and output selection in one jq invocation. Remove `threads_is_dropped`, the renderer’s Python `display_status`, and the report’s embedded Python `dropped` predicate. Renderer/report ranking code consumes the shared annotation. Bound renderer jq calls at **10 seconds**. Install the shared jq file beside the scripts.

- [ ] **Run green:** Repeat both red commands. Retain existing malformed-state, missing-state, hash-tie, historical-report, rendering, and atomic-write assertions.

- [ ] **Commit:**

  ```bash
  git add bin/threads.sh bin/threads-status.jq bin/threads-render.py install.sh tests/threads-state.sh tests/run-all.sh
  git commit -m "perf: annotate thread status in one jq call"
  ```

### Task 1.2: Launch resume in cmux and deduplicate concurrent clicks

**Files:** `bin/threads.sh`, `tests/run-all.sh`.

**Interfaces:**

```text
threads_resume_brief(id, state)
threads_resume(id, [--launch])
threads_claim_resume(id)
threads_release_resume_claim(id, owner)

threads.sh resume ID
threads.sh resume ID --launch
```

Pin exit codes: `0` success, `75` flock unavailable, `76` already resuming, `69` cmux/Claude unavailable, `70` workspace creation failed. Preserve other existing failure behavior.

- [ ] **Failing tests:**

  ```python
  # test_threads_resume_launches_cmux_workspace
  assert cmux_argv[:2] == ["workspace", "create"]
  assert cmux_cwd == expected_repo
  assert launched_claude_permission_mode == "default"
  assert decoded_brief == expected_brief
  assert injected_shell_side_effect.exists() is False

  # test_threads_resume_deduplicates_concurrent_launches
  assert sorted(exit_codes) == [0, 76]
  assert workspace_create_count == 1
  assert retry_at_age_119.returncode == 76
  assert retry_at_age_120.returncode == 0

  # test_threads_resume_cmux_failure_returns_brief
  assert result.returncode == 70
  assert result.stdout == expected_brief
  assert failed_claim.exists() is False
  assert retry.returncode == 0
  ```

  Also cover absent cmux, missing Claude, missing transcript, and a repo path containing spaces, apostrophes, `$()`, and backticks.

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp /bin/bash tests/run-all.sh
  ```

  Expected: current `resume --launch` invokes Claude directly, creates no workspace, and provides no two-minute deduplication.

- [ ] **Implement:** Replace the caller-side `exec claude` with the `review.sh` pattern: `cmux workspace create --cwd --command`, `%q` for every interpolated command argument, and an explicit exit-status check. Bound creation with `tmo 15`.

  Store claims under `$AUTODREAM_DIR/resume/<id>`, using the existing flock to serialize claim/reclaim operations. Refuse claims younger than **120 seconds**. Release the flock before calling cmux. Remove only the caller’s failed claim; retain a successful claim for the dedup window. Return the brief on launch failures and never fall back to headless Claude.

- [ ] **Run green:** Repeat the red command and run:

  ```bash
  TMPDIR=/tmp /bin/bash tests/review-cmux.sh
  ```

- [ ] **Commit:**

  ```bash
  git add bin/threads.sh tests/run-all.sh
  git commit -m "feat: resume threads in deduplicated cmux workspaces"
  ```

## PR 2: Server, authentication, Lately, and Dreams

### Task 2.1: Establish the authenticated HTTP boundary and local command

**Files:** `bin/autodream-web.py` (new), `bin/autodream-web` (new), `tests/autodream-web.py` (new), `tests/autodream-web.sh` (new), `tests/run-all.sh`.

**Interfaces:**

```python
make_server(config, port) -> ThreadingHTTPServer
load_or_create_token(path) -> str
AutodreamHandler.do_GET(self)
AutodreamHandler.do_POST(self)
AutodreamHandler.check_host(self) -> bool
AutodreamHandler.require_session(self) -> bool
AutodreamHandler.require_write_headers(self) -> bool
run_bounded(argv, *, timeout, input=None) -> CompletedProcess
```

```text
autodream-web serve [--port PORT]
autodream-web open [--print]
GET /login?t=<token>  → cookie, 303 Location: /
GET /                → web/index.html
GET /web/app.js
GET /web/app.css
```

The shell command resolves the installation and sources trusted config with environment precedence, then invokes Python. Default port is **8765**; port `0` is accepted for ephemeral operation.

- [ ] **Failing tests:**

  ```python
  # test_web_requires_cookie
  assert unauthenticated.status == 401
  assert private_goal not in unauthenticated.text
  assert "autodream-web open" in unauthenticated.text

  # test_web_rejects_foreign_host
  assert foreign_host.status == 421
  assert private_goal not in foreign_host.text

  # test_web_login_cookie_and_token_scope
  assert login.status == 303
  assert login.headers["Location"] == "/"
  assert "HttpOnly" in cookie_header
  assert "SameSite=Strict" in cookie_header
  assert "Path=/" in cookie_header
  assert authenticated.status == 200
  assert token_on_non_login_query.status == 401
  assert token_in_header_without_cookie.status == 401
  assert token_mode == 0o600
  assert token not in server_logs

  # test_web_sets_frame_blocking_csp
  assert response.headers["Content-Security-Policy"] == EXPECTED_CSP

  # test_web_refuses_non_loopback_bind
  assert non_loopback_result.returncode != 0
  ```

  Exercise the Host check with both valid and absent cookies. Allow only an exact `localhost:<actual-port>` **GET redirect** to the canonical address, with no private response body; other noncanonical Hosts receive 421.

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web.py
  ```

  Expected: the started service does not yet satisfy the authentication and HTTP-header contract.

- [ ] **Implement:** Bind exclusively to `127.0.0.1`. Generate a **32-byte random token** once at `$AUTODREAM_DIR/web-token`, using exclusive creation and mode `0600`. Use constant-time token comparison.

  `/login` is the credential-bootstrap exception. All other GETs, assets, API routes, and POSTs require the session cookie. Accept the token only in `/login?t=...`; redact query strings from logs.

  Set this exact CSP on served responses:

  ```text
  default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self';
  connect-src 'self'; frame-ancestors 'none'; base-uri 'none';
  form-action 'self'
  ```

  POST additionally requires exact canonical Origin and `X-Autodream: 1`. Use a fixed static-file route map, private-response `Cache-Control: no-store`, and no permissive CORS headers. Default subprocess timeout is **10 seconds**.

- [ ] **Run green:** Repeat the red command, then:

  ```bash
  TMPDIR=/tmp /bin/bash tests/autodream-web.sh
  TMPDIR=/tmp /bin/bash tests/shard.sh
  ```

- [ ] **Commit:**

  ```bash
  git add bin/autodream-web.py bin/autodream-web tests/autodream-web.py tests/autodream-web.sh tests/run-all.sh
  git commit -m "feat: add authenticated loopback web server"
  ```

### Task 2.2: Build artifact summaries, Lately, and safe Dreams rendering

**Files:** `bin/autodream_web_data.py` (new), `bin/autodream-web.py`, `bin/report-format.sh`, `web/index.html` (new), `web/app.js` (new), `web/app.css` (new), `tests/autodream-web-data.py` (new), `tests/autodream-web-browser.py` (new), `tests/autodream-web.py`, `tests/autodream-web.sh`.

**Interfaces:**

```python
NightCache.summary(date) -> dict
NightCache.fingerprint(date) -> tuple
build_night_summary(date, paths) -> dict
repo_for_project(project, cwd, thread_references) -> str
read_open_questions(report_path) -> int | None
lately(days=7) -> dict
dream_dates() -> dict
read_dream(date) -> dict
```

```text
/bin/bash bin/report-format.sh open-questions REPORT
GET /api/lately?days=7
GET /api/dreams
GET /api/dreams/<YYYY-MM-DD>
```

Pin responses:

```json
{
  "days": 7,
  "timeline": [{
    "date": "2026-11-14",
    "projects": [{
      "project": "-repo",
      "repo": "/repo",
      "sessions": [{
        "hash": "0123456789ab",
        "goal": "Ship a feature",
        "outcome": "partially_achieved",
        "user_messages": 4,
        "tool_calls": 12,
        "duration_minutes": 8
      }]
    }]
  }],
  "threads": {"open": 1, "dropped": 2, "ideas": 1},
  "newest_dream": {"date": "2026-11-14", "open_questions": 2}
}
```

```json
{"dates":["2026-11-14","2026-11-13"]}
```

```json
{"date":"2026-11-14","markdown":"# Autodream ...","open_questions":2}
```

Missing measurements are JSON `null`, rendered as **“not measured.”**

JavaScript interfaces:

```javascript
renderMarkdown(markdown) → DocumentFragment
renderLately(data)
renderDream(data)
loadView(view, date)
```

- [ ] **Failing tests:**

  ```python
  # test_web_lately_excludes_nested_and_folds_repos
  assert returned_hashes == [top_level_hash]
  assert worktree_repo == main_repo
  assert temp_worktree_repo == main_repo
  assert goal_with_fallback == first_notable_initiative

  # test_web_legacy_measurements_are_not_zero
  assert before_july_17["outcome"] is None
  assert before_july_20["goal"] is None
  assert missing_recent_goal["goal"] is None
  assert "not measured" in rendered_text

  # test_web_cache_rebuilds_after_artifact_changes
  assert after_stats_append["tool_calls"] == 12
  assert after_same_size_rewrite["tool_calls"] == 21
  assert after_new_finding["session_count"] == 2
  assert after_removed_finding["session_count"] == 1

  # test_web_dream_dates_and_question_reader
  assert dates == ["2026-11-14", "2026-11-13"]
  assert stale_report_name not in dates
  assert questions == 2
  assert unrecognized_legacy_questions is None
  assert traversal_response.status == 400

  # test_web_hostile_markdown_and_goal_are_inert
  assert hostile_goal in dom.text_content
  assert "<repo>" in dom.text_content
  assert hidden_comment not in dom.text_content
  assert dom.injected_script_count == 0
  assert dom.event_handler_attribute_count == 0
  assert dom.unsafe_link_count == 0
  ```

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web-data.py
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web.py
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web-browser.py
  ```

  Expected: missing endpoints, incorrect nested/history behavior, absent invalidation, and missing safe rendering.

- [ ] **Implement:** Read top-level `<12-hex>.json` findings and their matching sidecars. Determine nesting from `nested` or `isSidechain`; missing provenance remains unmeasured rather than being silently counted as top-level. Use `underlying_goal`, then the first `notable_initiatives` value. Do not apply the linker’s eligibility gate to Lately.

  Use existing `(date, hash)` thread references and `pin-projects.tsv` mappings for repository identity. For existing cwd paths, apply the linker’s physical Git common-directory rule, including bare repositories. Do not reverse dash-encoded buckets into invented paths. Keep unresolved historical buckets visible under their recorded project name.

  Add the executable `open-questions REPORT` entry point to `report-format.sh`, delegating to `report_open_questions`; retain sourcing behavior.

  Cache only in memory. Fingerprint the discovered file set and each dependency’s **mtime_ns and size**, including findings, sidecars, project mappings, reports, categories, and run-stats. Track the thread index separately. Recheck after reading; a changing or malformed file produces degraded measurement information and is retried on the next request.

  Validate dream dates with the spec regex and calendar validation. Return only exact dated `.md` files. Render markdown through DOM creation and `textContent`, with this allowlist: `h1`–`h6`, `p`, `ul`, `ol`, `li`, `blockquote`, `pre`, `code`, `hr`, `strong`, `em`, `a`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `br`. Hide HTML comments; preserve other HTML-shaped text literally. Permit only `http:` and `https:` links.

- [ ] **Run green:** Repeat all red commands, then run:

  ```bash
  TMPDIR=/tmp /bin/bash tests/report-format.sh
  TMPDIR=/tmp /bin/bash tests/autodream-web.sh
  ```

- [ ] **Commit:**

  ```bash
  git add bin/autodream_web_data.py bin/autodream-web.py bin/report-format.sh web/index.html web/app.js web/app.css tests/autodream-web-data.py tests/autodream-web-browser.py tests/autodream-web.py tests/autodream-web.sh
  git commit -m "feat: show recent activity and safely rendered dreams"
  ```

### Task 2.3: Provision the web LaunchAgent and preserve opt-outs

**Files:** `install.sh`, `bin/autodream-web.py`, `tests/install-web-agent.sh` (new), `tests/install-review-agent.sh`, `tests/install-path.sh`, `tests/install-dry-run.sh`, `tests/autodream-web.py`, `tests/run-all.sh`, `.github/workflows/launchd.yml`, `README.md`.

**Interfaces:**

```text
install.sh --no-web
AUTODREAM_WEB=0
AUTODREAM_WEB_PORT=8765
install_web_agent(label, path_val, cmux_bin, claude_bin)
```

Installed links: `autodream-web`, `autodream-web.py`, `autodream_web_data.py`, and `web/`.

- [ ] **Failing tests:**

  ```python
  # test_install_web_agent_ownership_and_options
  assert web_label == nightly_label + "-web"
  assert refused_label_launchctl_calls == []
  assert no_web_plist.exists() is False
  assert disabled_config_plist.exists() is False
  assert "--no-web" in help_text
  assert dry_run_tree_after == dry_run_tree_before

  # test_install_web_survives_review_opt_out
  assert web_with_no_review.exists()
  assert web_without_cmux.exists()
  assert review_without_cmux.exists() is False

  # test_install_web_restart_policy
  assert plist["RunAtLoad"] is True
  assert plist["KeepAlive"] == {"SuccessfulExit": False}
  assert plist["ThrottleInterval"] == 60
  assert plist_env["CMUX_BIN"] == absolute_cmux_path
  assert plist_env["CLAUDE_BIN"] == absolute_claude_path

  # test_web_port_in_use_warns_once_and_exits_zero
  assert result.returncode == 0
  assert notification_count == 1
  assert notification_argv[0] == "--warning"
  ```

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp /bin/bash tests/install-web-agent.sh
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web.py
  ```

  Expected: no web plist or opt-out handling; the port-conflict lifecycle contract is absent.

- [ ] **Implement:** Provision web as a sibling of review, **outside review’s early-return branches**. Reuse label ownership, cleaned PATH, executable resolution, XML escaping, plist linting, and bootstrap error handling. Pin absolute Python, cmux, and Claude paths when available. Missing launch tools leave read-only views available and make Resume report unavailable.

  Use `RunAtLoad=true`, `ThrottleInterval=60`, and `KeepAlive={SuccessfulExit:false}`. This satisfies both required outcomes: restart after a signal failure; stay stopped after the deliberate successful port-conflict exit.

  `--no-web` or environment/config `AUTODREAM_WEB=0` boots out and removes only the owned web job. Environment overrides config. A refused nightly label touches neither foreign review nor web jobs. `--no-schedule` retains its existing “do not touch launchd” meaning.

  On `EADDRINUSE`, invoke `notify.sh --warning` once with a **5-second timeout**, then exit `0`. Other startup failures remain nonzero. Update existing installer tests that assume exactly two agents. Register the new macOS suite in both the runner and launchd workflow.

- [ ] **Run green:**

  ```bash
  TMPDIR=/tmp /bin/bash tests/install-web-agent.sh
  TMPDIR=/tmp /bin/bash tests/install-review-agent.sh
  TMPDIR=/tmp /bin/bash tests/install-path.sh
  TMPDIR=/tmp /bin/bash tests/install-dry-run.sh
  TMPDIR=/tmp /bin/bash tests/autodream-web.sh
  ```

- [ ] **Commit:**

  ```bash
  git add install.sh bin/autodream-web.py tests/install-web-agent.sh tests/install-review-agent.sh tests/install-path.sh tests/install-dry-run.sh tests/autodream-web.py tests/run-all.sh .github/workflows/launchd.yml README.md
  git commit -m "feat: provision the local web LaunchAgent"
  ```

## PR 3: Threads view with Close, Reopen, and Resume

### Task 3.1: Extract the existing renderer and wire real actions

**Files:** `templates/threads.html`, `bin/threads-render.py`, `web/threads.js` (new), `web/threads.css` (new), `web/index.html`, `web/app.js`, `bin/autodream-web.py`, `tests/autodream-web.py`, `tests/autodream-web-browser.py`, `tests/threads-state.sh`, `tests/run-all.sh`.

**Interfaces:**

```javascript
mountThreads(root, data, onAction)
isInView(thread, view)
renderThreads()
performThreadAction(id, action, button)
```

Move the existing filters, counts, cards, search, and repo selection into the shared renderer. Static HTML uses its copy-command callback; the web view supplies the HTTP callback.

```text
GET  /api/threads
POST /api/threads/<id>/close
POST /api/threads/<id>/reopen
POST /api/threads/<id>/resume
```

Pin response shapes:

```json
{"threads":[{"id":"t-00000001","kind":"work","repo":"/repo","title":"Title","goal":"Goal","status":"dropped","display_status":"dropped","last_seen":"2026-11-01","sessions":[]}]}
```

```json
{"ok":true,"id":"t-00000001","action":"close"}
```

```json
{"ok":false,"error":"busy","message":"busy, retry"}
```

```json
{"ok":false,"error":"already_resuming","message":"Already resuming"}
```

```json
{"ok":false,"error":"cmux_unavailable","message":"cmux is unavailable","brief":"Resume brief ..."}
```

- [ ] **Failing tests:**

  ```python
  # test_web_actions_require_origin_and_header
  assert missing_origin.status == 403
  assert missing_header.status == 403
  assert foreign_origin.status == 403
  assert state_after == state_before
  assert workspace_create_count == 0

  # test_web_validates_action_paths
  assert malformed_id.status == 400
  assert unknown_id.status == 404
  assert unknown_action.status == 404
  assert shell_side_effect.exists() is False

  # test_web_close_reopen_use_real_threads_cli
  assert close.status == 200
  assert stored_status_after_close == "closed_by_sam"
  assert stored_done_by_after_close == "sam"
  assert reopen.status == 200
  assert stored_status_after_reopen == "open"

  # test_web_busy_thread_lock_returns_409
  assert response.status == 409
  assert response.json["message"] == "busy, retry"
  assert state_after == state_before

  # test_web_resume_twice_is_refused
  assert first.status == 200
  assert second.status == 409
  assert second.json["message"] == "Already resuming"
  assert workspace_create_count == 1

  # test_web_resume_cmux_down_returns_brief
  assert response.status == 503
  assert response.json["brief"] == expected_brief
  assert workspace_create_count == 0

  # test_web_thread_buttons_show_action_results
  assert busy_button.text == "busy, retry"
  assert closed_card.display_status == "closed_by_sam"
  assert reopened_card.display_status == "open"
  assert fallback_brief.text == expected_brief
  ```

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web.py
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web-browser.py
  ```

  Expected: thread routes/actions are absent; existing buttons only copy commands.

- [ ] **Implement:** Extract renderer code rather than copying it. Have `threads-render.py` embed the shared JS/CSS when generating the existing standalone HTML, preserving its portable single-file behavior. The web page loads external assets under the strict CSP.

  Fetch threads through `threads.sh list --json`, preserving its derived status. Actions invoke only:

  ```text
  ["/bin/bash", threads_path, "close", id]
  ["/bin/bash", threads_path, "reopen", id]
  ["/bin/bash", threads_path, "resume", id, "--launch"]
  ```

  Apply **10-second** list, **30-second** close/reopen, and **20-second** resume deadlines. Map exit `75` to HTTP 409, `76` to 409, and launch unavailability/failure to 503 with the brief. Other subprocess failures return a visible error. The existing flock retains its **three-second retry budget**.

  Disable a button while its request runs, display failures beside it, and refetch after successful mutations. A timeout says the outcome is unknown and requires refresh; it must not claim success or automatically retry a launch.

- [ ] **Run green:**

  ```bash
  TMPDIR=/tmp /bin/bash tests/autodream-web.sh
  TMPDIR=/tmp /bin/bash tests/threads-state.sh
  TMPDIR=/tmp /bin/bash tests/run-all.sh
  ```

- [ ] **Commit:**

  ```bash
  git add templates/threads.html bin/threads-render.py web/threads.js web/threads.css web/index.html web/app.js bin/autodream-web.py tests/autodream-web.py tests/autodream-web-browser.py tests/threads-state.sh tests/run-all.sh
  git commit -m "feat: wire thread actions into the shared web renderer"
  ```

## PR 4: Progress and Stats

### Task 4.1: Show live runs from lock ownership and report connectivity failures

**Files:** `bin/autodream_web_data.py`, `bin/autodream-web.py`, `web/app.js`, `web/app.css`, `tests/autodream-web.py`, `tests/autodream-web-browser.py`, `tests/install-web-agent.sh`.

**Interfaces:**

```python
read_run_lock(date, now) -> dict
read_last_log_line(date) -> str | None
progress(now) -> dict
```

```text
GET /api/progress
```

```json
{
  "runs":[{
    "date":"2026-11-14",
    "state":"running",
    "pid":1234,
    "started_at":"2026-11-15T08:15:00Z",
    "elapsed_seconds":120,
    "last_log_line":"L1 round 2 ..."
  }]
}
```

`state` is `running`, `stale`, or `starting`. Unknown elapsed time is `null`.

- [ ] **Failing tests:**

  ```python
  # test_web_progress_checks_pid_and_start
  assert live_run["state"] == "running"
  assert live_run["elapsed_seconds"] >= 0
  assert dead_pid_run["state"] == "stale"
  assert reused_pid_run["state"] == "stale"
  assert lock_without_pid["state"] == "starting"
  assert lock_bytes_after == lock_bytes_before

  # test_web_progress_never_infers_phase
  assert "phase" not in progress_row
  assert dead_run["state"] == "stale"
  assert dead_run["last_log_line"] == old_log_line

  # test_web_server_killed_shows_unreachable
  assert status_text == "server not reachable"
  assert reconnect_after_restart_succeeds is True

  # test_install_web_restart_policy
  assert plist["KeepAlive"] == {"SuccessfulExit": False}
  ```

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web.py
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web-browser.py
  ```

  Expected: no progress route or connectivity indicator.

- [ ] **Implement:** Read `locks/run-<date>.lock/pid` and `/start`. Match `run.sh`’s `kill -0` plus normalized `ps -o lstart=` check, with a **2-second** subprocess timeout. Preserve the existing live-pid fallback when no start was recorded. Never reclaim or modify locks.

  Calculate elapsed time from process start, not the log or findings-directory mtime. Show the last log line through `textContent`; do not infer phase. Poll Progress every **5 seconds** while visible. Failed fetches display **“server not reachable”** and retry on the same interval.

- [ ] **Run green:** Repeat the red commands and run:

  ```bash
  TMPDIR=/tmp /bin/bash tests/install-web-agent.sh
  ```

  On macOS, verify signal-kill/restart against an isolated test LaunchAgent, then boot it out.

- [ ] **Commit:**

  ```bash
  git add bin/autodream_web_data.py bin/autodream-web.py web/app.js web/app.css tests/autodream-web.py tests/autodream-web-browser.py tests/install-web-agent.sh
  git commit -m "feat: show live run ownership and server connectivity"
  ```

### Task 4.2: Add allowlisted nightly statistics and SVG charts

**Files:** `bin/autodream_web_data.py`, `bin/autodream-web.py`, `web/app.js`, `web/app.css`, `tests/autodream-web.py`, `tests/autodream-web-data.py`, `tests/autodream-web-browser.py`, `README.md`, `CLAUDE.md`, `codemaps/architecture.md`.

**Interfaces:**

```python
read_allowed_run_stats(path) -> dict
read_categories(path) -> list
stats() -> dict
```

```javascript
renderStats(data)
drawSeries(svg, points, label)
```

```text
GET /api/stats
```

```json
{
  "nights":[{
    "date":"2026-11-14",
    "run":{},
    "sessions":{"top_level":12,"nested":80},
    "activity":{"user_messages":40,"tool_calls":120,"duration_minutes":90},
    "outcomes":{"fully_achieved":4,"mostly_achieved":3,"partially_achieved":5},
    "categories":[{
      "category":"buggy_code_shipped",
      "severity":"all",
      "sessions":2,
      "findings":3
    }],
    "finished_that_day":2
  }]
}
```

Pin the run-stats allowlist to:

```text
sessions_found_raw, sessions_triaged, sessions_top_level, sessions_nested,
self_sessions_excluded, gated, l1_rounds_used, l1_rounds_max, l1_timed_out,
l1_missing_after_retries, l1_findings_with_error, l1_elapsed_seconds,
stats_sidecars_unparseable, overlap_measured, overlap_events,
network_down_seconds, network_deferred, network_down_seconds_l2,
network_deferred_l2, l1_served_mismatch, l1_served_unmeasured,
l1_cost_usd_estimate, l1_cost_unmeasured, l1_chunk_calls, l1_chunks_elided,
threads_linked, threads_unassigned, threads_unmeasured
```

- [ ] **Failing tests:**

  ```python
  # test_web_stats_exposes_only_allowed_keys
  assert set(night["run"]) <= ALLOWED_RUN_STATS
  assert "login_claude" not in response.text
  assert "login_omp" not in response.text
  assert account_canary not in response.text
  assert unknown_future_key not in night["run"]

  # test_web_stats_preserves_missing_measurements
  assert missing_metric is None
  assert measured_zero == 0
  assert malformed_categories is None
  assert missing_sidecar_activity is None

  # test_web_stats_categories_do_not_double_count
  assert all_severity_sessions == 2
  assert high_severity_sessions == 1
  assert chart_category_total == 2

  # test_web_finished_that_day_uses_last_seen
  assert finished_that_day == 2
  assert "Finished that day" in chart_label
  assert "done threads whose last_seen is that day" in explanation
  assert "dropped_over_time" not in response.json

  # test_web_stats_charts_keep_unmeasured_gaps
  assert svg_series_count > 0
  assert unmeasured_point_connects_line is False
  assert chart_accessible_label != ""
  ```

- [ ] **Run red:**

  ```bash
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web-data.py
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web.py
  TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 tests/autodream-web-browser.py
  ```

  Expected: absent stats endpoint/charts and missing allowlist/measurement semantics.

- [ ] **Implement:** Reuse the per-night cache and its dependency fingerprints. Parse run-stats into the fixed allowlist before constructing HTTP responses. Ignore account-related and unknown keys regardless of their value shape.

  Preserve category severity rows; use `severity=all` for category totals rather than summing overlapping rows. Sidecar aggregates must carry unavailable measurements as null. Display charts for activity, outcomes, category findings, and pipeline health using SVG DOM creation and text labels.

  Count “Finished that day” strictly as current `done` threads with `last_seen == date`; document that definition beside the chart. Do not reconstruct historical status transitions.

  Update README usage, CLAUDE operating notes, and the architecture map for the completed five-view system.

- [ ] **Run green:**

  ```bash
  TMPDIR=/tmp /bin/bash tests/autodream-web.sh
  TMPDIR=/tmp /bin/bash tests/run-all.sh
  git diff --check
  ```

  Run Linux CI as a non-root user and the macOS launchd suites. Complete the repository’s required shell/installer review gate before merge.

- [ ] **Commit:**

  ```bash
  git add bin/autodream_web_data.py bin/autodream-web.py web/app.js web/app.css tests/autodream-web.py tests/autodream-web-data.py tests/autodream-web-browser.py README.md CLAUDE.md codemaps/architecture.md
  git commit -m "feat: chart allowlisted nightly activity and pipeline stats"
  ```

## Parallel work and integration order

```text
PR 1:  1.1 → 1.2
                 │
PR 2:           2.1 → ┬─ 2.2 ─┐
                     └─ 2.3 ─┴─ read-only release
                                      │
PR 3:                                3.1
                                      │
PR 4:                                4.1 → 4.2
```

| Tasks | Parallel status | Files that determine ownership |
|---|---|---|
| 1.1 and 1.2 | Sequential | Both modify `bin/threads.sh` and `tests/run-all.sh`. |
| 2.2 and 2.3 | Parallel after 2.1, in isolated worktrees | 2.2 owns data/rendering files and report reader. 2.3 owns installer, launchd tests, workflow, and README. |
| 2.2/2.3 integration | Serialize shared-file changes | Both touch `bin/autodream-web.py` and `tests/autodream-web.py`. 2.3 adds only port-conflict behavior/tests there; apply that commit after 2.2. |
| PR 3 | After PRs 1 and 2 | Changes shared thread assets, renderer, server, and UI. |
| 4.1 and 4.2 | Sequential | Both modify data module, server, UI, and web tests. |

Each PR remains independently useful at its delivery boundary. Rebase subsequent PRs onto the preceding merged result and rerun affected checks.

## Failure-matrix coverage

| Spec state/input | Required behavior | Named test | PR |
|---|---|---|---|
| Request without cookie | 401; no private data; local-command guidance | `test_web_requires_cookie` | 2 |
| Host other than canonical address | 421; no data, apart from the specified localhost redirect | `test_web_rejects_foreign_host` | 2 |
| POST missing Origin or `X-Autodream` | 403; state and launch count unchanged | `test_web_actions_require_origin_and_header` | 3 |
| Page framed by another site | Exact CSP includes `frame-ancestors 'none'` | `test_web_sets_frame_blocking_csp` | 2 |
| Dream or goal contains HTML/script | Literal text; no injected elements, handlers, or unsafe links | `test_web_hostile_markdown_and_goal_are_inert` | 2 |
| `threads.sh` lock busy | 409 “busy, retry”; state unchanged | `test_web_busy_thread_lock_returns_409` | 3 |
| Resume clicked twice | One workspace; second request within 120 seconds refused | `test_threads_resume_deduplicates_concurrent_launches`, `test_web_resume_twice_is_refused` | 1, 3 |
| Resume with cmux down | No launch; error and copyable brief | `test_web_resume_cmux_down_returns_brief` | 3 |
| Port in use | One warning; successful exit; launchd stays stopped | `test_web_port_in_use_warns_once_and_exits_zero`, `test_install_web_restart_policy` | 2 |
| Night half-written | Rebuild after file addition/removal, mtime change, or size change | `test_web_cache_rebuilds_after_artifact_changes` | 2 |
| Night predates outcomes/goals | Null measurements displayed as “not measured” | `test_web_legacy_measurements_are_not_zero` | 2 |
| Server killed | launchd restarts; page reports connection failure until reachable | `test_install_web_restart_policy`, `test_web_server_killed_shows_unreachable` | 2, 4 |