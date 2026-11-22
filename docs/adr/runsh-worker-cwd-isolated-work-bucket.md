# runsh: workers launch from an isolated cwd so Claude Code's AI-title stubs land in a bucket the runner owns and wipes

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`WORK_DIR`, `WORK_BUCKET`, `clean_work_bucket`; `probe_roots` for the primary-dir keying)

## Context
Claude Code writes a one-line `{"type":"ai-title",...}` stub into the launch cwd's session bucket even under `--no-session-persistence` (that flag only suppresses the full transcript). Run from `$HOME`, those stubs polluted the user's real session history. See CLAUDE.md, "The AI-title stub vector (second-order self-pollution)" (339 stubs between 2026-05-25 and 06-02).

## Decision
- Every `claude --print` worker reads and writes by absolute path, so its cwd is functionally irrelevant; it is pointed at `$AUTODREAM_DIR/work` (`WORK_DIR`) purely to redirect the session bucket. Claude maps the launch cwd to `~/.claude/projects/<cwd with / and . replaced by ->`, so `WORK_BUCKET` is that path under `PROJECTS_DIR`.
- `clean_work_bucket` empties the bucket before and after the run's workers, so stubs never accumulate.
- `WORK_BUCKET` stays keyed off the PRIMARY projects dir even when extra session roots are scanned: the lean workers run under the default config, so their stubs land in the default bucket, which the isolation and the wipe are built around. Scanning extra roots does not change that.

## Consequences
Do not key the bucket off a scanned root. A worker's cwd must stay `$WORK_DIR`; a new engine that ignores the cwd convention would put stubs back in a real bucket.
