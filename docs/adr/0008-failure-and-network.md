# 0008: Failure classes, network health and deferral

Status: accepted · Governs: `bin/err-cause.sh`, `bin/failure-class.sh`, `bin/run.sh`

This record holds 13 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: A failed worker leaves its evidence, and the failure is classified (omp-autodream 2026-09-04, #26)](#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26)
- [Background: A dead network or a refusing provider defers the date; it never publishes a short corpus (omp-autodream 2026-09-04, #37)](#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37)
- [a failure's cause is the first stderr line that is not blank, `hint:` or `warning:`, cleaned for markdown](#a-failures-cause-is-the-first-stderr-line-that-is-not-blank-hint-or-warning-cleaned-for-markdown)
- [a provider refusal that retrying cannot clear is detected narrowly, so a talkative transcript cannot defer a date](#a-provider-refusal-that-retrying-cannot-clear-is-detected-narrowly-so-a-talkative-transcript-cannot-defer-a-date)
- [classification checks login failures first, then size, then provider, and a bare number is not a status code](#classification-checks-login-failures-first-then-size-then-provider-and-a-bare-number-is-not-a-status-code)
- [failure classes are judged on what the worker printed, with every line `run.sh` wrote skipped by its exact text](#failure-classes-are-judged-on-what-the-worker-printed-with-every-line-runsh-wrote-skipped-by-its-exact-text)
- [when the network never came back or the provider refused, defer the date and write no report](#when-the-network-never-came-back-or-the-provider-refused-defer-the-date-and-write-no-report)
- [Time blocked on the network is summed and reported in run-stats](#time-blocked-on-the-network-is-summed-and-reported-in-run-stats)
- [network health is recorded in two scopes (L1 and L2) and L2 retries stop when there is no route](#network-health-is-recorded-in-two-scopes-l1-and-l2-and-l2-retries-stop-when-there-is-no-route)
- [The network probe reads "cannot answer" as up](#the-network-probe-reads-cannot-answer-as-up)
- [The network probe trusts the HTTP status line, written to a header file, and is bounded by a timeout binary](#the-network-probe-trusts-the-http-status-line-written-to-a-header-file-and-is-bounded-by-a-timeout-binary)
- [A dead network or a refusing provider defers the date; it never publishes a short corpus](#a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus)
- [The network gate opens when any provider answers, its cap is wall-clock, and giving up defers the date](#the-network-gate-opens-when-any-provider-answers-its-cap-is-wall-clock-and-giving-up-defers-the-date)

## Background: A failed worker leaves its evidence, and the failure is classified (omp-autodream 2026-09-04, #26)

This section was moved here from the former CLAUDE.md. Its original title: "A failed worker leaves its evidence, and the failure is classified (omp-autodream 2026-09-04, #26)".

The worker's stdout used to go to `/dev/null`, so every failure looked the same: an `.err` holding the one line `Working...` plus a hand-written sentence. On 2026-09-04 that hid a dead network behind three fine transcripts, and the report blamed their size (`oversized_errored / oversized_total` read 3/4, the number that opens issue #12). Re-run by hand against a live network, those transcripts triaged in 73 to 78 seconds. Now a failed worker's `.err` records its exit code and elapsed time and the last 40 lines of its stdout, or says plainly that stdout was empty. The `.err` and `.out` are deleted only when the worker succeeds.

- **Non-empty is not valid.** A worker that writes malformed JSON, or JSON whose `.findings` is not an array, is a failure with its evidence kept, not a success. `jq -e .findings` is truthy for a string and judges only the last value in a file, so a forged object followed by a good one passed and L2 read the first (#167). The check is `L1_FINDINGS_OK` under `jq -s` (one value, an object, a `findings` array), the same rule `merge-chunks.sh --check` applies to chunks, used on the way in (idempotency, `l1_missing_count`), on the way out and by the skill-field pass. The malformed file is removed so it cannot reach L2.
- `bin/failure-class.sh` is the single failure predicate sourced by both `run.sh` and
`bin/oversized-gate.sh`. It assigns every error stub to one of four classes from its
`.err`: `unclassified` when the file is missing, empty, or predates the
`worker exit code:` capture; `silent` for exit 0 with the exact
`worker stdout was empty` line; `provider` when the worker's own output shows a
429/auth/5xx/overload/quota refusal without a size signature; and `size` for
everything else, including context-limit signatures, timeouts, and other nonzero
exits. The worker's own output is its stderr (the top of the `.err`, before the
exit-code line) plus the captured stdout section. Every line `run.sh` writes itself is
skipped by its exact text: the timeout note, the malformed-output dump, the session-path
line, the exit-code line, the omp log tail and the network notes. A session path or a
dumped findings JSON can say `quota` or `HTTP 500` with no provider refusing anything,
and the omp log may belong to a sibling worker. The stdout section ends only at
`run.sh`'s next marker, never at a `--- ` line the worker printed itself. A number counts as a status code only after an HTTP,
status, code or error label, so `read 520 bytes` is not a 5xx; a bare code needs its
reason phrase (`503 Service Unavailable`). Words match with spaces, hyphens or
underscores, so `prompt-too-long` stays size even beside an HTTP 500.

The size and provider word lists are best-effort and will never be complete: five of the
seven review rounds on PR #26 found another phrasing. That is acceptable because of the default.
A wording neither list knows lands in `size`, which is the owner's decision (2026-09-15):
a session is only counted once its byte size is over the threshold, so an unexplained
failure there is a size failure. Add a wording when a real `.err` shows one, with a
matrix row in `test_failure_class_provider_matrix`; do not grow the lists speculatively.

`run.sh` and `bin/oversized-gate.sh` look for the classifier next to themselves, then next
to the file their symlink points at, then in `AUTODREAM_DIR`. An install made before this
file existed has a link for every other script but not this one, and updating the
checkout must not break its nightly.

`run.sh` records silent, provider, and unclassified counts beside both
`l1_findings_with_error` and `oversized_errored`. The #12 share removes all three
classes from its numerator and denominator, so only failures with no better
explanation count against size. On 2026-09-13 the raw ratio read 6/7 while every
failed worker had died in omp's first-turn memory recall; the classified window now
reports that it measured nothing about size. `bin/oversized-gate.sh` recomputes all
four classes from artifacts even when `run-stats.txt` predates the counters. It also
skips any date whose stats read `network_deferred: yes`, because those runs counted
oversized sessions that never reached a worker and their share reads low (Codex
review of 2400815).

## Background: A dead network or a refusing provider defers the date; it never publishes a short corpus (omp-autodream 2026-09-04, #37)

This section was moved here from the former CLAUDE.md. Its original title: "A dead network or a refusing provider defers the date; it never publishes a short corpus (omp-autodream 2026-09-04, #37)".

A report written from a run that could not reach the model looks complete, ships open questions, and its own self-audit cannot tell the corpus is missing. So:

- `wait_for_network` runs before every L1 round (round 1 included) and returns 1 once `AUTODREAM_NETCHECK_CAP` is spent. The run then sets `NET_DEFERRED=yes`, writes no report and exits 1, so `unassembled_dates()` names the date and a later trigger retries it.
- A worker failure probes `curl` once. No route, or a permanent provider refusal (`provider_is_permanent` in `failure-class.sh`: no balance or quota, Z.ai 1113, DeepSeek 402), is ledgered in `l1-netdown.txt` as `<hash> <round> true|provider` and gets no metadata stub. A stub fills the slot, so the session would never be retried.
- Only the LAST round that dispatched decides the deferral, so one transient flap is ridden out by the next round. A curl that is absent or not executable (exit 127/126) is "cannot tell", never "down".
- `run-stats.txt` carries `network_down_seconds`, `network_deferred`, `network_flapped`, and after L2 `network_down_seconds_l2` / `network_deferred_l2` (both also on the deferral exit).
- `run.sh` appends to the caller's `PATH` instead of replacing it, so a caller (or a test) can put a shim in front.

## a failure's cause is the first stderr line that is not blank, `hint:` or `warning:`, cleaned for markdown

Status: accepted · Date: 2026-11-21 · Code: `bin/err-cause.sh` (`err_cause_line`)

### Context

`run.sh` (the changelog sections) and `bin/remote-sync.sh` (the `remote_sync_<label>_cause` key) both quote a failed tool's stderr in one line. They source this file so both quote a failure the same way. git and rsync both end their output with boilerplate that says nothing about the cause, and OpenSSH prints `Warning: Permanently added ...` before the real error. docs/adr/0014-changelog-watch.md#background-upstream-changelog-window, "Upstream changelog window", states the same rule.

### Decision

- The cause is the first line that is not blank, `hint:` or `warning:` (matched in any case). It is the first and not the last, because the last lines are the boilerplate.
- Backticks and angle brackets are swapped out (`` ` `` becomes `'`, `<` and `>` become parentheses), because they would open a code span or an HTML tag in the markdown L2 reads. Control characters are removed.
- The line is capped at 200 characters.

### Consequences

Changing to the last line, or letting `warning:` through, makes the section and the run-stats key quote advice or an SSH notice in place of the failure.

## a provider refusal that retrying cannot clear is detected narrowly, so a talkative transcript cannot defer a date

Status: accepted · Date: 2026-11-21 · Code: `bin/failure-class.sh` (`provider_is_permanent`)

### Context

Z.ai code 1113 "Insufficient balance or no resource package" refused every worker on 2026-10-01 and 2026-10-02. A refusal like that does not clear by retrying, unlike a transient 429 or 5xx. A permanent refusal is ledgered and gets no metadata stub, and the date is deferred (docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, "A dead network or a refusing provider defers the date").

### Decision

`provider_is_permanent` looks only at `worker_text_of`. A line must read like an error report (`error`, `http`, `status`, `code`, `429` or `402`) and must also match a no-balance signature (insufficient balance, quota or funds, no resource package, credit balance too low, or the JSON code 1113). DeepSeek says "Error code: 402 - Insufficient Balance". A transient 429 or 5xx is not permanent and keeps its stub.

### Consequences

The error-report requirement stops a transcript that merely talks about balances from deferring a date. A new provider's wording needs both an error-looking line and a signature added here.

## classification checks login failures first, then size, then provider, and a bare number is not a status code

Status: accepted · Date: 2026-11-21 · Code: `bin/failure-class.sh` (`classify_failure`)

### Context

An expired login under the sandbox can sit beside a context-limit line. Providers and models spell the same words with spaces, hyphens or underscores. A transcript or a log line can contain a number such as 520 with no status code behind it. docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "A failed worker leaves its evidence, and the failure is classified", records that a wording neither list knows lands in `size`, which is the owner's decision (2026-09-15).

### Decision

- A login failure is checked first and is `provider` (retriable) whatever else the output mentions, so the size rule cannot claim it.
- Size signatures come next, then provider signatures. Anything neither list knows is `size`.
- Word patterns use `[[:space:]_-]` as the separator, so `prompt-too-long` and `prompt too long` match alike.
- A bare number is not a status code: "read 520 bytes" is not a 5xx. A code counts only after an HTTP, status, code or error label, allowing the connecting words of "HTTP status code was 500". Otherwise the reason phrase has to say it.

### Consequences

Reordering the checks lets a size line hide a login failure and defers a date for the wrong reason. Add a wording only when a real `.err` shows one, with a matrix row in `test_failure_class_provider_matrix`.

## failure classes are judged on what the worker printed, with every line `run.sh` wrote skipped by its exact text

Status: accepted · Date: 2026-11-21 · Code: `bin/failure-class.sh` (`worker_text_of`)

### Context

`run.sh` builds a failed worker's `.err` in this order: the worker's stderr, then its own notes (the timeout line, the malformed-output dump, the session-path line, and the staging and sandbox lines from #169), the exit-code line, the stdout section, and finally the omp log tail and the network notes. A session path or a dumped findings JSON can say "quota" or "HTTP 500" without any provider refusing anything. docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26, "A failed worker leaves its evidence, and the failure is classified", describes the classes.

### Decision

`worker_text_of` prints only what the worker itself printed: everything before the `worker exit code:` line except the lines `run.sh` wrote, then the stdout section. Each `run.sh` line is skipped by its exact text. The stdout section ends only at `run.sh`'s next marker (the omp log line, the `curl could not be run here` line or the `no route to` line). It does not end at any `--- ` line a worker might print. The decision came out of Codex reviews of b19ec84 and 7eda1a8.

### Consequences

A new line that `run.sh` writes into the `.err` must be added to the skip list here, or the classifier reads it as worker output. docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26 warns that any new line in the `.err` would be read as worker output (before the exit-code line) or as worker stdout (after it).

## when the network never came back or the provider refused, defer the date and write no report

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `NET_DEFERRED` branch that precedes changelog collection)

### Context
L2 over a corpus known to be short produces a report that looks complete. Findings written so far stay on disk and the worker is idempotent, so a later catch-up trigger picks up exactly the sessions still missing. The idempotency guard keys on the report existing, and `unassembled_dates()` names the date until one does, so writing no report is what makes the retry happen.

### Decision
When `NET_DEFERRED = yes` the run logs the shortfall (`COUNT - MISSING` of `COUNT`), appends the two L2 network keys, cleans the work bucket and returns 1 before L2. `NET_DEFERRED` is set earlier: when `wait_for_network` gives up before a round, or when the last round that dispatched left a `true` or `provider` row in `l1-netdown.txt` with sessions still missing. The two L2 keys are appended here because the post-L2 append is jumped over, and PROMPT.md reads all four network keys, so an absent key would read as an older runner; L2 did not run, so the values are zero waits and no deferral. The test stays narrow: only a round that could not run, or whose last round failed outright, defers, never a slow or partial one. See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, "A dead network or a refusing provider defers the date".

### Consequences
Widening the condition would defer nights that are merely slow and leave days permanently unreported; narrowing it publishes short corpora. If a report is written on this path the guard stops all later retries.

## Time blocked on the network is summed and reported in run-stats

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`NET_DOWN_SECONDS`, `wait_for_network`)

### Context
On 2026-09-04 the self-audit could not tell an outage from a transcript problem and blamed 90 minutes of dead network on oversized transcripts.

### Decision
`NET_DOWN_SECONDS` accumulates the seconds this run spent blocked on `wait_for_network`, summed across rounds, and is written to `run-stats.txt` as `network_down_seconds` (`network_down_seconds_l2` is appended after L2 with the seconds spent during it) so the self-audit can tell the two apart. Down time runs from the first failed probe to the one that answered; a healthy first probe adds nothing.

See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, "A dead network or a refusing provider defers the date" (run-stats keys).

### Consequences
The counter must be added to on every exit path of `wait_for_network` that waited (the cap path and the recovery path both do).

## network health is recorded in two scopes (L1 and L2) and L2 retries stop when there is no route

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `network_*` keys in the `run-stats.txt` block, the deferral branch before changelog collection, the L2 retry loop and the post-loop probe)

### Context
- `run-stats.txt` is closed before L2 runs, so the L2 side is appended after the aggregator loop as `network_down_seconds_l2` / `network_deferred_l2`.
- `network_down_seconds` is time the runner spent blocked BETWEEN rounds; the per-worker ledger (`l1-netdown.txt`) is one curl at the instant a worker failed. A flapping network makes the first large and the second false for every worker, which is not a contradiction; `network_flapped: yes` is emitted when the former is positive and no worker saw a `true`.
- PROMPT.md reads all four network keys. The deferral exit jumps over the post-L2 append, and an absent key cannot be told from an older runner, so the deferral branch writes `network_down_seconds_l2: 0` and `network_deferred_l2: no` itself (L2 did not run: zero waits, no deferral).
- Between L2 attempts, spending the remaining attempts against a host with no route produces nothing but a later exit, so `wait_for_network` failing sets `NET_DEFERRED=yes` and breaks out.
- The last attempt is classified too: the probe in the retry loop only runs between attempts, so a route that dropped before the final attempt was never seen and the run would record `network_deferred_l2: no`. The probe runs only when L2 failed; a delivered report needs no explanation.

### Decision
`NET_DOWN_SECONDS_PRE_L2` is captured when the run-stats block closes; after the L2 loop `network_down_seconds_l2` is `NET_DOWN_SECONDS - NET_DOWN_SECONDS_PRE_L2` and `network_deferred_l2` is the final `NET_DEFERRED`. The deferral branch (taken when L1 left the date deferred) appends `0` / `no`, calls `clean_work_bucket` and returns 1 before any L2 attempt. Both L2 network checks use `l2_probe_url`. See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37.

### Consequences
Removing the explicit zero/no append on the deferral path makes the keys vanish exactly when a reader most needs them. The L2 probe is gated on `AUTODREAM_NETCHECK` (tests set it to 0).

## The network probe reads "cannot answer" as up

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`net_up`)

### Context
No URL, or a `curl` that cannot run at all (exit 127 not found, 126 found but not executable), means the check cannot answer; it does not mean the host is down. Reading that as down made a machine without curl wait out the full cap and defer a healthy run, every run, for a reason nothing reported.

### Decision
`net_up` returns up when called with no URL, and when `curl` exits 127 or 126. The test is on the exit status, not `command -v`, which also covers a curl that is present but unrunnable. Bias is to up: a wrong "up" costs one round of workers, a wrong "down" costs the whole date.

### Consequences
Do not "fix" this to report down when curl is missing. A worker that does need a dead route fails and is classified as an outage by its own probe (see `wait-for-network-any-provider-and-wall-clock-cap` and `l1-failed-worker-network-and-provider-verdict`). `tests/run-all.sh` extracts `net_up()` with `sed -n '/^net_up() {/,/^}/p'`, so it must stay a top-level function ending in a column-0 `}`.

## The network probe trusts the HTTP status line, written to a header file, and is bounded by a timeout binary

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`net_up`)

### Context
A network filter can hold curl in `close()` after the reply has already arrived (found at the 2026-10-03 cutover: Little Snitch on this host). curl then prints nothing and its own `--max-time` cannot interrupt a `close()`, so the probe read a healthy network as down and the run waited out the whole cap.

### Decision
curl writes the status line to a header file (`-D "$hdr"`) the moment it arrives, so a reply counts (`grep '^HTTP/'`) even when curl never gets to report it. A `TIMEOUT_BIN` (`-k 2 <limit>`) bounds the stall when one exists. curl's own `--max-time` is `min(5, limit)`, so it never exceeds the probe's limit and a host without a timeout binary is bounded too.

### Consequences
Keep all three signals (status code, header file, curl exit status) in `net_up`; dropping the header file reintroduces the false "down".

## A dead network or a refusing provider defers the date; it never publishes a short corpus

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: the `wait_for_network` check at the top of each L1 round, and the deferral block after the round loop)

### Context
A report written from a run that could not reach the model looks complete, ships open questions, and its own self-audit cannot tell the corpus is missing. See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, 'A dead network or a refusing provider defers the date; it never publishes a short corpus (omp-autodream 2026-09-04, #37)'. The overnight failure is a Mac that slept through its trigger, so round 1 is the round most likely to run at a host with no route.

### Decision
- `wait_for_network` is checked BEFORE dispatching every round, round 1 included. When it fails, `NET_DEFERRED=yes`, `NET_DEFERRED_CAUSE=network`, and the loop breaks. The run then stops before L2 and writes no report, so the date stays unassembled and a later catch-up trigger retries it.
- The outage question is decided AFTER the retry budget, not during it: one transient DNS timeout mid-round is ridden out on the next round and must not defer the date. Both conditions are required: sessions are still missing, AND the last round that dispatched (`LAST_ROUND_RUN`) has a `true` or `provider` row in `l1-netdown.txt`. A run that recovered is never deferred, however bad round 1 was. `NET_DEFERRED_CAUSE` becomes `provider` when a `provider` row exists.

### Consequences
- Moving the decision into the round loop turns every flap into a deferred night.
- Dropping the "still missing" condition defers recovered runs.
- The stop itself (log the shortfall, append `network_down_seconds_l2: 0` and `network_deferred_l2: no`, clean the work bucket, return 1 before L2) is recorded in `defer-date-when-network-or-provider-fails`. `NET_DEFERRED` is also set later by the L2 retry loop (`wait_for_network "$(l2_probe_url)"` between attempts), a separate trigger of the same flag. A `staging` row in `l1-netdown.txt` is checked first and is a fatal, not a deferral.
- Related: `l1-setup-failure-is-fatal-not-deferral` (a runner that cannot set up its workers is not an outage).

## The network gate opens when any provider answers, its cap is wall-clock, and giving up defers the date

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_probe_urls`, `l2_probe_url`, `wait_for_network`)

### Context
- A dead route to one provider must not hold back sessions that run on another. A worker that does need the dead one fails, is classified as an outage by its own probe, and defers the date through the existing path.
- The cap used to count only the sleeps, so each probe (up to `AUTODREAM_NETUP_LIMIT`) ran past the bound it was handed, and a hung one was only noticed after it returned.
- A non-numeric cap makes every `[ "$elapsed" -ge "$cap" ]` test error out, and an erroring test reads as false, so the give-up branch became unreachable and the bound that was supposed to limit the wait removed it instead.
- Giving up used to `return 0` ("proceeding anyway"). That dispatched a full round of workers at a host with no route, which fails every one of them in about 9s and burns a retry round to learn nothing.
- A fixed 15s sleep step meant any cap below 15 still waited a full 15 seconds, so the wait overran its bound and reported a `network_down_seconds` larger than the configured maximum.

### Decision
`l1_probe_urls` yields one URL per distinct provider, from `AUTODREAM_L1_PROBE_URLS`, the per-source map resolved against each source's L1 engine (`AUTODREAM_L1_ENGINE_<NAME>`): an omp source on the claude engine needs anthropic. It is empty when no adapter has a resolvable provider, which `wait_for_network` reads as "nothing to ask". `wait_for_network` returns up when any URL answers. The cap (`AUTODREAM_NETCHECK_CAP`, default 1800) is wall-clock and counts the probes themselves: each probe gets at most what is left of the cap, the first one always runs (so a cap of 0 still asks once), and once the cap is spent the pass stops rather than flooring every later URL at 1s (which ran the pass N-1 probes past the cap). A non-numeric cap logs and becomes 1800. Past the cap it returns 1 and the caller defers the date. The sleep step is `min(15, cap - elapsed)`.

See docs/adr/0008-failure-and-network.md#background-a-dead-network-or-a-refusing-provider-defers-the-date-it-never-publishes-a-short-corpus-omp-autodream-2026-09-04-37, "A dead network or a refusing provider defers the date; it never publishes a short corpus".

### Consequences
Do not change give-up back to `return 0`. `tests/run-all.sh` extracts `wait_for_network()` with `sed -n '/^wait_for_network() {/,/^}/p'`, so it must stay top-level and end in a column-0 `}`. See also `network-probe-biases-to-up` and `network-down-seconds-in-run-stats`.
