# run.sh: usage and environment knobs

Moved out of the header of `bin/run.sh` (the knobs are read there, and the code is the authority when this text disagrees).

```
Autodream runner — invoked by launchd at ~3am local time.

Two-layer pipeline:
  L1: For each of yesterday's session JSONLs, spawn a parallel `claude --model claude-haiku-5-5`
      running SESSION_TRIAGE.md → writes one findings.json per session.
  L2: One `claude` (CLI default model) running PROMPT.md with Glob and Read only → reads
      all findings JSONs and prints the report on stdout, ending with AUTODREAM_REPORT_END,
      then an optional AUTODREAM_PINS_BEGIN/END block. run.sh is the only writer: it strips
      the sentinel into $DREAMS_DIR/YYYY-MM-DD.md, writes pins.jsonl from the block, and
      stores the pins in Mnemopi via apply-pins.sh.

Usage:
  ./run.sh             # process yesterday
  ./run.sh 2026-05-24  # process a specific date
  FANOUT=4 ./run.sh    # tune L1 parallelism (default 8)

Environment overrides (all optional):
  CLAUDE_BIN     path to claude CLI                   default: $HOME/.local/bin/claude
  PROJECTS_DIR   single root: where session JSONLs live (kept for compat; one root)
                 default: $HOME/.claude/projects
  SESSION_ROOTS  colon-separated dirs to scan for session JSONLs. Takes precedence
                 over PROJECTS_DIR. If neither is set, every $HOME/.claude*/projects
                 that exists is scanned (primary always first) — each CLAUDE_CONFIG_DIR
                 profile keeps its own projects/ bucket, so one-dir scanning silently
                 missed sessions recorded under ~/.claude-nous, ~/.claude-ds4, ...
  AUTODREAM_DIR  scripts + prompts + state           default: $HOME/.claude/autodream
  DREAMS_DIR     where final reports are written     default: $HOME/.claude/dreams
  FANOUT         L1 parallelism                      default: 8
  AUTODREAM_CHANGELOG  set 0 to skip the upstream-changelog check  default: 1
  AUTODREAM_CHANGELOG_SOURCES  override the watched harnesses. Semicolon-separated
                       records of name|remote|path-in-repo|cache-dir. Default watches
                       Claude Code, Codex and OMP (OMP is a monorepo with no root
                       CHANGELOG, hence the per-source path). CHANGELOG_REMOTE selects
                       one source alone and suppresses the others.
  AUTODREAM_CHANGELOG_MAX_LINES  per-source cap on inserted lines          default: 400
  CLAUDE_CODE_REPO     persistent cache for the claude-code clone  default: $AUTODREAM_DIR/cache/claude-code
  CHANGELOG_REMOTE     git remote to clone/pull       default: https://github.com/anthropics/claude-code.git
  AUTODREAM_L1_ROUNDS  max L1 retry rounds for missing sessions    default: 5
                       Two consecutive rounds that recover no session trip a circuit
                       breaker: the run jumps straight to the stub round rather than
                       spending the rest of the budget on an identical failure.
  AUTODREAM_L1_TIMEOUT seconds before an L1 worker is killed with     default: 1200
                       its process group; needs timeout or gtimeout on PATH.
                       Must be a positive integer (0 would disable the timeout).
                       SIGKILL follows 30s after the SIGTERM, so the worst-case
                       bound is AUTODREAM_L1_TIMEOUT + 30.
  AUTODREAM_L1_WARMUP  set 0 to skip the pre-fanout auth warmup     default: 1
                       One serial model call per adapter before the parallel dispatch, so
                       a cold OAuth token is refreshed once instead of by FANOUT workers
                       at once. Never fatal; result lands in run-stats as l1_warmup.
  AUTODREAM_L1_WARMUP_TIMEOUT seconds before the warmup is killed    default: 120
                       Must be a positive integer (0 would disable the deadline).
  AUTODREAM_L2_ATTEMPTS max L2 attempts to produce a report        default: 3
  AUTODREAM_RETRY_WAIT seconds to pause between retry rounds       default: 60
  AUTODREAM_NETCHECK   set 0 to skip waiting-for-network on retry  default: 1
  AUTODREAM_ADAPTERS   harnesses to scan: names (space/comma) or all   default: claude
                       (an adapter under adapters/ is accepted, not enabled, until named)
  AUTODREAM_FORCE      set 1 to rebuild even if a report exists    default: 0
  AUTODREAM_SLIM_BYTES sessions larger than this are slimmed for L1  default: 262144
  AUTODREAM_L1_CHUNK_BYTES  a transcript whose worker input is bigger than this is split at line
                       boundaries and read by one worker per chunk, then merged into the one
                       findings JSON per session. 0 turns chunking off and restores the head/tail
                       slim exactly. COST: every oversized session costs up to MAX_CHUNKS worker
                       calls instead of one, per round, so a night costs up to
                       (oversized sessions x MAX_CHUNKS) calls plus the rest one each; a session
                       takes up to MAX_CHUNKS x AUTODREAM_L1_TIMEOUT of wall time (its chunks run
                       in sequence in one slot)                              default: 0 (off; 300000 is
                       the value the replay in the PR was run with)
  AUTODREAM_L1_MAX_CHUNKS  most chunks read per session; over it the middle is dropped and counted
                       (l1_chunks_elided), the first half and last half are kept   default: 8
  AUTODREAM_WINDOW     set 0 to place a session in a report day by its file mtime
                       alone, as before. On (default) it is placed by the timestamps
                       INSIDE the transcript, and stats and L1 see only that day  default: 1
  AUTODREAM_L2_ENGINE  adapter whose engine runs L2, and by default reviews every source's
                       sessions in L1 too: the run's reviewer      default: the first enabled adapter
  AUTODREAM_TRIAGE     set 1 to triage each delivered report into dreams/DATE.triage.md   default: 0
                       One extra read-only call on the L2 engine and model, after everything
                       else (bin/triage-dream.sh; never fatal). Off, nothing changes.
  AUTODREAM_L2_MODEL   pin the L2 aggregator model (every engine)   default: the adapter's own (claude: the CLI default)
  AUTODREAM_L2_MODEL_<NAME> / AUTODREAM_L1_MODEL_<NAME>  the same for one engine only. Keyed by
                       the engine that makes the call, not the source: AUTODREAM_L1_MODEL_OMP is
                       the model of every L1 call on the omp engine, whichever harness holds the
                       session, and never reaches the claude CLI
  AUTODREAM_L1_ENGINE  accepted adapter whose engine reviews every source's sessions in L1
                                                                    default: the L2 engine
  AUTODREAM_L1_ENGINE_<NAME>  the same for one source only, e.g. AUTODREAM_L1_ENGINE_OMP=omp
                       Which harness holds a transcript and which engine reads it are separate:
                       the source's own adapter still enumerates, linearizes, describes and adds
                       its triage notes, and only the model call goes to the engine. A name that
                       is not an accepted adapter leaves those sessions untriaged, never on
                       another engine. The L1 model defaults to that engine's manifest l1_model.
  AUTODREAM_SESSION_ROOTS_<NAME>  colon-separated session roots for one adapter other than
                       claude, in place of its manifest's defaults   default: the manifest's
  AUTODREAM_REMOTE_ROOTS  space-separated label=ssh-target:path entries for other hosts whose
                       Claude transcripts this run pulls one way (bin/remote-sync.sh, rsync over
                       ssh with BatchMode) into $AUTODREAM_DIR/remote/<label>/projects and scans
                       with the claude roots, e.g. "studio2=studio2:.claude/projects". The label is
                       [A-Za-z0-9._-]+. A host that fails is a run-stats line, never a deferred
                       date; every host failing posts one warning   default: unset (off)
  AUTODREAM_REMOTE_LOCK_WAIT  seconds to wait for another run that is syncing the same host
                       before scanning its mirror as it stands (skipped_locked)   default: 600
  AUTODREAM_REQUIRE_LOGIN  space-separated key=value pairs the login of every engine the run uses
                       must match before it is handed anything; keys provider, auth, plan,
                       account, as the engine's whoami verb reports them (claude: claude auth
                       status). An L1 engine that fails triages nothing; a failing L2 engine
                       stops the run before it starts      default: record only
                       (e.g. "provider=firstParty auth=claude.ai plan=max")
  AUTODREAM_LOGIN_WARN_DAYS  post a warning banner when an engine's claude.ai sign-in ends within
                       this many days; 0 turns it off                       default: 10
  AUTODREAM_L1_REQUIRE_SERVED  1 discards the findings of any L1 call answered by a model other
                       than the requested one, as the engine's served verb judges it (claude: an
                       alias such as haiku matches the claude-haiku-... id it answers as). An
                       engine with no served verb (omp) cannot be vouched for, so its calls are
                       discarded too                                  default: 0, record only
  AUTODREAM_MARKER_EPOCH    first date whose report is REQUIRED to carry the
                            open-questions marker; earlier unmarked reports are treated
                            as complete (legacy) rather than abandoned
                                                                    default: 2026-08-19
  AUTODREAM_SANDBOX_SHAPE_MIN  a session with at least this many denies signed by the sandbox-shape
                       guard is listed in the report's self-audit (rollup.tsv's sandbox_shape_denies,
                       threshold passed to L2 as run-stats sandbox_shape_denies_min)   default: 10
  AUTODREAM_MIN_USER_TURNS  noise-gate floor on user_message_count  default: 2
  AUTODREAM_MIN_MINUTES     noise-gate floor on duration_minutes    default: 1
  AUTODREAM_STATS_BIN       override the resolved session-stats.sh path, authoritative
                            (no existability fallback — lets tests force missing or
                            malformed stats sidecars)                default: unset
  AUTODREAM_OVERLAP_BIN     override the resolved overlap-stats.sh path, authoritative
                            (no existability fallback — lets tests force the "not
                            measured" paths)                        default: unset
  AUTODREAM_CONFIG     path to the sourced config file             default: $AUTODREAM_DIR/config
  AUTODREAM_VAULT_DIR  autodream folder inside an Obsidian/synced vault; enables the
                       inbox note surface + report publishing       default: unset (off)
  AUTODREAM_VAULT_BIN  override the resolved vault-notes.sh path, authoritative
  AUTODREAM_XBOOKMARKS_BIN override the resolved x-bookmarks.sh path, authoritative
  AUTODREAM_REPORTS_BIN    override the resolved report-scripts.sh path, authoritative
                           (the allowlist is $AUTODREAM_DIR/report-scripts.conf; the knobs
                           AUTODREAM_REPORT_TIMEOUT (60), AUTODREAM_REPORT_MAX_BYTES (100000) and
                           AUTODREAM_REPORT_KILL_GRACE (5) are read by report-scripts.sh)
  AUTODREAM_PRUNE_ROOTS    colon-separated dirs to search for repos whose finished
                           worktrees and branches are pruned     default: unset (off)
  AUTODREAM_PRUNE_BIN      override the resolved prune-worktrees.sh path, authoritative
  AUTODREAM_PRUNE_GRACE_MIN    recent-edit window in minutes                  default 720
  AUTODREAM_PRUNE_MAX          most removals in one run                       default 25
  AUTODREAM_PRUNE_CLOSED_DAYS  how long a closed PR must have been closed     default 7
  AUTODREAM_PRUNE_BUDGET_SEC   wall-clock budget for the whole run            default 1200
  AUTODREAM_PRUNE_KILL_SLACK   seconds after the budget before a hard stop    default 120
  AUTODREAM_PRUNE_CALL_SEC     timeout for one network call or trash          default 60
  AUTODREAM_PRUNE_PROTECT      extra protected branch globs, colon-separated  default none
  AUTODREAM_PRUNE_OPEN_LIMIT   open PRs read per repo; at the limit the repo
                               is kept whole                                  default 200
  AUTODREAM_PRUNE_TRASH        0 to delete with git instead of trash          default 1
  AUTODREAM_PRUNE_LEDGER       append-only record of every removal
                               default ~/.claude/autodream/prune-ledger.tsv
  AUTODREAM_PRUNE_DRY_RUN      1 is the same as --dry-run
  AUTODREAM_TRIAGE_SUGGEST 0 turns off the "repos worth triaging" list  default: on
  AUTODREAM_TRIAGE_BIN     override the resolved triage-candidates.sh path, authoritative
                           (the other AUTODREAM_TRIAGE_* knobs are in triage-candidates.sh)
```
