# runsh: The allowlist of operator-requested scripts is snapshotted, and the scripts run, before the first model call

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `REPORT_SNAPSHOT`, `REPORT_COLLECTOR_FP`, the collect step, `REPORT_OUT_FP`)

## Context
The collector (`bin/report-scripts.sh`) EXECUTES what `$AUTODREAM_DIR/report-scripts.conf` names. An L1 worker reads untrusted transcripts and holds the Write tool, so it could rewrite the conf (or a script the conf names, or a file such a script sources) and have the collector run the result with this user's privileges. The sha256 pins alone cannot cover files a script sources. A worker that is not confined (a host whose sandbox probe fails, `AUTODREAM_L1_CONFINE=0`, or an engine whose adapter declares no `l1-writes` profile; the comment this ADR came from said omp had none, which stopped being true when both adapters gained one) can rewrite them, and the script's own hash would still match. See CLAUDE.md, 'Report scripts: one collector so a note can ask for a command' (snapshot and "Collection runs before the first model call").

## Decision
- Before the first model call, `report_collector_fingerprint` and `report-scripts.sh snapshot` are taken and held in memory (`#unavailable` when the snapshot fails). Just before collection the collector fingerprint is checked again; a mismatch, or a missing collector, runs nothing.
- The collector runs right after, from the snapshot file, never from the live conf; each allowlisted entry runs with a timeout and a failing one still writes its file with the failure as the content. A new report is a conf line, never a change to `run.sh` or the prompt.
- Nothing has run that could have rewritten a script when it executes. What a worker can still reach is the files the step wrote into the findings dir, so the runner hashes them (`report_output_fingerprint`), holds the hashes in memory and checks them again before L2 reads anything.
- A collector that cannot run costs a log line and an `unavailable` index (`report_scripts_unavailable`). The run stops (`log_fatal`) only when the earlier run's report files cannot be cleared.

## Consequences
- Do not move collection after L1: a script would then report the state after untrusted workers had run, and its sourced files could have been rewritten.
- A script reports the machine as of the start of the run, minutes earlier than when collection followed L1.
- Do not read the live conf in `collect` during a run.
