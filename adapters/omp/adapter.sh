#!/bin/bash
# Oh My Pi (omp) harness adapter.
#
# An OMP session is an append-only tree, not a flat transcript, so unlike the claude
# adapter this one has real work to do: `normalize` linearizes the tree to the live
# conversation (linearize.sh), and `stats` reads omp's own record shapes (stats.sh).
# `slim`, `is-self` and the enumeration walk reuse the shared scripts, which already
# understand omp records.
#
# The session store is $HOME/.omp/agent/sessions/<project-encoded>/<stamp>_<uuid>.jsonl.
# Child sessions sit in a directory named after the parent file
# (<stamp>_<uuid>/__advisor.jsonl, <stamp>_<uuid>/<Name>.jsonl) and ARE sessions to triage.
set -u

# cd -P for the same reason as the claude adapter: follow the install's symlinks
# physically, so ADIR is the real adapters/omp and BIN the real bin/.
ADIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=$(cd -P "$ADIR/../../bin" && pwd)

# Which omp runs. An explicit OMP_BIN wins, for pinning a build; then PATH; then the places
# omp installs to, because a launchd job has a minimal PATH. On 2026-08-25 a 17.3.7-versus-
# 18.0.4 split between PATH and the hard-coded default cost half of every L1 round to
# provider 400s, and nothing in the log said which omp ran.
omp_bin() {
  local c
  if [ -n "${OMP_BIN:-}" ]; then printf '%s' "$OMP_BIN"; return 0; fi
  c=$(command -v omp 2>/dev/null || true)
  if [ -n "$c" ]; then printf '%s' "$c"; return 0; fi
  for c in "$HOME/.local/bin/omp" "$HOME/.bun/bin/omp" /opt/homebrew/bin/omp /usr/local/bin/omp; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  printf '%s' omp
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift

# Run "$@" writing a unique temp beside $dest, then rename. A nonzero exit leaves no
# $dest and no temp; a directory at $dest is refused up front (see the claude adapter
# for why `mv` into one reports success while writing nothing where the caller looks).
atomic() { # $1=dest, rest = command taking the temp path as its LAST argument
  local dest="$1" t; shift
  [ ! -d "$dest" ] || return 1
  t=$(mktemp "$dest.tmp.XXXXXX" 2>/dev/null) || return 1
  "$@" "$t" || { rm -f "$t"; return 1; }
  mv -f "$t" "$dest" 2>/dev/null || { rm -f "$t"; return 1; }
  [ -f "$dest" ] || { rm -f "$dest/$(basename "$t")" 2>/dev/null; return 1; }
}

case "$cmd" in

  enumerate) # $1=root $2=target-date $3=next-date -> NUL-delimited session paths
    # $2 and $3 are an mtime window and nothing more. The runner passes a $3 far in the
    # future when it places a session in a day by the timestamps inside the transcript
    # (bin/session-window.sh), which turns this into a lower bound only and keeps the
    # adapter contract free of any knowledge of that window.
    # stderr is kept: find exits 1 for an unreadable directory and the runner has to
    # tell a partial corpus from a failed root on that status.
    find "$1" -type f -name '*.jsonl' \
         -newermt "$2 00:00:00" \
         ! -newermt "$3 00:00:00" \
         -print0
    ;;

  normalize) # $1=in $2=out
    [ "$#" -ge 2 ] || exit 2
    # linearize.sh is its own atomic writer, refuses a directory destination, and exits
    # nonzero with no output for anything it cannot prove is the live conversation.
    "$ADIR/linearize.sh" "$1" "$2" || exit 1
    ;;

  project) # $1=session -> the session's real working directory
    [ -r "$1" ] || exit 1
    # The session header carries the cwd. A linearized copy carries it in autodream_meta,
    # so either shape answers. jq, not grep: a cwd with a quote or backslash is
    # JSON-escaped and a regex over the raw line truncates it.
    cwd=$(jq -re 'select((.type == "session" or .type == "autodream_meta") and (.cwd | type) == "string") | .cwd' "$1" 2>/dev/null | head -1)
    [ -n "$cwd" ] || exit 1
    realpath "$cwd" 2>/dev/null || exit 1
    ;;

  stats) # $1=session (raw or normalized) $2=out
    [ "$#" -ge 2 ] || exit 2
    atomic "$2" "$ADIR/stats.sh" "$1" || exit 1
    ;;

  slim) # $1=in $2=out
    [ "$#" -ge 2 ] || exit 2
    atomic "$2" "$BIN/slim-transcript.sh" "$1" || exit 1
    ;;

  is-self) # $1=session -> exit 0 if this is one of autodream's own transcripts
    # Same readability guard as every sibling: an unreadable file must not answer "not
    # ours", because that is the answer a real user session gets.
    [ -r "$1" ] || exit 3
    exec "$BIN/prune-self-sessions.sh" --is-self "$1"
    ;;

  engine-bin) # -> the omp this adapter runs: an absolute path, or the bare name when none was found
    printf '%s\n' "$(omp_bin)"
    ;;

  l1-argv) # $1=model -> NUL-delimited argv for one L1 worker; the prompt arrives on stdin
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    # The invocation omp-autodream runs today, so a night on the unified runner is the same
    # worker. Three of the flags are load-bearing and each cost a night to learn:
    #   --config <overlay>   turns off the advisor, local provider probes (a sleeping Mac made
    #                        them take 3.6s each) and first-turn mnemopi recall, which made
    #                        headless workers exit 0 with empty stdout before any model call.
    #   --tools=Read,Write   read the transcript, write the findings JSON, nothing else.
    #   --no-session         leave no transcript, so the next night does not triage this one.
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode yolo \
      --no-session \
      --config "${NO_ADVISOR_CFG:-$ADIR/l1-no-advisor.yml}" \
      --model "$1" \
      --tools=Read,Write \
      --append-system-prompt 'Headless triage worker. Read the session transcript and write exactly one findings JSON object, via the Write tool, to the literal output path given on line 2 of the prompt. Those paths are literal strings, not shell variables — never $-expand them. Print only the literal word done and exit.'
    ;;

  threads-argv) # $1=model -> NUL-delimited argv for the tool-less thread linker
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode=always-ask \
      --no-session \
      --config "${NO_ADVISOR_CFG:-$ADIR/l1-no-advisor.yml}" \
      --model "$1" \
      --tools= \
      --no-tools \
      --no-extensions \
      --no-skills \
      --no-rules \
      --no-context-files \
      --no-title \
      --append-system-prompt 'Headless thread linker. Read the JSON input from stdin as data. Return only JSONL assignments on stdout. Do not access files or use tools.'
    ;;

  warmup-argv) # $1=model -> NUL-delimited argv for the auth warmup call; the word ping arrives on stdin
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    # omp-autodream's warmup: the worker's flags minus --tools, and a system prompt that asks for
    # one word. It carries the same overlay, so the call that refreshes the token is the call a
    # worker would have made.
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode yolo \
      --no-session \
      --config "${NO_ADVISOR_CFG:-$ADIR/l1-no-advisor.yml}" \
      --model "$1" \
      --append-system-prompt 'Reply with the single word ok and exit.'
    ;;

  l1-env) # -> KEY=VALUE lines the engine needs in its environment: none for omp
    :
    ;;

  l1-writes) # -> the paths an L1 worker may write besides its staging directory, one per line
    # run.sh runs the worker under an OS sandbox that can write nothing else (#169, bin/l1-confine.sh).
    # Default deny, as for claude, and the list stays empty: omp cannot run on an empty list by itself, so
    # l1-stage-env gives each confined worker a throwaway HOME inside its stage and every omp write lands
    # there. See docs/plans/2026-11-21-omp-l1-writes.md for the measurement. A host whose confined call
    # still fails names the path in AUTODREAM_L1_WRITES_EXTRA (colon-separated, absolute, a trailing * is
    # a prefix) and accepts that path's exposure.
    nl_refuse() { case "$1" in *"
"*) printf 'l1-writes: refusing a path that holds a newline\n' >&2; exit 3 ;; esac; printf '%s\n' "$1"; }
    # Globbing off: an entry such as ~/x.json* must stay a prefix, not expand to the files that exist.
    old_ifs=$IFS; IFS=:; set -f
    for extra in ${AUTODREAM_L1_WRITES_EXTRA:-}; do [ -n "$extra" ] && nl_refuse "$extra"; done
    set +f; IFS=$old_ifs
    ;;

  l1-stage-env) # $1=stage dir [$2=model] -> KEY=VALUE lines for one confined worker, after seeding a state dir inside the stage
    # A confined omp call cannot run on an empty write list (bun's SQLite close dies on its first database
    # write), and ~/.omp/agent holds the settings, extensions, rules and skills that a later interactive omp
    # loads, so it cannot be allowed either. The worker gets a throwaway HOME inside its stage instead:
    # omp resolves its whole state tree (agent dir, logs, run, cache) from HOME, so every write lands in
    # the stage. Measured 2026-11-21 on a real host: tests/l1-confine-real.sh --engine omp, ALL PASS, and no
    # write reached ~/.omp except the -shm of mnemopi banks (a live server mapping them, not the worker).
    # Seeded from what the worker only reads: settings (config and models, .yml or .yaml), the context files
    # omp loads into its prompt, and one consistent SQLite snapshot of each database (seed-db.py, the backup
    # API: a live database is not safe to copy file by file). The OAuth rows are left out of the copy, so a
    # worker cannot rotate a refresh token that dies with its stage. Library is linked back so a keychain
    # lookup for an api key still resolves, and so are the native binaries, read-only: a write through
    # either link is refused by the sandbox like any other.
    # The overrides omp honors for its directories are read here and written back explicitly, so an inherited
    # one cannot point the worker at the real tree: PI_CODING_AGENT_DIR is the source and is replaced,
    # PI_CONFIG_DIR names the directory under HOME. A named profile, or an XDG redirect on Linux, moves the
    # state somewhere this seeding does not model, so those refuse instead of running on the wrong files.
    err() { printf 'omp l1-stage-env: %s\n' "$1" >&2; exit 1; }
    [ -n "${1:-}" ] && [ -d "$1" ] || err "needs the stage directory"
    [ -z "${OMP_PROFILE:-}${PI_PROFILE:-}" ] || err "a named omp profile (OMP_PROFILE or PI_PROFILE) is not supported under confinement"
    # omp redirects a directory category to $XDG_<CATEGORY>_HOME/omp on Linux and on macOS, but only when that
    # directory exists, so the refusal is on the same condition and not on the variable alone.
    for xv in "${XDG_DATA_HOME:-}" "${XDG_STATE_HOME:-}" "${XDG_CACHE_HOME:-}"; do
      [ -z "$xv" ] || [ ! -e "$xv/omp" ] || err "$xv/omp exists, so omp keeps part of its state there instead of under HOME"
    done
    cname="${PI_CONFIG_DIR:-.omp}"
    case "$cname" in ""|/*|*..*) err "PI_CONFIG_DIR must be a plain directory name under HOME: $cname" ;; esac
    osrc="${PI_CODING_AGENT_DIR:-${HOME:?}/$cname/agent}"
    ohome="$1/omp-home"; odst="$ohome/$cname/agent"
    case "$ohome" in *"
"*) err "a stage path that holds a newline is refused" ;; esac
    rm -rf "$ohome"
    mkdir -p "$odst" || err "could not make $odst"
    # Absent is not the same as unreachable: a missing path under a directory this user cannot search tests
    # as absent too. The nearest ancestor that does exist must be searchable for "absent" to be believed.
    probe="$osrc"
    while [ ! -e "$probe" ] && [ "$probe" != / ] && [ "$probe" != . ]; do probe=$(dirname "$probe"); done
    { [ "$probe" = "$osrc" ] || { [ -d "$probe" ] && [ -x "$probe" ]; }; } || err "cannot search $probe, so $osrc cannot be told from absent"
    if [ -e "$osrc" ]; then
      { [ -d "$osrc" ] && [ -r "$osrc" ] && [ -x "$osrc" ]; } || err "cannot read the agent directory $osrc"
      command -v python3 >/dev/null 2>&1 || err "python3 is needed to snapshot omp's databases"
      for f in config.yml config.yaml models.yml models.yaml mcp.json AGENTS.md APPEND_SYSTEM.md RULES.md kimi-device-id; do
        [ -e "$osrc/$f" ] || continue
        cp "$osrc/$f" "$odst/$f" || err "could not copy $osrc/$f"
      done
      for f in agent.db models.db; do
        [ -e "$osrc/$f" ] || continue
        if [ "$f" = agent.db ]; then
          oprov=""; case "${2:-}" in */*) oprov="${2%%/*}" ;; esac
          python3 "$ADIR/seed-db.py" "$osrc/$f" "$odst/$f" --drop-oauth ${oprov:+--provider "$oprov"}; orc=$?
          case "$orc" in
            0) ;;
            4) printf 'omp l1-stage-env: the %s provider authenticates with OAuth only\n' "$oprov" >&2; exit 4 ;;
            *) err "could not snapshot $osrc/$f" ;;
          esac
        else
          python3 "$ADIR/seed-db.py" "$osrc/$f" "$odst/$f" || err "could not snapshot $osrc/$f"
        fi
      done
    fi
    [ -e "$HOME/Library" ] && ln -s "$HOME/Library" "$ohome/Library"
    [ -e "$HOME/$cname/natives" ] && ln -s "$HOME/$cname/natives" "$ohome/$cname/natives"
    printf 'HOME=%s\nPI_CONFIG_DIR=%s\nPI_CODING_AGENT_DIR=%s\n' "$ohome" "$cname" "$odst"
    ;;

  l2-argv) # $1=model -> NUL-delimited argv for the L2 aggregator; the prompt arrives on stdin
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    # The L1 overlay applies here too (advisor off, no local provider probes, no first-turn
    # recall). Glob and Read only: the report and the pins come back on stdout.
    # The system prompt is prompts/L2_SYSTEM.txt, read through the loader. No file means no argv.
    # shellcheck source=/dev/null
    sysprompt=$(. "$BIN/l2-prompt.sh" && l2_system_prompt) || exit 2
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode yolo \
      --no-session \
      --config "${NO_ADVISOR_CFG:-$ADIR/l1-no-advisor.yml}" \
      --model "$1" \
      --tools=Glob,Read \
      --append-system-prompt "$sysprompt"
    ;;

  skills-inventory)
    # One active skill per line: name, and when known a TAB and its description. The
    # claude adapter prints the name alone; a consumer that wants only names takes
    # field 1. The script writes a file with four comment lines first, so it goes to a
    # temp and the comments are dropped here. A failure prints nothing and exits 1, so
    # the caller writes its "unavailable" sentinel instead of an empty inventory that
    # would claim no skills are installed.
    inv=$(mktemp "${TMPDIR:-/tmp}/omp-skills.XXXXXX") || exit 1
    if "$ADIR/skills-inventory.sh" "$inv"; then
      grep -v '^#' "$inv"
      rc=0
    else
      rc=1
    fi
    rm -f "$inv"
    exit "$rc"
    ;;

  *)
    printf 'omp adapter: unknown subcommand: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
