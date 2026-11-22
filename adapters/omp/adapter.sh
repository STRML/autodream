#!/bin/bash
set -u

ADIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=$(cd -P "$ADIR/../../bin" && pwd)
# shellcheck source=/dev/null
. "$BIN/lib-path-state.sh"

OVERLAY="$ADIR/l1-no-advisor.yml"

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
    find "$1" -type f -name '*.jsonl' \
         -newermt "$2 00:00:00" \
         ! -newermt "$3 00:00:00" \
         -print0
    ;;

  normalize) # $1=in $2=out
    [ "$#" -ge 2 ] || exit 2
    "$ADIR/linearize.sh" "$1" "$2" || exit 1
    ;;

  project) # $1=session -> the session's real working directory
    [ -r "$1" ] || exit 1
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
    [ -r "$1" ] || exit 3
    exec "$BIN/prune-self-sessions.sh" --is-self "$1"
    ;;

  engine-bin) # -> the omp this adapter runs: an absolute path, or the bare name when none was found
    printf '%s\n' "$(omp_bin)"
    ;;

  l1-argv) # $1=model -> NUL-delimited argv for one L1 worker; the prompt arrives on stdin
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode yolo \
      --no-session \
      --config "$OVERLAY" \
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
      --config "$OVERLAY" \
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
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode yolo \
      --no-session \
      --config "$OVERLAY" \
      --model "$1" \
      --append-system-prompt 'Reply with the single word ok and exit.'
    ;;

  l1-env) # -> KEY=VALUE lines the engine needs in its environment: none for omp
    :
    ;;

  l1-writes) # -> the paths an L1 worker may write besides its staging directory, one per line
    nl_refuse() { case "$1" in *"
"*) printf 'l1-writes: refusing a path that holds a newline\n' >&2; exit 3 ;; esac; printf '%s\n' "$1"; }
    old_ifs=$IFS; IFS=:; set -f
    for extra in ${AUTODREAM_L1_WRITES_EXTRA:-}; do [ -n "$extra" ] && nl_refuse "$extra"; done
    set +f; IFS=$old_ifs
    ;;

  l1-stage-env) # $1=stage dir [$2=model] -> KEY=VALUE lines for one confined worker, after seeding a state dir inside the stage
    err() { printf 'omp l1-stage-env: %s\n' "$1" >&2; exit 1; }
    [ -n "${1:-}" ] && [ -d "$1" ] || err "needs the stage directory"
    [ -z "${OMP_PROFILE:-}${PI_PROFILE:-}" ] || err "a named omp profile (OMP_PROFILE or PI_PROFILE) is not supported under confinement"
    for xv in "${XDG_DATA_HOME:-}" "${XDG_STATE_HOME:-}" "${XDG_CACHE_HOME:-}"; do
      [ -n "$xv" ] || continue
      path_state "$xv/omp"; xrc=$?
      [ "$xrc" -ne 0 ] || err "$xv/omp exists, so omp keeps part of its state there instead of under HOME"
      [ "$xrc" -ne 2 ] || err "cannot tell whether $xv/omp exists (an unreachable path), so cannot tell where omp keeps its state"
    done
    for ov in OMP_WORKTREE_DIR OMP_GITHUB_CACHE_DB OMP_COMMIT_CACHE_DB OMP_JUDGMENT_CACHE_DB OMP_AUTH_BROKER_SNAPSHOT_CACHE PI_NATIVES_DIR; do
      [ -z "${!ov:-}" ] || err "$ov is set, so omp keeps part of its state where this seeding does not look"
    done
    cname="${PI_CONFIG_DIR:-.omp}"
    case "$cname" in ""|/*|*..*) err "PI_CONFIG_DIR must be a plain directory name under HOME: $cname" ;; esac
    osrc="${PI_CODING_AGENT_DIR:-${HOME:?}/$cname/agent}"
    ohome="$1/omp-home"
    case "$ohome" in *"
"*) err "a stage path that holds a newline is refused" ;; esac
    rm -rf "$ohome"
    [ ! -e "$ohome" ] && [ ! -L "$ohome" ] || err "could not remove the previous state directory $ohome"
    obuild=$(mktemp -d "$(dirname "$1")/seed.XXXXXX") || err "could not make a build directory beside the stage"
    trap 'rm -rf "$obuild"' EXIT
    odst="$obuild/$cname/agent"
    mkdir -p "$odst" || err "could not make $odst"
    path_state "$osrc"; src_state=$?
    [ "$src_state" -ne 2 ] || err "cannot tell whether the agent directory $osrc exists (an unreachable path)"
    if [ "$src_state" -eq 0 ]; then
      { [ -d "$osrc" ] && [ -r "$osrc" ] && [ -x "$osrc" ]; } || err "cannot read the agent directory $osrc"
      command -v python3 >/dev/null 2>&1 || err "python3 is needed to snapshot omp's databases"
      for f in config.yml config.yaml models.yml models.yaml AGENTS.md APPEND_SYSTEM.md RULES.md kimi-device-id .env; do
        path_state "$osrc/$f"; fst=$?
        [ "$fst" -ne 2 ] || err "cannot tell whether $osrc/$f exists (an unreachable path)"
        [ "$fst" -eq 0 ] || continue
        cp "$osrc/$f" "$odst/$f" || err "could not copy $osrc/$f"
      done
      for f in agent.db models.db; do
        path_state "$osrc/$f"; fst=$?
        [ "$fst" -ne 2 ] || err "cannot tell whether $osrc/$f exists (an unreachable path): a database that cannot be snapshotted is not an absent one"
        [ "$fst" -eq 0 ] || continue
        if [ "$f" = agent.db ]; then
          if [ "${2+set}" = set ]; then
            oprov=""; case "$2" in */*) oprov="${2%%/*}" ;; esac
            python3 "$ADIR/seed-db.py" "$osrc/$f" "$odst/$f" --drop-oauth --provider "$oprov"; orc=$?
          else
            python3 "$ADIR/seed-db.py" "$osrc/$f" "$odst/$f" --drop-oauth; orc=$?
          fi
          case "$orc" in
            0) ;;
            4) exit 4 ;;
            *) err "could not snapshot $osrc/$f" ;;
          esac
        else
          python3 "$ADIR/seed-db.py" "$osrc/$f" "$odst/$f" || err "could not snapshot $osrc/$f"
        fi
      done
    fi
    for f in "$HOME/.env" "$HOME/$cname/.env"; do
      path_state "$f"; fst=$?
      [ "$fst" -ne 2 ] || err "cannot tell whether $f exists (an unreachable path)"
      [ "$fst" -eq 0 ] || continue
      case "$f" in "$HOME/.env") cp "$f" "$obuild/.env" || err "could not copy $f" ;; *) cp "$f" "$obuild/$cname/.env" || err "could not copy $f" ;; esac
    done
    [ -e "$HOME/Library" ] && ln -s "$HOME/Library" "$obuild/Library"
    [ -e "$HOME/$cname/natives" ] && ln -s "$HOME/$cname/natives" "$obuild/$cname/natives"
    mv "$obuild" "$ohome" || err "could not move the state directory into the stage"
    trap - EXIT
    odst="$ohome/$cname/agent"
    printf 'HOME=%s\nPI_CONFIG_DIR=%s\nPI_CODING_AGENT_DIR=%s\n' "$ohome" "$cname" "$odst"
    ;;

  l2-argv) # $1=model -> NUL-delimited argv for the L2 aggregator; the prompt arrives on stdin
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    # shellcheck source=/dev/null
    sysprompt=$(. "$BIN/l2-prompt.sh" && l2_system_prompt) || exit 2
    printf '%s\0' "$(omp_bin)" \
      --allow-home \
      -p \
      --approval-mode yolo \
      --no-session \
      --config "$OVERLAY" \
      --model "$1" \
      --tools=Glob,Read \
      --append-system-prompt "$sysprompt"
    ;;

  skills-inventory)
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
