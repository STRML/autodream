#!/bin/bash

set -u

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
PROJECTS_DIR_EXPLICIT=0
if [ -n "${PROJECTS_DIR+x}" ]; then
  PROJECTS_DIR_EXPLICIT=1
  PROJECTS_DIR="${PROJECTS_DIR:-$HOME/.claude/projects}"
else
  PROJECTS_DIR="$HOME/.claude/projects"
fi
AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"

AUTODREAM_CONFIG="${AUTODREAM_CONFIG:-$AUTODREAM_DIR/config}"
if [ -f "$AUTODREAM_CONFIG" ]; then
  _env_snapshot=$(export -p)

  # shellcheck disable=SC1090
  _config_probe_err=$(set -a; set -u; . "$AUTODREAM_CONFIG" 2>&1 1>/dev/null)
  if [ -n "$_config_probe_err" ]; then
    echo "WARNING: $AUTODREAM_CONFIG has an unbound variable reference (continuing without it): $_config_probe_err" >&2
  fi

  set +u
  set -a
  # shellcheck disable=SC1090
  . "$AUTODREAM_CONFIG" || echo "WARNING: failed to source $AUTODREAM_CONFIG (continuing)" >&2
  set +a
  set -u
  eval "$_env_snapshot"
  unset _env_snapshot _config_probe_err
fi
DREAMS_DIR="${DREAMS_DIR:-$HOME/.claude/dreams}"
LOG_DIR="$AUTODREAM_DIR/logs"
FANOUT="${FANOUT:-8}"

AUTODREAM_L1_TIMEOUT="${AUTODREAM_L1_TIMEOUT:-1200}"
case "$AUTODREAM_L1_TIMEOUT" in
  ''|*[!0-9]*) echo "FATAL: AUTODREAM_L1_TIMEOUT must be a positive integer (got '$AUTODREAM_L1_TIMEOUT')" >&2; exit 1 ;;
  *) [ "$AUTODREAM_L1_TIMEOUT" -gt 0 ] || { echo "FATAL: AUTODREAM_L1_TIMEOUT must be greater than 0 (0 disables the timeout entirely)" >&2; exit 1; } ;;
esac
AUTODREAM_L1_WARMUP_TIMEOUT="${AUTODREAM_L1_WARMUP_TIMEOUT:-120}"
case "$AUTODREAM_L1_WARMUP_TIMEOUT" in
  ''|*[!0-9]*) echo "FATAL: AUTODREAM_L1_WARMUP_TIMEOUT must be a positive integer (got '$AUTODREAM_L1_WARMUP_TIMEOUT')" >&2; exit 1 ;;
  *) [ "$AUTODREAM_L1_WARMUP_TIMEOUT" -gt 0 ] || { echo "FATAL: AUTODREAM_L1_WARMUP_TIMEOUT must be greater than 0 (0 disables the warmup deadline entirely)" >&2; exit 1; } ;;
esac
L1_KILL_GRACE=30
AUTODREAM_L1_CHUNK_BYTES="${AUTODREAM_L1_CHUNK_BYTES:-0}"
case "$AUTODREAM_L1_CHUNK_BYTES" in
  ''|*[!0-9]*) echo "FATAL: AUTODREAM_L1_CHUNK_BYTES must be a non-negative integer (got '$AUTODREAM_L1_CHUNK_BYTES'); 0 turns chunking off" >&2; exit 1 ;;
esac
AUTODREAM_L1_CHUNK_BYTES=$((10#$AUTODREAM_L1_CHUNK_BYTES))
AUTODREAM_L1_MAX_CHUNKS="${AUTODREAM_L1_MAX_CHUNKS:-8}"
case "$AUTODREAM_L1_MAX_CHUNKS" in
  ''|*[!0-9]*) echo "FATAL: AUTODREAM_L1_MAX_CHUNKS must be a positive integer (got '$AUTODREAM_L1_MAX_CHUNKS')" >&2; exit 1 ;;
esac
AUTODREAM_L1_MAX_CHUNKS=$((10#$AUTODREAM_L1_MAX_CHUNKS))
[ "$AUTODREAM_L1_MAX_CHUNKS" -ge 1 ] || { echo "FATAL: AUTODREAM_L1_MAX_CHUNKS must be at least 1" >&2; exit 1; }
AUTODREAM_SANDBOX_SHAPE_MIN="${AUTODREAM_SANDBOX_SHAPE_MIN:-10}"
case "$AUTODREAM_SANDBOX_SHAPE_MIN" in
  ''|*[!0-9]*) echo "FATAL: AUTODREAM_SANDBOX_SHAPE_MIN must be a positive integer (got '$AUTODREAM_SANDBOX_SHAPE_MIN')" >&2; exit 1 ;;
esac
AUTODREAM_SANDBOX_SHAPE_MIN=$((10#$AUTODREAM_SANDBOX_SHAPE_MIN))
[ "$AUTODREAM_SANDBOX_SHAPE_MIN" -ge 1 ] || { echo "FATAL: AUTODREAM_SANDBOX_SHAPE_MIN must be a positive integer (got 0, which would list every session)" >&2; exit 1; }
for _knob in AUTODREAM_MIN_USER_TURNS AUTODREAM_MIN_MINUTES; do
  case "${!_knob:-0}" in
    ''|*[!0-9]*) echo "FATAL: $_knob must be a non-negative integer (got '${!_knob}')" >&2; exit 1 ;;
  esac
done

WORK_DIR="$AUTODREAM_DIR/work"
WORK_BUCKET="$PROJECTS_DIR/$(printf '%s' "$WORK_DIR" | sed 's#[/.]#-#g')"

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"
TARGET_DATE="${1:-$(pdate_yesterday)}"
NEXT_DATE=$(pdate_shift "$TARGET_DATE" 1 d)

FINDINGS_DIR="$AUTODREAM_DIR/findings/$TARGET_DATE"
REPORT_PATH="$DREAMS_DIR/$TARGET_DATE.md"
RUN_LOG="$LOG_DIR/run-$TARGET_DATE.log"
SESSIONS_LIST="$FINDINGS_DIR/sessions.txt"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

RUNNER_SRC="${BASH_SOURCE[0]}"
runner_hops=0
while [ -L "$RUNNER_SRC" ] && [ "$runner_hops" -lt 8 ]; do
  runner_link_dir=$(cd "$(dirname "$RUNNER_SRC")" && pwd) || break
  RUNNER_SRC=$(readlink "$RUNNER_SRC") || break
  case $RUNNER_SRC in /*) ;; *) RUNNER_SRC="$runner_link_dir/$RUNNER_SRC" ;; esac
  runner_hops=$((runner_hops + 1))
done

RUNNER_BIN_DIR=""
if [ ! -L "$RUNNER_SRC" ]; then
  RUNNER_BIN_DIR=$(cd "$(dirname "$RUNNER_SRC")" 2>/dev/null && pwd) || RUNNER_BIN_DIR=""
fi
find_lib() {
  if [ -r "$SCRIPT_DIR/$1" ]; then printf '%s' "$SCRIPT_DIR/$1"; return 0; fi
  if [ -n "$RUNNER_BIN_DIR" ] && [ -r "$RUNNER_BIN_DIR/$1" ]; then
    printf '%s' "$RUNNER_BIN_DIR/$1"; return 0
  fi
  return 1
}

_lib=$(find_lib lib-project.sh) && { # shellcheck source=/dev/null
  . "$_lib"; }
_lib=$(find_lib adapters.sh) && { # shellcheck source=/dev/null
  . "$_lib"; }
_lib=$(find_lib report-format.sh) || { echo "FATAL: report-format.sh not found beside run.sh or its link target" >&2; exit 1; }
# shellcheck source=/dev/null
. "$_lib"
_lib=$(find_lib err-cause.sh) || { echo "FATAL: err-cause.sh not found beside run.sh or its link target" >&2; exit 1; }
# shellcheck source=/dev/null
. "$_lib"
PREFLIGHT=$(find_lib preflight.sh) || PREFLIGHT="$SCRIPT_DIR/preflight.sh"

PRUNE="$SCRIPT_DIR/prune-self-sessions.sh"
[ -x "$PRUNE" ] || PRUNE="$AUTODREAM_DIR/prune-self-sessions.sh"
if [ -n "${AUTODREAM_ROOTPROBE_BIN:-}" ]; then
  ROOT_PROBE="$AUTODREAM_ROOTPROBE_BIN"
else
  ROOT_PROBE="$SCRIPT_DIR/root-probe.sh"
  [ -x "$ROOT_PROBE" ] || ROOT_PROBE="$AUTODREAM_DIR/root-probe.sh"
fi
SLIM="$SCRIPT_DIR/slim-transcript.sh"
[ -x "$SLIM" ] || SLIM="$AUTODREAM_DIR/slim-transcript.sh"
if [ -n "${AUTODREAM_STATS_BIN:-}" ]; then
  STATS="$AUTODREAM_STATS_BIN"
else
  STATS="$SCRIPT_DIR/session-stats.sh"
  [ -x "$STATS" ] || STATS="$AUTODREAM_DIR/session-stats.sh"
fi
if [ -n "${AUTODREAM_OVERLAP_BIN:-}" ]; then
  OVERLAP="$AUTODREAM_OVERLAP_BIN"
else
  OVERLAP="$SCRIPT_DIR/overlap-stats.sh"
  [ -x "$OVERLAP" ] || OVERLAP="$AUTODREAM_DIR/overlap-stats.sh"
fi
CITECHECK="$SCRIPT_DIR/citation-check.sh"
[ -x "$CITECHECK" ] || CITECHECK="$AUTODREAM_DIR/citation-check.sh"
TRIAGE_DREAM="$SCRIPT_DIR/triage-dream.sh"
[ -x "$TRIAGE_DREAM" ] || TRIAGE_DREAM="$AUTODREAM_DIR/triage-dream.sh"
if [ -n "${AUTODREAM_VAULT_BIN:-}" ]; then
  VAULT_NOTES="$AUTODREAM_VAULT_BIN"
else
  VAULT_NOTES="$SCRIPT_DIR/vault-notes.sh"
  [ -x "$VAULT_NOTES" ] || VAULT_NOTES="$AUTODREAM_DIR/vault-notes.sh"
fi
if [ -n "${AUTODREAM_XBOOKMARKS_BIN:-}" ]; then
  XBOOKMARKS="$AUTODREAM_XBOOKMARKS_BIN"
else
  XBOOKMARKS="$SCRIPT_DIR/x-bookmarks.sh"
  [ -x "$XBOOKMARKS" ] || XBOOKMARKS="$AUTODREAM_DIR/x-bookmarks.sh"
fi
if [ -n "${AUTODREAM_REPORTS_BIN:-}" ]; then
  REPORT_SCRIPTS="$AUTODREAM_REPORTS_BIN"
else
  REPORT_SCRIPTS="$SCRIPT_DIR/report-scripts.sh"
  [ -x "$REPORT_SCRIPTS" ] || REPORT_SCRIPTS="$AUTODREAM_DIR/report-scripts.sh"
fi
if [ -n "${AUTODREAM_PRUNE_BIN:-}" ]; then
  PRUNE_WORKTREES="$AUTODREAM_PRUNE_BIN"
else
  PRUNE_WORKTREES="$SCRIPT_DIR/prune-worktrees.sh"
  [ -x "$PRUNE_WORKTREES" ] || PRUNE_WORKTREES="$AUTODREAM_DIR/prune-worktrees.sh"
fi
if [ -n "${AUTODREAM_TRIAGE_BIN:-}" ]; then
  TRIAGE_CANDIDATES="$AUTODREAM_TRIAGE_BIN"
else
  TRIAGE_CANDIDATES="$SCRIPT_DIR/triage-candidates.sh"
  [ -x "$TRIAGE_CANDIDATES" ] || TRIAGE_CANDIDATES="$AUTODREAM_DIR/triage-candidates.sh"
fi
APPLY_PINS=$(find_lib apply-pins.sh) || APPLY_PINS="$SCRIPT_DIR/apply-pins.sh"

SESSION_WINDOW=$(find_lib session-window.sh) || SESSION_WINDOW=""
ENUM_END="$NEXT_DATE"
WINDOW_ON=0
WIN_START_EPOCH=""
WIN_END_EPOCH=""
if [ "${AUTODREAM_WINDOW:-1}" != "0" ] && [ -n "$SESSION_WINDOW" ] \
   && _wb=$(bash "$SESSION_WINDOW" bounds "$TARGET_DATE" "$NEXT_DATE" 2>/dev/null) && [ -n "$_wb" ] \
   && _far=$(pdate_shift "$TARGET_DATE" 5 y) && [ -n "$_far" ] \
   && find / -maxdepth 0 ! -newermt "$_far 00:00:00" >/dev/null 2>&1; then
  WIN_START_EPOCH="${_wb%% *}"
  WIN_END_EPOCH="${_wb##* }"
  WINDOW_ON=1
  ENUM_END="$_far"
fi

CHUNKER=$(find_lib chunk-transcript.sh) || CHUNKER=""
MERGER=$(find_lib merge-chunks.sh) || MERGER=""
ROLLUP=$(find_lib rollup.sh) || ROLLUP=""
L1_CONFINER=$(find_lib l1-confine.sh) || L1_CONFINER=""
L1_CHUNKING=0
if [ "$AUTODREAM_L1_CHUNK_BYTES" -gt 0 ] && [ -n "$CHUNKER" ] && [ -n "$MERGER" ]; then
  L1_CHUNKING=1
fi

if [ -L "$RUNNER_SRC" ]; then
  RUNNER_REPO_DIR=""
else
  RUNNER_REPO_DIR=$(cd "$(dirname "$RUNNER_SRC")" && pwd) || RUNNER_REPO_DIR=""
fi
if [ -z "$RUNNER_REPO_DIR" ]; then
  RUNNER_COMMIT=""
else
  RUNNER_COMMIT=$(git -C "$RUNNER_REPO_DIR" rev-parse --short HEAD 2>/dev/null) || RUNNER_COMMIT=""
fi
: "${RUNNER_COMMIT:=unknown}"
if [ "$RUNNER_COMMIT" = "unknown" ]; then
  RUNNER_DIRTY=no
elif [ -n "$(git -C "$RUNNER_REPO_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  RUNNER_DIRTY=yes
else
  RUNNER_DIRTY=no
fi

FAILURE_CLASS=""
for candidate in "$SCRIPT_DIR" "$RUNNER_REPO_DIR" "$AUTODREAM_DIR"; do
  [ -n "$candidate" ] && [ -r "$candidate/failure-class.sh" ] && { FAILURE_CLASS="$candidate/failure-class.sh"; break; }
done
if [ -z "$FAILURE_CLASS" ]; then
  printf 'fatal: required failure classifier not found next to %s, %s or %s\n' "$SCRIPT_DIR" "${RUNNER_REPO_DIR:-?}" "$AUTODREAM_DIR" >&2
  exit 1
fi
# shellcheck source=./failure-class.sh
. "$FAILURE_CLASS"

mkdir -p "$FINDINGS_DIR" "$DREAMS_DIR" "$LOG_DIR" "$WORK_DIR"

export PATH="${PATH:+$PATH:}$HOME/.cargo/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
cd "$HOME" || exit 1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

FATAL_REASON=""
log_fatal() { FATAL_REASON="$1"; log "FATAL: $1"; }

fatal_exit() {
  local reason="${FATAL_REASON:-the run stopped before it produced a report}"
  mkdir -p "$FINDINGS_DIR" 2>/dev/null || true
  if [ -s "$REPORT_PATH" ]; then
    log "  not overwriting run-stats.txt: $TARGET_DATE already has a complete report"
    notify_fatal "$reason (the existing report for $TARGET_DATE is unchanged)"
    return 1
  fi
  {
    printf '# Autodream run self-audit — %s\n' "$TARGET_DATE"
    printf 'runner_commit: %s\n' "$RUNNER_COMMIT"
    printf 'runner_dirty: %s\n' "$RUNNER_DIRTY"
    printf 'fatal: %s\n' "$reason"
    printf 'sessions_triaged: 0\n'
    printf '%s' "${REMOTE_SYNC_LINES:-}"
  } > "$FINDINGS_DIR/run-stats.txt" 2>/dev/null || true
  notify_fatal "$reason"
  return 1
}

notify_fatal() { # $1=reason
  [ -x "$AUTODREAM_DIR/notify.sh" ] || return 0
  "$AUTODREAM_DIR/notify.sh" --failure "$TARGET_DATE" "$1" \
    || log "failure notification returned non-zero (continuing)"
}

sweep_killed_leftovers() {
  local _f _n=0
  for _f in "$FINDINGS_DIR"/*.tmp.?????? "$FINDINGS_DIR"/*.pre.jsonl "$FINDINGS_DIR"/*.stage "$FINDINGS_DIR"/.chunks/*/*.stage; do
    { [ -e "$_f" ] || [ -L "$_f" ]; } || continue
    rm -rf "$_f" 2>/dev/null && _n=$((_n + 1))
  done
  [ "$_n" -eq 0 ] || log "removed $_n temp file(s) left in $FINDINGS_DIR by a killed run"
}

clean_work_bucket() { rm -rf "$WORK_BUCKET" 2>/dev/null || true; }

probe_roots() {
  SESSION_ROOTS="${SESSION_ROOTS:-}"
  if [ -z "$SESSION_ROOTS" ] && [ "$PROJECTS_DIR_EXPLICIT" = "1" ]; then
    SESSION_ROOTS="$PROJECTS_DIR"
  fi
  if [ -n "$SESSION_ROOTS" ]; then
    log "session roots: ${SESSION_ROOTS//:/, }"
    return 0
  fi
  if [ -x "$ROOT_PROBE" ]; then
    SESSION_ROOTS=$("$ROOT_PROBE" --consolidated 2>/dev/null) || SESSION_ROOTS=""
  fi
  SESSION_ROOTS_ARE_FALLBACK=0
  if [ -z "$SESSION_ROOTS" ]; then
    SESSION_ROOTS="$HOME/.claude/projects"
    SESSION_ROOTS_ARE_FALLBACK=1
  fi
  log "session roots: ${SESSION_ROOTS//:/, }"
}

write_unindexed_flag() {
  local flag="$FINDINGS_DIR/unindexed-roots.txt"
  : > "$flag"
  [ -x "$ROOT_PROBE" ] || { printf 'root-probe.sh not found; cannot detect unindexed claude folders\n' > "$flag"; return 0; }
  "$ROOT_PROBE" --unindexed 2>/dev/null >> "$flag" || true
  [ -s "$flag" ] || printf '(none — every $HOME/.claude*/projects dir is indexed)\n' > "$flag"
}

NL=$'\n'            # for the newline-in-path check below
TAB=$'\t'           # ditto; the tab-separated artifacts cannot carry one
REJECTED_PATHS=0    # session paths a line-based sessions.txt cannot represent
OUT_OF_WINDOW=0     # files modified since the day began that hold no record inside it
SESSIONS_WINDOWED=0 # triaged sessions that spill outside the day, so their stats are cut to it
PARTIAL_ROOTS=0     # roots whose enumerator failed but still returned data
ROOTS_CONFIGURED=0  # roots we were told to scan
ROOTS_SCANNED=0     # roots that existed and were walked
ROOTS_UNAVAILABLE=0 # roots that were configured but are not directories
ROOTS_FAILED=0      # roots reached but whose enumeration failed and returned nothing
SESSION_ROOTS_ARE_FALLBACK=0  # 1 when SESSION_ROOTS is the bare default nobody configured
COLLIDED_DROPPED=0  # paths removed from the worklist by collision handling
SIDECAR_STALE_ROWS=0  # provenance rows that could not be rewritten; sessions_by_source is high by this much
DUPLICATE_PATHS=0   # one path reached twice: overlapping roots, or two adapters
HASH_COLLISIONS=0   # two different paths truncating to one artifact hash
SESSIONS_BY_SOURCE=none

adapter_roots() { # $1=adapter name -> one root per line
  if [ "$1" = "claude" ]; then
    printf '%s\n' "$SESSION_ROOTS" | tr ':' '\n'
    return 0
  fi
  local roots up var
  up=$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')
  var="AUTODREAM_SESSION_ROOTS_$up"
  if [ -n "${!var:-}" ]; then
    printf '%s\n' "${!var}" | tr ':' '\n'
    return 0
  fi
  roots=$(adapter_manifest_get "$1" '.session_roots_default[]' 2>/dev/null) || return 0
  [ -n "$roots" ] || return 0
  printf '%s\n' "$roots"
}

ENABLED_ADAPTERS=""
ENABLED_ADAPTERS_RESOLVED=0
resolve_enabled_adapters() {
  [ "$ENABLED_ADAPTERS_RESOLVED" = "1" ] && return 0
  ENABLED_ADAPTERS=$(_enabled_adapters_uncached)
  ENABLED_ADAPTERS_RESOLVED=1
  return 0
}
review_engine() {
  resolve_enabled_adapters
  printf '%s' "${AUTODREAM_L2_ENGINE:-${ENABLED_ADAPTERS%% *}}"
}
ENGINE_LOGINS=""
LOGIN_REFUSAL=""
engine_login_ok() { # $1=engine -> 0 when its login meets AUTODREAM_REQUIRE_LOGIN, or nothing is required
  local eng="$1" row who req k want have
  row=$(printf '%s' "$ENGINE_LOGINS" | awk -F'\t' -v e="$eng" '$1 == e { print; exit }')
  if [ -z "$row" ]; then
    who=$(adapter_run "$eng" whoami 2>/dev/null) || who=""
    printf '%s' "$who" | jq -e 'type == "object"' >/dev/null 2>&1 || who='{}'
    row="$eng"$'\t'"$(printf '%s' "$who" | jq -r '[.provider, .auth, .plan, .account, .expires] | map(. // "unknown" | tostring) | @tsv')"
    ENGINE_LOGINS="${ENGINE_LOGINS}${row}"$'\n'
    log "login for the $eng engine: $(printf '%s' "$row" | awk -F'\t' '{ printf "provider=%s auth=%s plan=%s account=%s expires=%s", $2, $3, $4, $5, $6 }')"
    login_expiry_warn "$eng" "$(printf '%s' "$row" | cut -f3)" "$(printf '%s' "$row" | cut -f6)"
  fi
  LOGIN_REFUSAL=""
  if [ "$(printf '%s' "$row" | cut -f3)" = "claude.ai" ]; then
    local exp left
    exp=$(printf '%s' "$row" | cut -f6)
    if left=$(login_seconds_left "$exp") && [ "$left" -le 0 ]; then
      LOGIN_REFUSAL="its claude.ai sign-in ended $exp; run claude auth login"
      return 1
    fi
  fi
  for req in ${AUTODREAM_REQUIRE_LOGIN:-}; do
    k=${req%%=*}; want=${req#*=}
    case "$k" in
      provider) have=$(printf '%s' "$row" | cut -f2) ;;
      auth) have=$(printf '%s' "$row" | cut -f3) ;;
      plan) have=$(printf '%s' "$row" | cut -f4) ;;
      account) have=$(printf '%s' "$row" | cut -f5) ;;
      *) LOGIN_REFUSAL="$req is not a provider, auth, plan or account requirement"; return 1 ;;
    esac
    [ "$have" = "$want" ] || { LOGIN_REFUSAL="$k is $have, not $want"; return 1; }
  done
  return 0
}
login_seconds_left() { # $1=end time
  local stamp end
  stamp=$(printf '%s' "$1" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)T\([0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*Z$/\1 \2/p')
  [ -n "$stamp" ] || return 1
  end=$(TZ=UTC pdate_epoch "$stamp") || return 1
  printf '%s' "$(( end - $(date +%s) ))"
}
login_expiry_warn() { # $1=engine $2=auth $3=end time as whoami reports it
  local days="${AUTODREAM_LOGIN_WARN_DAYS:-10}" left when msg
  [ "$2" = "claude.ai" ] || return 0
  case "$days" in ''|*[!0-9]*) return 0 ;; esac
  days=$(( 10#$days ))
  [ "$days" -gt 0 ] || return 0
  left=$(login_seconds_left "$3") || return 0
  [ "$left" -gt 0 ] && [ "$left" -le $(( days * 86400 )) ] || return 0
  if [ "$left" -lt 86400 ]; then when="$(( (left + 3599) / 3600 )) hours"
  else when="$(( left / 86400 )) days"; fi
  msg="the claude.ai sign-in of the $1 engine ends $3 (in $when); run claude auth login before then"
  log "WARNING: $msg"
  [ -x "$AUTODREAM_DIR/notify.sh" ] || return 0
  "$AUTODREAM_DIR/notify.sh" --warning "$TARGET_DATE" "$msg" "login-$1" \
    || log "login expiry notification returned non-zero (continuing)"
}
_enabled_adapters_uncached() {
  if ! declare -F adapters_list >/dev/null 2>&1 || [ ! -d "$(adapters_root 2>/dev/null)" ]; then
    printf 'claude'; return 0
  fi
  local a
  a=$(adapters_list 2>/dev/null | tr '\n' ' ')
  a="${a% }"
  if [ -z "${a// /}" ]; then
    printf ''                        # tree present, nothing accepted: a refusal
    return 0
  fi
  local one keep="" want
  want=" $(printf '%s' "${AUTODREAM_ADAPTERS:-claude}" | tr ',' ' ') "
  for one in $a; do
    case "$want" in
      *" all "*|*" $one "*) keep="${keep:+$keep }$one" ;;
      *) log "  adapter '$one' is accepted but not enabled (AUTODREAM_ADAPTERS=${AUTODREAM_ADAPTERS:-claude}); not enumerating it" >&2 ;;
    esac
  done
  printf '%s' "$keep"
}

scan_roots() {
  if ! { : > "$SESSIONS_LIST.raw"; } 2>/dev/null \
     || ! { : > "$SESSIONS_LIST.src"; } 2>/dev/null; then
    log_fatal "cannot write the session lists in $FINDINGS_DIR"
    return 1
  fi
  REJECTED_PATHS=0
  local src adapters
  resolve_enabled_adapters
  adapters="$ENABLED_ADAPTERS"
  ACCEPTED_ADAPTERS=$(adapters_list 2>/dev/null)
  if [ -z "${adapters// /}" ]; then
    local accepted; accepted=$(adapters_list 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    if [ -n "$accepted" ]; then
      log_fatal "no usable adapter — accepted [$accepted] but none is enabled (AUTODREAM_ADAPTERS=${AUTODREAM_ADAPTERS:-claude}). Refusing to scan."
    else
      log_fatal "the adapter loader ran and accepted no adapters (rejected: $(adapters_rejected 2>/dev/null)). Refusing to scan."
    fi
    RAW=0
    return 1
  fi
  for src in $adapters; do
    scan_one_adapter "$src" || return 1
  done
  if [ "${SESSION_ROOTS_ARE_FALLBACK:-0}" != "1" ] \
     && [ "$ROOTS_CONFIGURED" -gt 0 ] && [ "$ROOTS_SCANNED" -eq 0 ]; then
    log_fatal "all $ROOTS_CONFIGURED configured session root(s) are unavailable; refusing to report an empty night over a store that was never reached"
    return 1
  fi

  sort_unique_inplace "$SESSIONS_LIST.raw" "the session worklist" || return 1
  RAW=$(wc -l < "$SESSIONS_LIST.raw" | tr -d ' ')
}

scan_one_adapter() { # $1=adapter name
  local src="$1" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ROOTS_CONFIGURED=$((ROOTS_CONFIGURED + 1))
    if [ ! -d "$r" ]; then
      ROOTS_UNAVAILABLE=$((ROOTS_UNAVAILABLE + 1))
      log "WARNING: session root is not a directory (possible ':' in path — SESSION_ROOTS is colon-separated): $r"
      continue
    fi
    ROOTS_SCANNED=$((ROOTS_SCANNED + 1))
    local nulfile status
    nulfile=$(mktemp "$FINDINGS_DIR/.enum.XXXXXX") || { log_fatal "cannot stage enumeration in $FINDINGS_DIR"; return 1; }
    enumerate_for "$src" "$r" > "$nulfile"
    status=$?
    if [ "$status" -ne 0 ]; then
      if [ -s "$nulfile" ]; then
        PARTIAL_ROOTS=$((PARTIAL_ROOTS + 1))
        log "WARNING: enumeration for adapter '$src' at root $r exited $status but returned data; continuing with a possibly INCOMPLETE corpus for this root"
      else
        ROOTS_FAILED=$((ROOTS_FAILED + 1))
        log "WARNING: enumeration failed for adapter '$src' at root $r (exit $status) and returned nothing; this root contributes NO sessions to tonight's corpus"
        rm -f "$nulfile"
        continue
      fi
    fi
    while IFS= read -r -d '' sp; do
      case "$sp" in
        *"$NL"*|*"$TAB"*)
          REJECTED_PATHS=$((REJECTED_PATHS + 1))
          log "  skip: session path holds a newline or tab, which the line-based artifact lists cannot carry: $(printf '%q' "$sp")"
          continue
          ;;
      esac
      if [ "$WINDOW_ON" = 1 ]; then
        bash "$SESSION_WINDOW" in-window "$sp" "$WIN_START_EPOCH" "$WIN_END_EPOCH" </dev/null >/dev/null 2>&1
        if [ "$?" -eq 1 ]; then
          OUT_OF_WINDOW=$((OUT_OF_WINDOW + 1))
          continue
        fi
      fi
      if ! printf '%s\n' "$sp" >> "$SESSIONS_LIST.raw" 2>/dev/null \
         || ! printf '%s\t%s\n' "$src" "$sp" >> "$SESSIONS_LIST.src" 2>/dev/null; then
        log_fatal "could not record $sp in the session lists"
        rm -f "$nulfile"
        return 1
      fi
    done < "$nulfile"
    rm -f "$nulfile"
  done < <(adapter_roots "$src")
  return 0
}

enumerate_for() { # $1=adapter $2=root -> NUL-delimited paths
  if declare -F adapter_run >/dev/null 2>&1 \
     && printf '%s\n' ${ACCEPTED_ADAPTERS:-} | grep -qxF "$1" \
     && [ -x "$(adapters_root 2>/dev/null)/$1/adapter.sh" ]; then
    adapter_run "$1" enumerate "$2" "$TARGET_DATE" "$ENUM_END"
    return $?
  fi
  if [ "$1" != "claude" ]; then
    log "  no adapter for '$1' and no fallback that knows its session format; this root contributes nothing" >&2
    return 1
  fi
  find "$2" -type f -name '*.jsonl' \
       -newermt "$TARGET_DATE 00:00:00" \
       ! -newermt "$ENUM_END 00:00:00" \
       -print0 2>/dev/null
}

sort_unique_inplace() { # $1=file $2=what (for the log)
  local f="$1" what="$2"
  if sort -u "$f" > "$f.su.$$" 2>/dev/null && mv -f "$f.su.$$" "$f" 2>/dev/null; then
    return 0
  fi
  rm -f "$f.su.$$"
  log_fatal "could not deduplicate $what; refusing to continue over a possibly damaged list"
  return 1
}

rewrite_filtered() { # $1=file $2=what (for the log) ; remaining args = grep args
  local file="$1" what="$2"; shift 2
  local tmp="$file.rw.$$" grc
  grep "$@" "$file" > "$tmp" 2>/dev/null; grc=$?
  if [ "$grc" -gt 1 ]; then
    rm -f "$tmp"
    log "  WARNING: could not rewrite $what (grep exit $grc); leaving it unchanged"
    return 1
  fi
  if ! mv -f "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp"
    log "  WARNING: could not replace $what (mv failed); leaving it unchanged"
    return 1
  fi
  return 0
}

build_source_sidecar() {
  local sidecar="$FINDINGS_DIR/sessions-source.txt"
  local seen="$FINDINGS_DIR/.hash-to-path"
  local drop="$FINDINGS_DIR/.collided"
  if ! { : > "$sidecar"; } 2>/dev/null || ! { : > "$seen"; } 2>/dev/null \
     || ! { : > "$drop"; } 2>/dev/null; then
    log_fatal "cannot write the provenance bookkeeping files in $FINDINGS_DIR; refusing to run collision detection blind"
    return 1
  fi
  DUPLICATE_PATHS=0; HASH_COLLISIONS=0; SESSIONS_BY_SOURCE=""
  local src sp h prev
  while IFS=$'\t' read -r src sp; do
    [ -n "$sp" ] || continue
    grep -qxF "$sp" "$SESSIONS_LIST.raw" 2>/dev/null; local prc=$?
    case "$prc" in
      0) : ;;                # present, carry on
      1) continue ;;         # dropped at enumeration, expected
      *) log_fatal "could not check the worklist for $sp (grep exit $prc); refusing to build provenance over an unreadable list"
         return 1 ;;
    esac
    if ! h=$(session_hash "$sp"); then
      log_fatal "could not derive an artifact hash for $sp; refusing to run collision detection on unusable keys"
      return 1
    fi
    if ! prev=$(awk -v k="$h" 'substr($0,1,12)==k {print substr($0,14); exit}' "$seen" 2>/dev/null); then
      log_fatal "could not read the collision index; refusing to detect collisions blind"
      return 1
    fi
    if [ -n "$prev" ]; then
      if [ "$prev" = "$sp" ]; then
        DUPLICATE_PATHS=$((DUPLICATE_PATHS + 1))
        log "  duplicate: $sp was reached more than once (two session roots, or two adapters); keeping the first"
      else
        HASH_COLLISIONS=$((HASH_COLLISIONS + 1))
        log "  COLLISION: $h maps to two different sessions; dropping both: $prev / $sp"
        if ! printf '%s\n%s\n' "$prev" "$sp" >> "$drop" 2>/dev/null; then
          log_fatal "could not record a collided path for removal; refusing to dispatch two sessions onto one artifact"
          return 1
        fi
        rewrite_filtered "$sidecar" "the source sidecar" -v "^$h	" || :
      fi
      continue
    fi
    if ! printf '%s\t%s\n' "$h" "$sp" >> "$seen" 2>/dev/null; then
      log_fatal "could not record $sp in the collision index; refusing to detect collisions blind"
      return 1
    fi
    if ! printf '%s\t%s\n' "$h" "$src" >> "$sidecar" 2>/dev/null; then
      log_fatal "could not record provenance for $h in $sidecar"
      return 1
    fi
  done < "$SESSIONS_LIST.src" || {
    log_fatal "could not read the session source list; refusing to detect collisions over an unreadable input"
    return 1
  }
  rm -f "$seen"

  if [ -s "$drop" ]; then
    if ! sort_unique_inplace "$drop" "the collision drop set"; then
      rm -f "$drop"; return 1
    fi

    if ! rewrite_filtered "$SESSIONS_LIST.raw" "the worklist" -vxF -f "$drop"; then
      log_fatal "refusing to dispatch two sessions onto one artifact"
      rm -f "$drop"; return 1
    fi
    grep -qxF -f "$drop" "$SESSIONS_LIST.raw" 2>/dev/null; local vrc=$?
    if [ "$vrc" -ne 1 ]; then
      log_fatal "could not confirm the collided paths are gone from the worklist (grep exit $vrc); refusing to dispatch two sessions onto one artifact"
      rm -f "$drop"; return 1
    fi
    COLLIDED_DROPPED=$(( $(wc -l < "$drop" | tr -d ' ') ))
    while IFS= read -r sp; do
      [ -n "$sp" ] || continue
      h=$(session_hash "$sp") || continue
      rewrite_filtered "$sidecar" "the provenance row for $h" -v "^$h	" || :
    done < "$drop"

    local stale_hashes hstage ok_stage=1
    hstage="$FINDINGS_DIR/.stale-hashes.$$"
    : > "$hstage" 2>/dev/null || ok_stage=0
    if [ "$ok_stage" = "1" ]; then
      while IFS= read -r sp; do
        [ -n "$sp" ] || continue
        if ! session_hash "$sp" >> "$hstage" 2>/dev/null; then ok_stage=0; break; fi
        printf '\n' >> "$hstage" 2>/dev/null || { ok_stage=0; break; }
      done < "$drop"
    fi
    if [ "$ok_stage" = "1" ] && stale_hashes=$(sort -u "$hstage" 2>/dev/null); then
      rm -f "$hstage"
      SIDECAR_STALE_ROWS=0
      local sh grc2
      for sh in $stale_hashes; do
        grep -q "^$sh	" "$sidecar" 2>/dev/null; grc2=$?
        case "$grc2" in
          0) SIDECAR_STALE_ROWS=$((SIDECAR_STALE_ROWS + 1)) ;;
          1) : ;;                       # genuinely absent
          *) SIDECAR_STALE_ROWS=unknown; break ;;
        esac
      done
    else
      rm -f "$hstage"
      SIDECAR_STALE_ROWS=unknown
      log "  WARNING: could not compute the stale-row count; reporting it as unknown rather than zero"
    fi
  fi
  rm -f "$drop"

  SESSIONS_BY_SOURCE=$(awk -F'\t' 'NF>1 {print $2}' "$sidecar" 2>/dev/null | sort | uniq -c \
    | awk 'NF {printf "%s%s=%s", (NR>1?",":""), $2, $1}')
  [ -n "$SESSIONS_BY_SOURCE" ] || SESSIONS_BY_SOURCE="none"
}

filter_empty_sessions() {
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    if session_is_substantive "$sp"; then
      printf '%s\n' "$sp"
    fi
  done
}

session_is_substantive() {
  local sp="$1" verdict
  [ -r "$sp" ] || return 0
  verdict=$(jq -s 'if any(.[]; (.type=="user" and (.isMeta != true)) or ((.type=="message") and (.message.role=="user") and ([.message.content[]? | select(.type=="text")] | length > 0))) then 1 else 0 end' "$sp" 2>/dev/null) || return 0
  [ "$verdict" = "0" ] && return 1
  return 0
}

changelog_sources() {
  if [ -n "${CHANGELOG_REMOTE:-}" ]; then
    printf '%s|%s|%s|%s\n' "Claude Code" "$CHANGELOG_REMOTE" "CHANGELOG.md" \
      "${CLAUDE_CODE_REPO:-$AUTODREAM_DIR/cache/claude-code}"
    return 0
  fi
  if [ -n "${AUTODREAM_CHANGELOG_SOURCES:-}" ]; then
    printf '%s\n' "$AUTODREAM_CHANGELOG_SOURCES" | tr ';' '\n' | sed '/^[[:space:]]*$/d'
    return 0
  fi
  printf '%s|%s|%s|%s\n' \
    "Claude Code" "https://github.com/anthropics/claude-code.git" "CHANGELOG.md" "${CLAUDE_CODE_REPO:-$AUTODREAM_DIR/cache/claude-code}"
  printf '%s|%s|%s|%s\n' \
    "Codex" "https://github.com/openai/codex.git" "CHANGELOG.md" "$AUTODREAM_DIR/cache/codex"
  printf '%s|%s|%s|%s\n' \
    "OMP" "https://github.com/STRML/oh-my-pi.git" "packages/coding-agent/CHANGELOG.md" "$AUTODREAM_DIR/cache/oh-my-pi"
}

cache_owns() {
  local cache parent
  case "$1" in *..*) return 1 ;; esac
  cache=$(cd "$AUTODREAM_DIR/cache" 2>/dev/null && pwd -P) || return 1
  parent=$(dirname "$1")
  while [ ! -e "$parent" ] && [ ! -L "$parent" ]; do
    [ "$parent" != "$(dirname "$parent")" ] || return 1
    parent=$(dirname "$parent")
  done
  parent=$(cd "$parent" 2>/dev/null && pwd -P) || return 1
  case "$parent/" in "$cache"/*) return 0 ;; esac
  return 1
}

changelog_git() { # $1=owned (yes|no), then git's arguments
  local owned="$1"; shift
  if [ "$owned" = yes ]; then
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git "$@"
    return
  fi
  git "$@"
}

changelog_fail() { # $1=name $2=what failed $3=git's reason (may be empty) $4=out
  local name="$1" what="$2" why="$3" out="$4"
  log "changelog[$name]: $what${why:+ ($why)}"
  printf '## %s\n\n%s%s; %s changes not checked this run.\n\n' \
    "$name" "$what" "${why:+ ($why)}" "$name" >> "$out"
  [ -n "$CHANGELOG_FIRST_ERR" ] || CHANGELOG_FIRST_ERR="$name: ${why:-$what}"
}

changelog_step() { # $1=name $2=what failed $3=out, then the command
  local name="$1" what="$2" out="$3" errf rc=0
  shift 3
  errf=$(mktemp "${TMPDIR:-/tmp}/clerr.XXXXXX" 2>/dev/null) || errf=/dev/null
  "$@" 2>"$errf" || rc=1
  cat "$errf" >> "$RUN_LOG" 2>/dev/null
  [ "$rc" -eq 0 ] || changelog_fail "$name" "$what" "$(err_cause_line "$errf")" "$out"
  [ "$errf" = /dev/null ] || rm -f "$errf"
  return "$rc"
}

changelog_sync() { # $1=repo $2=owned
  if [ "$2" = yes ]; then
    ( cd "$1" && changelog_git yes fetch --quiet origin && changelog_git yes reset --hard --quiet FETCH_HEAD )
    return
  fi
  ( cd "$1" && git pull --ff-only --quiet )
}

changelog_patch() { # $1=repo $2=owned $3=path $4=dest file
  ( cd "$1" && changelog_git "$2" log -p --reverse \
      --since="$TARGET_DATE 00:00:00" --until="$NEXT_DATE 00:00:00" -- "$3" ) > "$4"
}

changelog_clone() { # $1=name $2=remote $3=path $4=repo $5=owned $6=out
  local name="$1" remote="$2" path="$3" repo="$4" owned="$5" out="$6"
  if [ "$owned" = yes ]; then rm -rf "$repo"; fi
  if [ -e "$repo" ] && [ -n "$(ls -A "$repo" 2>/dev/null)" ]; then
    log "changelog[$name]: $repo exists, is not a git repo and is outside $AUTODREAM_DIR/cache; refusing to delete it"
    changelog_fail "$name" "Cache path $repo is a non-empty directory that is not a git clone" "" "$out"
    return 1
  fi
  log "changelog[$name]: cloning $remote -> $repo..."
  local cloneargs=()
  case "$remote" in
    *://*|*@*:*) cloneargs=(--filter=blob:none --sparse) ;;
  esac
  changelog_step "$name" "Git clone failed" "$out" \
    changelog_git "$owned" clone --quiet "${cloneargs[@]+"${cloneargs[@]}"}" "$remote" "$repo" || return 1
  [ "${#cloneargs[@]}" -gt 0 ] || return 0
  ( cd "$repo" && changelog_git "$owned" sparse-checkout set --no-cone "/$path" ) >/dev/null 2>>"$RUN_LOG" || true
}

changelog_one() { # $1=name $2=remote $3=path $4=repo $5=out
  local name="$1" remote="$2" path="$3" repo="$4" out="$5"
  local head_sha n added owned=no
  if cache_owns "$repo"; then owned=yes; fi

  if [ -d "$repo/.git" ]; then
    changelog_step "$name" "Git pull failed" "$out" changelog_sync "$repo" "$owned" || return 1
  else
    changelog_clone "$name" "$remote" "$path" "$repo" "$owned" "$out" || return 1
  fi

  head_sha=$( cd "$repo" && changelog_git "$owned" rev-parse --short HEAD 2>/dev/null ) || head_sha="?"
  n=$( cd "$repo" && changelog_git "$owned" log --format=%H \
         --since="$TARGET_DATE 00:00:00" --until="$NEXT_DATE 00:00:00" \
         -- "$path" 2>/dev/null | wc -l | tr -d ' ' )
  local patchf
  patchf=$(mktemp "${TMPDIR:-/tmp}/clpatch.XXXXXX" 2>/dev/null) \
    || { changelog_fail "$name" "No scratch file for the changelog diff" "" "$out"; return 1; }
  if ! changelog_step "$name" "Git log failed" "$out" changelog_patch "$repo" "$owned" "$path" "$patchf"; then
    rm -f "$patchf"
    return 1
  fi
  added=$( grep '^+' "$patchf" | grep -v '^+++' | sed 's/^+//' \
           | awk '!NF { print; next } /^## \[/ { hdr = $0 } !seen[hdr SUBSEP $0]++' )
  rm -f "$patchf"
  local cap="${AUTODREAM_CHANGELOG_MAX_LINES:-400}" total
  local cap_ok=no
  case "$cap" in
    ''|*[!0-9]*) ;;
    *) [ "$cap" -gt 0 ] 2>/dev/null && cap_ok=yes ;;
  esac
  if [ "$cap_ok" = no ]; then
    log "changelog[$name]: AUTODREAM_CHANGELOG_MAX_LINES='$cap' is not a positive integer; using 400"
    cap=400
  fi
  total=$(printf '%s\n' "$added" | wc -l | tr -d ' ')
  if [ "${total:-0}" -gt "$cap" ]; then
    added=$(printf '%s\n' "$added" | head -n "$cap")
    added="$added
[...truncated: $total lines in window, showing first $cap. Raise AUTODREAM_CHANGELOG_MAX_LINES to see the rest.]"
    log "changelog[$name]: $total lines truncated to $cap"
  fi

  if [ "${n:-0}" -gt 0 ] && [ -n "$added" ]; then
    printf '## %s\n# Source: %s @ %s (%s)\n# Commits touching the changelog in window: %s\n\n%s\n\n' \
      "$name" "$remote" "$head_sha" "$path" "$n" "$added" >> "$out"
    log "changelog[$name]: $n commit(s) in window"
  else
    printf '## %s\n# Source: %s @ %s (%s)\n\nNo changelog commits in this window.\n\n' \
      "$name" "$remote" "$head_sha" "$path" >> "$out"
    log "changelog[$name]: no commits in window"
  fi
}

changelog_window() {
  local out="$FINDINGS_DIR/changelog-window.md"
  [ "${AUTODREAM_CHANGELOG:-1}" != "0" ] || { log "changelog check disabled (AUTODREAM_CHANGELOG=0)"; return 0; }
  command -v git >/dev/null 2>&1 || { log "changelog: git not found; skipping"; return 0; }

  local srcs; srcs=$(changelog_sources)
  printf '# Harness changelogs — commits in [%s, %s)\n\n' "$TARGET_DATE" "$NEXT_DATE" > "$out"
  mkdir -p "$AUTODREAM_DIR/cache" 2>/dev/null || true
  local CHANGELOG_FIRST_ERR=""
  local name remote path repo sources=0 failed=0
  while IFS='|' read -r name remote path repo; do
    [ -n "$name" ] || continue
    sources=$((sources + 1))
    changelog_one "$name" "$remote" "$path" "$repo" "$out" || failed=$((failed + 1))
  done <<< "$srcs"
  log "changelog: window written -> $out"
  changelog_warn_all_failed "$sources" "$failed"
}

changelog_warn_all_failed() { # $1=sources $2=failed
  [ "$1" -gt 0 ] && [ "$2" -eq "$1" ] || return 0
  log "changelog: all $1 source(s) failed"
  [ -x "$AUTODREAM_DIR/notify.sh" ] || return 0
  "$AUTODREAM_DIR/notify.sh" --warning "$TARGET_DATE" \
    "upstream changelog check failed for all $1 source(s); first: $CHANGELOG_FIRST_ERR" \
    || log "changelog warning notification returned non-zero (continuing)"
}

report_complete() {
  report_finishes "$REPORT_PATH" "${TARGET_DATE:-}"
}

write_run_outcome() {
  case "${AUTODREAM_RUN_TOKEN:-}" in ''|*[!0-9A-Za-z._-]*) return 0 ;; esac
  printf '%s %s\n' "$AUTODREAM_RUN_TOKEN" "$1" >> "${RUN_LOG%.log}.outcome" 2>/dev/null || true
}

l2_diag_probe() { # $1=heading, rest=command (function or binary). Always returns 0.
  local title="$1" out pid i=0
  shift
  printf '## %s\n' "$title"
  out=$(mktemp "${TMPDIR:-/tmp}/l2diag.XXXXXX" 2>/dev/null) || { echo "(no scratch file)"; return 0; }
  ( "$@" > "$out" 2>&1 ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
    echo "(probe still running after 3s; abandoned)"
  fi
  wait "$pid" 2>/dev/null
  cut -c1-600 "$out" 2>/dev/null | head -n 80
  rm -f "$out"
  return 0
}

l2_diag_chain() { # $1=pid: that process and every parent up to launchd
  local p="$1" n=0
  while [ "${p:-0}" -gt 0 ] 2>/dev/null && [ "$n" -lt 10 ]; do
    ps -o pid=,ppid=,pgid=,etime=,user=,command= -p "$p" 2>/dev/null
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    n=$((n + 1))
  done
}

l2_diag_memory() { # kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical
  printf 'vm_pressure_level: %s (1 normal, 2 warn, 4 critical)\n' "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)"
  sysctl vm.swapusage 2>/dev/null
  vm_stat 2>/dev/null | head -6
}

l2_diag_launchd() { # $1=label: the job's state, user domain first, then the login session's
  local uid out; uid=$(id -u)
  out=$(launchctl print "gui/$uid/$1" 2>&1) || out=$(launchctl print "user/$uid/$1" 2>&1)
  printf '%s\n' "$out" | head -60
}

l2_diag_jobs() { # the label is not always known to the runner; the job list names it, with pid and last exit
  launchctl list 2>&1 | grep -iE 'autodream|^PID' | head -20
}

l2_diag_sleepwake() { # the kernel's last sleep and wake, so a sleep inside the attempt shows
  local k v
  for k in sleeptime waketime boottime; do
    v=$(sysctl -n "kern.$k" 2>/dev/null | sed -n 's/.*sec = \([0-9]*\).*/\1/p')
    printf '%s: %s (%s)\n' "$k" "${v:-unknown}" "$([ -n "$v" ] && pdate_fmt_epoch "$v" "+%a %b %e %H:%M:%S %Y")"
  done
  pmset -g batt 2>/dev/null | head -2
}

l2_diag_procs() { # every other autodream or claude process, with its parent and age
  ps -axo pid=,ppid=,etime=,command= 2>/dev/null | grep -E 'autodream|claude' | grep -v 'grep -E' | head -40
}

l2_diag_snapshot() { # $1=when: the host's state at one moment
  l2_diag_probe "load average at $1" uptime
  l2_diag_probe "memory pressure at $1" l2_diag_memory
}

l2_diag_start_body() {
  printf 'start_time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf 'runner_pid: %s\n' "$$"
  l2_diag_probe "parent chain at start (runner first)" l2_diag_chain "$$"
  l2_diag_snapshot start
}

l2_diag_start() {
  L2_DIAG_T0=$(date +%s); L2_DIAG_FILE=""; L2_DIAG_JOB=""
  L2_DIAG_FILE=$(mktemp "${TMPDIR:-/tmp}/l2start.XXXXXX" 2>/dev/null) || { L2_DIAG_FILE=""; L2_DIAG_JOB=""; return 0; }
  ( l2_diag_start_body > "$L2_DIAG_FILE" 2>&1 < /dev/null ) &
  L2_DIAG_JOB=$!
}

l2_diag_collect() { # $1=1 to wait for the job and print its output, 0 to discard it
  local i=0
  if [ "$1" = 1 ]; then
    while [ -n "${L2_DIAG_JOB:-}" ] && kill -0 "${L2_DIAG_JOB:-}" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
    cat "${L2_DIAG_FILE:-}" 2>/dev/null
  fi
  [ -n "${L2_DIAG_JOB:-}" ] && { pkill -P "${L2_DIAG_JOB:-}" 2>/dev/null; kill "${L2_DIAG_JOB:-}" 2>/dev/null; wait "${L2_DIAG_JOB:-}" 2>/dev/null; }
  [ -n "${L2_DIAG_FILE:-}" ] && rm -f "${L2_DIAG_FILE:-}"
  return 0
}

l2_diag_end() {
  local n="$1" total="$2" rc="$3" pidfile="$4" f end label worker start
  case "$rc" in 143|137|124) ;; *) l2_diag_collect 0; return 0 ;; esac
  f="$FINDINGS_DIR/l2-attempt-$n.diag"
  end=$(date +%s)
  start=$(l2_diag_collect 1)
  worker=$(cat "$pidfile" 2>/dev/null)
  label="${AUTODREAM_LAUNCHD_LABEL:-${XPC_SERVICE_NAME:-}}"
  {
    printf 'attempt: %s/%s\n' "$n" "$total"
    printf 'exit_code: %s\n' "$rc"
    printf 'worker_pid: %s\n' "${worker:-unknown}"
    printf 'end_epoch: %s\n' "$end"
    printf 'start_epoch: %s\n' "${L2_DIAG_T0:-unknown}"
    printf 'elapsed_seconds: %s\n' "$(( end - ${L2_DIAG_T0:-$end} ))"
    printf 'runner_timeout_fired: no (run.sh applies no timeout to L2, so exit %s came from the engine process or a signal sent to it)\n' "$rc"
    printf 'runner_survived: yes (this runner reached the end of the attempt, so the signal did not hit it)\n'
    printf 'launchd_label: %s\n' "${label:-none}"
    printf '%s\n' "$start"
    l2_diag_snapshot end
    l2_diag_probe "sleep and wake times" l2_diag_sleepwake
    l2_diag_probe "worker at end (gone means it died)" ps -o pid=,ppid=,etime=,command= -p "${worker:-0}"
    l2_diag_probe "other autodream or claude processes at end" l2_diag_procs
    l2_diag_probe "launchd jobs naming autodream at end" l2_diag_jobs
    case "$label" in ""|0) ;; *) l2_diag_probe "launchd job state at end" l2_diag_launchd "$label" ;; esac
  } > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" 2>/dev/null && log "L2 attempt $n exited $rc; diagnostics in $f" || rm -f "$f.tmp" 2>/dev/null
  return 0
}

report_finishes_date() {
  [ -s "$REPORT_PATH" ] || return 1
  report_complete && return 0
  [[ "$TARGET_DATE" < "${AUTODREAM_MARKER_EPOCH:-2026-08-19}" ]]
}

lock_held_by_live_run() {
  local lock="$AUTODREAM_DIR/locks/run-$1.lock" pid
  pid=$(cat "$lock/pid" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

sweep_stranded_pins() {
  local window="${AUTODREAM_UNASSEMBLED_WINDOW:-7}" root="$AUTODREAM_DIR/findings"
  local d label report res n
  [ -d "$root" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    label=$(basename "$d")
    [ -s "$d/pins.jsonl" ] || continue
    [ "$label" = "$TARGET_DATE" ] && [ "${AUTODREAM_FORCE:-0}" = "1" ] && continue
    report="$DREAMS_DIR/$label.md"
    report_finishes "$report" "$label" || continue
    [ ! "$d/pins.jsonl" -nt "$report" ] || continue
    if [ "$label" != "$TARGET_DATE" ] && lock_held_by_live_run "$label"; then
      log "pin sweep: $label has a run in flight; leaving its pins to that run"
      continue
    fi
    res="$d/pins-result.txt"
    if [ -e "$res" ] && [ ! "$d/pins.jsonl" -nt "$res" ]; then
      n=$(awk -F': ' '/^pins_(failed|cli_missing|unreadable|unsupported_harness): / { t += $2 } END { print t + 0 }' "$res" 2>/dev/null)
      [ "${n:-0}" -gt 0 ] || continue
    fi
    if [ ! -s "$d/pin-projects.tsv" ]; then
      log "pin sweep: $label has pins but no pin-projects.tsv, so no project is authorized; they stay in $d/pins.jsonl"
      continue
    fi
    log "pin sweep: applying the pins $label never finished storing"
    bash "$APPLY_PINS" "$d" "$label" >> "$RUN_LOG" 2>&1 \
      || log "pin sweep: apply-pins exited non-zero for $label (counters unavailable)"
    [ ! -r "$res" ] || log "pin sweep: $label: $(tr '\n' ' ' < "$res")"
  done < <(find "$root" -maxdepth 1 -type d -name '2[0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]' 2>/dev/null \
    | sort | tail -n "$window")
}

RUN_LOCK="$AUTODREAM_DIR/locks/run-$TARGET_DATE.lock"
LOCK_HOLDER=""

proc_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }

lock_holder_state() { # $1=lock dir
  local pid start
  pid=$(cat "$1/pid" 2>/dev/null) || pid=""
  [ -n "$pid" ] || return 2
  kill -0 "$pid" 2>/dev/null || return 1
  start=$(cat "$1/start" 2>/dev/null) || start=""
  [ -z "$start" ] || [ "$(proc_start "$pid")" = "$start" ]
}

reclaim_lock() { # $1=lock dir $2=the pid judged stale ("" when none was ever written)
  local dead="$1.stale.$$"
  mv "$1" "$dead" 2>/dev/null || return 0
  if [ "$(cat "$dead/pid" 2>/dev/null)" = "$2" ]; then
    rm -rf "$dead"
    return 0
  fi
  mv "$dead" "$1" 2>/dev/null || { log "WARNING: could not restore another run's lock from $dead"; return 0; }
}

acquire_lock() { # $1=lock dir
  mkdir -p "$(dirname "$1")" 2>/dev/null || return 3
  local tries=0 st pid
  until mkdir "$1" 2>/dev/null; do
    pid=$(cat "$1/pid" 2>/dev/null) || pid=""
    lock_holder_state "$1"; st=$?
    [ "$st" -ne 0 ] || { LOCK_HOLDER="$pid"; return 1; }
    tries=$((tries + 1))
    if [ "$st" -eq 2 ] && [ "$tries" -le 3 ]; then sleep 1; continue; fi
    reclaim_lock "$1" "$pid"
    [ "$tries" -lt 8 ] || { LOCK_HOLDER="${pid:-unknown}"; return 1; }
  done
  printf '%s\n' "$$" > "$1/pid"
  proc_start "$$" > "$1/start"
  return 0
}

release_lock() { # $1=lock dir
  [ "$(cat "$1/pid" 2>/dev/null)" = "$$" ] || return 0
  rm -rf "$1"
}

acquire_run_lock() {
  local rc=0
  acquire_lock "$RUN_LOCK" || rc=$?
  case "$rc" in
    0) return 0 ;;
    3) log "WARNING: could not create $(dirname "$RUN_LOCK"); running without the per-date lock"; return 0 ;;
    *) RUN_LOCK_HOLDER="$LOCK_HOLDER"; return 1 ;;
  esac
}

release_run_lock() { release_lock "$RUN_LOCK"; }

REMOTE_SYNC_LINES=""   # run-stats lines, written into every run-stats block
REMOTE_SYNC_TOTAL=0    # entries configured
REMOTE_SYNC_BAD=0      # entries that did not sync this run: failed or invalid
REMOTE_SYNC_SHORT=0    # entries whose mirror may be short tonight: BAD plus partial and skipped_locked
REMOTE_SYNC_FIRST_ERR=""
REMOTE_SYNC_HELPER=""
REMOTE_SYNCED_LABELS=" "   # labels whose sync was ok or partial this run, space-delimited
REMOTE_SHORT_LABELS=" "    # real labels this run did not fully read (not ok): the next scan lists this date for them
REMOTE_SHORT_QUESTIONS=""  # Open-questions items naming earlier dates a host missed (#230), for the stub report
REMOTE_SHORT_QCOUNT=0      # how many items that is
REMOTE_SHORT_UNREADABLE=0  # earlier nights the scan could not judge
REMOTE_SYNC_NOTMP=0        # 1 when the per-run job dir could not be made, so no job was started
REMOTE_MIRROR_UNKNOWN=0    # mirrors whose size could not be measured tonight
remote_sync_stat() { REMOTE_SYNC_LINES="${REMOTE_SYNC_LINES}$1"$'\n'; }

remote_sync_refuse() {
  log "WARNING: AUTODREAM_REMOTE_ROOTS entry '$1' refused ($3); it is not synced"
  remote_sync_stat "remote_sync_$2: invalid"
  remote_sync_stat "remote_sync_$2_cause: $3"
  REMOTE_SYNC_BAD=$((REMOTE_SYNC_BAD + 1))
  REMOTE_SYNC_SHORT=$((REMOTE_SYNC_SHORT + 1))
  [ "${4:-}" != real ] || REMOTE_SHORT_LABELS="$REMOTE_SHORT_LABELS$2 "
  [ -n "$REMOTE_SYNC_FIRST_ERR" ] || REMOTE_SYNC_FIRST_ERR="$2: invalid ($3)"
}

wait_for_lock_release() {
  local waited=0
  while [ -d "$1" ]; do
    lock_holder_state "$1" || return 0
    [ "$waited" -lt "$2" ] || return 1
    sleep 1; waited=$((waited + 1))
  done
  return 0
}

remote_sync_locked() {
  local rc=0 wait="${AUTODREAM_REMOTE_LOCK_WAIT:-600}"
  case "$wait" in ''|*[!0-9]*) wait=600 ;; esac
  acquire_lock "$4" || rc=$?
  if [ "$rc" -eq 1 ] && wait_for_lock_release "$4" "$((10#$wait))"; then
    rc=0; acquire_lock "$4" || rc=$?
  fi
  case "$rc" in
    0) bash "$REMOTE_SYNC_HELPER" "$1" "$2" "$3" 2>>"$RUN_LOG"
       release_lock "$4" ;;
    1) printf 'skipped_locked (pid %s still held %s after %ss)\n' "${LOCK_HOLDER:-unknown}" "$4" "$wait" ;;
    *) printf 'failed (cannot create %s)\n' "$(dirname "$4")" ;;
  esac
}

remote_mirror_size() {
  [ -d "$1" ] || { echo "0 0"; return 0; }
  local out
  [ -z "$(find "$1" -name $'*\n*' -print -quit 2>/dev/null)" ] || { echo "unknown unknown"; return 0; }
  out=$(set -o pipefail; find "$1" -type f -name '*.jsonl' -exec wc -c {} + 2>/dev/null \
    | awk '$2 == "total" && NF == 2 { next } { f++; b += $1 } END { print f + 0, b + 0 }') \
    || { echo "unknown unknown"; return 0; }
  echo "$out"
}

remote_sync_job() {
  local label="$1" mirror="$AUTODREAM_DIR/remote/$1/projects" t0=$SECONDS status=""
  if [ -z "$REMOTE_SYNC_HELPER" ]; then
    status="failed (remote-sync.sh not found)"
  else
    status=$(remote_sync_locked "$label" "$2" "$mirror" "$AUTODREAM_DIR/locks/remote-$label.lock")
  fi
  { printf '%s\n' "$status" > "$3.status"
    printf '%s\n' "$((SECONDS - t0))" > "$3.secs"
    remote_mirror_size "$mirror" > "$3.mirror"; } 2>/dev/null
}

remote_sync_finish() {
  local label="$1" p="$2" dir="$AUTODREAM_DIR/remote/$1" status="" word cause="" last secs="" size=""
  local mirror="$AUTODREAM_DIR/remote/$1/projects"
  if [ -n "$p" ]; then
    status=$(head -n 1 "$p.status" 2>/dev/null) || status=""
    secs=$(head -n 1 "$p.secs" 2>/dev/null) || secs=""
    size=$(cat "$p.mirror" 2>/dev/null) || size=""
  fi
  [ -n "$size" ] || size=$(remote_mirror_size "$mirror")
  if [ -z "$status" ]; then
    status="failed (remote-sync.sh printed nothing)"
    [ "$REMOTE_SYNC_NOTMP" != 1 ] || status="failed (cannot make a job dir for the sync jobs)"
  fi
  word=${status%% *}
  case "$status" in *" ("*")") cause=${status#* (}; cause=${cause%)} ;; esac
  case "$word" in
    ok|partial)
      REMOTE_SYNCED_LABELS="$REMOTE_SYNCED_LABELS$label "
      if ! { mkdir -p "$dir" && printf '%s\n' "$(date +%Y-%m-%d)" > "$dir/last-ok.tmp.$$" \
             && mv -f "$dir/last-ok.tmp.$$" "$dir/last-ok"; } 2>/dev/null; then
        log "WARNING: remote sync $label: could not stamp $dir/last-ok"
      fi ;;
    skipped_locked) ;;
    invalid) REMOTE_SYNC_BAD=$((REMOTE_SYNC_BAD + 1)) ;;
    *) word=failed; REMOTE_SYNC_BAD=$((REMOTE_SYNC_BAD + 1)) ;;
  esac
  [ "$word" = ok ] || { REMOTE_SYNC_SHORT=$((REMOTE_SYNC_SHORT + 1)); REMOTE_SHORT_LABELS="$REMOTE_SHORT_LABELS$label "; }
  case "$word" in failed|invalid) [ -n "$REMOTE_SYNC_FIRST_ERR" ] || REMOTE_SYNC_FIRST_ERR="$label: ${cause:-$word}" ;; esac
  last=$(head -n 1 "$dir/last-ok" 2>/dev/null) || last=""
  remote_sync_stat "remote_sync_$label: $word"
  remote_sync_stat "remote_sync_${label}_cause: $cause"
  remote_sync_stat "remote_sync_${label}_last_ok: ${last:-never}"
  case "$size" in unknown*) REMOTE_MIRROR_UNKNOWN=$((REMOTE_MIRROR_UNKNOWN + 1)) ;; esac
  remote_sync_stat "remote_mirror_files_$label: ${size% *}"
  remote_sync_stat "remote_mirror_bytes_$label: ${size#* }"
  log "remote sync $label: $status in ${secs:-?}s"
  [ ! -d "$mirror" ] || SESSION_ROOTS="${SESSION_ROOTS:+$SESSION_ROOTS:}$mirror"
}

REMOTE_SHORT_SCAN_DAYS=7
REMOTE_PREV_SHORT=""   # the record of the report this run replaces, comma-separated

remote_report_record() {
  local line
  line=$(printf '%s\n' "$1" | grep '^<!-- autodream:remote-short=.* -->$') || return 1
  line=${line##*$'\n'}
  line=${line#'<!-- autodream:remote-short='}
  printf '%s' "${line% -->}"
}

remote_short_labels() {
  local l all="$REMOTE_SHORT_LABELS" out="" configured="$REMOTE_SYNCED_LABELS $REMOTE_SHORT_LABELS"
  if [ $(( ${ROOTS_FAILED:-0} + ${ROOTS_UNAVAILABLE:-0} + ${PARTIAL_ROOTS:-0} )) -gt 0 ]; then all="$configured"; fi
  for l in ${REMOTE_PREV_SHORT//,/ }; do
    case " $configured " in *" $l "*) ;; *) all="$all $l" ;; esac
  done
  for l in $all; do
    case ",$out," in *",$l,"*) ;; *) out="${out:+$out,}$l" ;; esac
  done
  printf '%s' "$out"
}

remote_short_line() {
  { [ -n "${AUTODREAM_REMOTE_ROOTS:-}" ] || [ -n "$REMOTE_PREV_SHORT" ]; } || return 0
  printf '<!-- autodream:remote-short=%s -->\n' "$(remote_short_labels)"
}

remote_short_scan() {
  local i k n=0 d report body rec label dates
  local dnames=() drecs=()
  REMOTE_SHORT_QUESTIONS=""; REMOTE_SHORT_QCOUNT=0; REMOTE_SHORT_UNREADABLE=0
  i=$REMOTE_SHORT_SCAN_DAYS
  while [ "$i" -ge 1 ]; do
    d=$(pdate_shift "$TARGET_DATE" "-$i" d) || { REMOTE_SHORT_UNREADABLE=$((REMOTE_SHORT_UNREADABLE + 1)); i=$((i - 1)); continue; }
    i=$((i - 1))
    report="$DREAMS_DIR/$d.md"
    if [ ! -e "$report" ]; then
      [ ! -d "$AUTODREAM_DIR/findings/$d" ] || REMOTE_SHORT_UNREADABLE=$((REMOTE_SHORT_UNREADABLE + 1))
      continue
    fi
    if ! body=$(cat "$report" 2>/dev/null); then
      REMOTE_SHORT_UNREADABLE=$((REMOTE_SHORT_UNREADABLE + 1)); continue
    fi
    if rec=$(remote_report_record "$body"); then dnames[n]=$d; drecs[n]=$rec; n=$((n + 1)); fi
  done
  for label in $REMOTE_SYNCED_LABELS; do
    dates=""; k=0
    while [ "$k" -lt "$n" ]; do
      case ",${drecs[k]}," in *",$label,"*) dates="${dates:+$dates }${dnames[k]}" ;; esac
      k=$((k + 1))
    done
    remote_sync_stat "remote_short_dates_$label: ${dates:-none}"
    [ -n "$dates" ] || continue
    log "remote sync $label: earlier dates missing its sessions: $dates"
    REMOTE_SHORT_QCOUNT=$((REMOTE_SHORT_QCOUNT + 1))
    REMOTE_SHORT_QUESTIONS="${REMOTE_SHORT_QUESTIONS}${REMOTE_SHORT_QCOUNT}. **Rebuild the report dates missing $label sessions?**"$'\n'
    REMOTE_SHORT_QUESTIONS="${REMOTE_SHORT_QUESTIONS}   - $label was not fully read on these dates and is syncing again, so those reports are missing its sessions. Nothing retries them."$'\n'
    for d in $dates; do
      REMOTE_SHORT_QUESTIONS="${REMOTE_SHORT_QUESTIONS}   - \`autodream-now.sh $d --force\`"$'\n'
    done
    REMOTE_SHORT_QUESTIONS="${REMOTE_SHORT_QUESTIONS}   - A rebuild replaces that date's report, including any \`## Triage decisions\` already written into it. Leave a date you have already triaged."$'\n'
  done
  remote_sync_stat "remote_short_scan_unreadable: $REMOTE_SHORT_UNREADABLE"
}

drop_stale_report_copies() {
  local s rc keep
  for s in "$REPORT_PATH".stale-*; do
    [ -f "$s" ] || continue
    grep -q '^## Triage decisions' "$s" 2>/dev/null && rc=0 || rc=$?
    if [ "$rc" = 1 ]; then
      rm -f "$s" || log "WARNING: could not remove the superseded report copy $s"
      continue
    fi
    keep="$REPORT_PATH.triaged-${s##*.stale-}"
    [ -e "$keep" ] && keep="$keep.$$"
    mv "$s" "$keep" || log "WARNING: could not set aside the report copy $s that holds triage decisions"
  done
}

sync_remote_roots() {
  local prev f rec
  REMOTE_PREV_SHORT=""
  if [ -f "$REPORT_PATH" ] && prev=$(cat "$REPORT_PATH" 2>/dev/null) && rec=$(remote_report_record "$prev"); then
    REMOTE_PREV_SHORT=$rec
  else
    for f in "$REPORT_PATH".stale-*; do
      [ -f "$f" ] && prev=$(cat "$f" 2>/dev/null) || continue
      if rec=$(remote_report_record "$prev"); then REMOTE_PREV_SHORT=$rec; fi
    done
  fi
  if [ -z "${AUTODREAM_REMOTE_ROOTS:-}" ]; then remote_sync_stat "remote_sync: off"; return 0; fi
  remote_sync_stat "remote_sync: on"
  local entries=() entry label seen=" " sdir="" n i
  local kinds=() keys=() whys=() entrys=() pids=()
  REMOTE_SYNC_FIRST_ERR=""
  REMOTE_SYNC_HELPER=$(find_lib remote-sync.sh) || REMOTE_SYNC_HELPER=""
  local claude_on=1
  resolve_enabled_adapters
  case " $ENABLED_ADAPTERS " in *" claude "*) ;; *) claude_on=0 ;; esac
  local jobs="$AUTODREAM_DIR/remote-jobs" jd jp
  if mkdir -p "$jobs" 2>/dev/null; then
    for jd in "$jobs"/*; do
      [ -d "$jd" ] || continue
      jp=${jd##*/}
      case "$jp" in ''|*[!0-9]*) continue ;; esac
      kill -0 "$jp" 2>/dev/null || rm -rf "$jd"
    done
    rm -rf "${jobs:?}/$$"
    mkdir "$jobs/$$" 2>/dev/null && sdir="$jobs/$$"
  fi
  [ -n "$sdir" ] || { REMOTE_SYNC_NOTMP=1; log "WARNING: remote sync: cannot make a job dir under $jobs, so no host is synced"; }
  read -r -a entries <<< "$AUTODREAM_REMOTE_ROOTS"
  for entry in ${entries[@]+"${entries[@]}"}; do
    REMOTE_SYNC_TOTAL=$((REMOTE_SYNC_TOTAL + 1))
    n=${#kinds[@]}; entrys[n]=$entry
    case "$entry" in *=*) label=${entry%%=*} ;; *) kinds[n]=refuse; keys[n]=invalid; whys[n]="no label=target"; continue ;; esac
    case "$label" in
      ''|.|..|*[!A-Za-z0-9._-]*) kinds[n]=refuse; keys[n]=invalid; whys[n]="label must match [A-Za-z0-9._-]+"; continue ;;
      invalid|*_cause|*_last_ok) kinds[n]=refuse; keys[n]=invalid; whys[n]="label $label is reserved (invalid, or ending in _cause or _last_ok)"; continue ;;
    esac
    case "$seen" in *" $label "*) kinds[n]=refuse; keys[n]=invalid; whys[n]="label $label is used twice"; continue ;; esac
    seen="$seen$label "
    if [ "$claude_on" = 0 ]; then
      kinds[n]=refuse-real; keys[n]=$label; whys[n]="the claude adapter is not enabled (AUTODREAM_ADAPTERS), so no mirror would be scanned"
      continue
    fi
    kinds[n]=sync; keys[n]=$label; pids[n]=""
    if [ -n "$sdir" ]; then
      remote_sync_job "$label" "${entry#*=}" "$sdir/$n" &
      pids[n]=$!
    fi
  done
  i=0
  while [ "$i" -lt "${#kinds[@]}" ]; do
    case "${kinds[i]}" in
      refuse) remote_sync_refuse "${entrys[i]}" "${keys[i]}" "${whys[i]}" ;;
      refuse-real) remote_sync_refuse "${entrys[i]}" "${keys[i]}" "${whys[i]}" real ;;
      *)
        [ -z "${pids[i]}" ] || wait "${pids[i]}" 2>/dev/null
        remote_sync_finish "${keys[i]}" "${sdir:+$sdir/$i}" ;;
    esac
    i=$((i + 1))
  done
  [ -z "$sdir" ] || rm -rf "$sdir"
  remote_short_scan
  log "session roots with remote mirrors: ${SESSION_ROOTS//:/, }"
  [ "$REMOTE_SYNC_TOTAL" -gt 0 ] && [ "$REMOTE_SYNC_BAD" -eq "$REMOTE_SYNC_TOTAL" ] || return 0
  log "remote sync: all $REMOTE_SYNC_TOTAL remote(s) failed"
  [ -x "$AUTODREAM_DIR/notify.sh" ] || return 0
  "$AUTODREAM_DIR/notify.sh" --warning "$TARGET_DATE" \
    "remote session sync failed for all $REMOTE_SYNC_TOTAL remote(s), so their sessions may be missing from the report; first: $REMOTE_SYNC_FIRST_ERR" remote-sync \
    || log "remote sync warning notification returned non-zero (continuing)"
}

session_project() {
  local r rest best=""
  if [ -n "$1" ]; then
    while IFS= read -r r; do
      r=${r%/}
      [ -n "$r" ] || continue
      case $2 in
        "$r"/*/*) [ "${#r}" -gt "${#best}" ] && best=$r ;;
      esac
    done < <(adapter_roots "$1")
  fi
  if [ -n "$best" ]; then
    rest=${2#"$best"/}
    printf '%s' "${rest%%/*}"
    return 0
  fi
  basename "$(dirname "$2")"
}

session_rows() {
  local dir=$1 s hash src proj cwd
  [ -r "$dir/sessions.txt" ] || return 1
  while IFS= read -r s <&3; do
    [ -n "$s" ] || continue
    hash=$(session_hash "$s") || continue
    src=$(awk -F'\t' -v h="$hash" '$1 == h { print $2; exit }' "$dir/sessions-source.txt" 2>/dev/null)
    proj=$(session_project "$src" "$s")
    case $proj in ''|*$'\t'*|*$'\n'*) continue ;; esac
    cwd="?"
    if [ -n "$src" ]; then
      cwd=$(adapter_run "$src" project "$s" 2>/dev/null </dev/null) || cwd="?"
      [ -n "$cwd" ] || cwd="?"
    fi
    case $cwd in *$'\t'*|*$'\n'*) cwd="?" ;; esac
    case $proj in
      -*) if [ "$cwd" != "?" ] && [ "$(encode_project "$cwd")" != "$proj" ]; then cwd="?"; fi ;;
    esac
    printf '%s\t%s\t%s\n' "$hash" "$proj" "$cwd"
  done 3< "$dir/sessions.txt"
}

thread_repo_hint() {
  local cwd=$1 common bare
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  common=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null) || return 0
  case "$common" in /*) ;; *) common="$cwd/$common" ;; esac
  common=$(cd -P "$common" 2>/dev/null && pwd -P) || return 0
  bare=$(git -C "$cwd" rev-parse --is-bare-repository 2>/dev/null) || return 0
  if [ "$bare" = true ]; then
    printf '%s' "$common"
  else
    dirname "$common"
  fi
}

thread_stats_fields() {
  local stats=$1 count nested
  count=0
  nested=false
  if [ -r "$stats" ] && jq -e '
    type == "object" and
    (.user_message_count | type == "number" and . >= 0 and floor == .) and
    ((.nested | type) == "boolean" or (.isSidechain | type) == "boolean")
  ' "$stats" >/dev/null 2>&1; then
    count=$(jq -r '.user_message_count | floor' "$stats")
    nested=$(jq -r 'if (.nested | type) == "boolean" then .nested else .isSidechain end' "$stats")
    printf '%s\t%s\ttrue' "$nested" "$count"
  else
    printf '%s\t%s\tfalse' "$nested" "$count"
  fi
}

thread_source_rows() {
  local from=$1 to=$2 tmp keys paths unique_paths finding date_dir date hash session src cwd repo fields nested count measured roots root end_date
  local source_map=${AUTODREAM_SOURCE_MAP:-}
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/thread-source-rows.XXXXXX" 2>/dev/null) || return 1
  keys="$tmp/history-keys.tsv"
  paths="$tmp/path-map.jsonl"
  unique_paths="$tmp/unique-paths.tsv"
  : > "$keys" || { rmdir "$tmp" 2>/dev/null; return 1; }
  : > "$paths" || { rmdir "$tmp" 2>/dev/null; return 1; }
  [ -n "$source_map" ] || source_map=$(cat "$FINDINGS_DIR/sessions-source.txt" 2>/dev/null)

  for date_dir in "$AUTODREAM_DIR"/findings/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
    [ -d "$date_dir" ] || continue
    date=${date_dir##*/}
    case "$date" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) pdate_epoch "$date" >/dev/null 2>&1 || continue ;;
      *) continue ;;
    esac
    [[ "$date" < "$from" || "$date" > "$to" ]] && continue
    [ "$date" = "$TARGET_DATE" ] && continue
    for finding in "$date_dir"/*.json; do
      [ -f "$finding" ] || continue
      case "$finding" in *.stats.json) continue ;; esac
      hash=${finding##*/}
      hash=${hash%.json}
      case "$hash" in
        [0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef])
          printf '%s\t%s\n' "$date" "$hash" >> "$keys" ;;
      esac
    done
  done

  end_date=${ENUM_END:-$to}
  for src in $ENABLED_ADAPTERS; do
    while IFS= read -r root; do
      [ -n "$root" ] && [ -d "$root" ] || continue
      while IFS= read -r -d '' session; do
        hash=$(session_hash "$session") || continue
        awk -F '\t' -v h="$hash" '($2 "x") == (h "x") { found = 1; exit } END { exit !found }' "$keys" || continue
        case "$session" in *$'\t'*|*$'\n'*) continue ;; esac
        cwd=$(adapter_run "$src" project "$session" 2>/dev/null </dev/null) || cwd=""
        case "$cwd" in *$'\t'*|*$'\n'*) cwd="" ;; esac
        repo=$(thread_repo_hint "$cwd")
        case "$repo" in *$'\t'*|*$'\n'*) repo="" ;; esac
        jq -cn --arg hash "$hash" --arg source "$src" --arg path "$session" --arg cwd "$cwd" --arg repo "$repo" \
          '{hash:$hash,source:$source,session_path:$path,cwd:$cwd,repo:$repo}' >> "$paths"
      done < <(adapter_run "$src" enumerate "$root" "$from" "$end_date" 2>/dev/null)
    done < <(adapter_roots "$src")
  done

  python3 - "$paths" "$unique_paths" <<'PY_THREAD_PATHS'
import json
import sys

source, destination = sys.argv[1:]
by_hash = {}
for line in open(source, encoding="utf-8"):
    if line.strip():
        item = json.loads(line)
        key = item["hash"]
        identity = (item["source"], item["session_path"], item["cwd"], item["repo"])
        by_hash.setdefault(key, set()).add(identity)
with open(destination, "w", encoding="utf-8") as output:
    for key in sorted(by_hash):
        values = by_hash[key]
        if len(values) == 1:
            source_name, path, cwd, repo = next(iter(values))
            output.write("%s\t%s\t%s\t%s\t%s\n" % (key, source_name, path, cwd, repo))
PY_THREAD_PATHS
  if [ "$?" -ne 0 ]; then
    find "$tmp" -depth -type f -exec unlink {} \; 2>/dev/null
    rmdir "$tmp" 2>/dev/null
    return 1
  fi

  while IFS= read -r session <&3; do
    [ -n "$session" ] || continue
    hash=$(session_hash "$session") || continue
    src=$(printf '%s\n' "$source_map" | awk -F '\t' -v h="$hash" '($1 "x") == (h "x") { print $2; exit }')
    [ -n "$src" ] || continue
    cwd=$(printf '%s\n' "${SESSION_ROWS:-}" | awk -F '\t' -v h="$hash" '($1 "x") == (h "x") { print $3; exit }')
    [ "$cwd" = "?" ] && cwd=""
    repo=$(thread_repo_hint "$cwd")
    fields=$(thread_stats_fields "$FINDINGS_DIR/$hash.stats.json")
    IFS=$'\t' read -r nested count measured <<EOF_THREAD_FIELDS
$fields
EOF_THREAD_FIELDS
    jq -cn --arg date "$to" --arg hash "$hash" --arg source "$src" --arg path "$session" \
      --arg cwd "$cwd" --arg repo "$repo" --argjson nested "$nested" --argjson count "$count" \
      --argjson measured "$measured" \
      '{date:$date,hash:$hash,source:$source,session_path:$path,cwd:$cwd,repo:$repo,nested:$nested,user_message_count:$count,measured:$measured}'
  done 3< "$SESSIONS_LIST"

  while IFS=$'\t' read -r date hash; do
    [ -n "$date" ] && [ -n "$hash" ] || continue
    row=$(awk -F '\t' -v h="$hash" '($1 "x") == (h "x") { n++; line=$0 } END { if (n == 1) print line }' "$unique_paths")
    [ -n "$row" ] || continue
    IFS=$'\t' read -r _hash src session cwd repo <<EOF_THREAD_PATH
$row
EOF_THREAD_PATH
    fields=$(thread_stats_fields "$AUTODREAM_DIR/findings/$date/$hash.stats.json")
    IFS=$'\t' read -r nested count measured <<EOF_THREAD_FIELDS
$fields
EOF_THREAD_FIELDS
    jq -cn --arg date "$date" --arg hash "$hash" --arg source "$src" --arg path "$session" \
      --arg cwd "$cwd" --arg repo "$repo" --argjson nested "$nested" --argjson count "$count" \
      --argjson measured "$measured" \
      '{date:$date,hash:$hash,source:$source,session_path:$path,cwd:$cwd,repo:$repo,nested:$nested,user_message_count:$count,measured:$measured}'
  done < "$keys"

  find "$tmp" -depth -type f -exec unlink {} \; 2>/dev/null
  rmdir "$tmp" 2>/dev/null
}

thread_refresh_pending() {
  local state=$1 rows=$2 line date hash findings
  THREADS_REFRESH_PENDING=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    date=$(printf '%s\n' "$line" | jq -r '.date')
    [ "$date" = "$TARGET_DATE" ] || continue
    hash=$(printf '%s\n' "$line" | jq -r '.hash')
    printf '%s\n' "$state" | jq -e --arg date "$date" --arg hash "$hash" \
      'any(.[]; any(.sessions[]?; .date == $date and .hash == $hash))' >/dev/null 2>&1 || continue
    findings="$FINDINGS_DIR/$hash.json"
    jq -s -e "$L1_FINDINGS_OK" "$findings" >/dev/null 2>&1 && continue
    THREADS_REFRESH_PENDING="${THREADS_REFRESH_PENDING}${date}"$'\t'"${hash}"$'\n'
  done <<EOF_THREAD_ROWS
$rows
EOF_THREAD_ROWS
}

thread_refresh_accepted() {
  local line date hash findings
  THREADS_REFRESH_KEYS=""
  while IFS=$'\t' read -r date hash; do
    [ -n "$date" ] && [ -n "$hash" ] || continue
    findings="$FINDINGS_DIR/$hash.json"
    jq -s -e "$L1_FINDINGS_OK" "$findings" >/dev/null 2>&1 || continue
    THREADS_REFRESH_KEYS="${THREADS_REFRESH_KEYS}${date}"$'\t'"${hash}"$'\n'
  done <<EOF_THREAD_PENDING
${THREADS_REFRESH_PENDING:-}
EOF_THREAD_PENDING
}

run_threads_update() {
  local updater from
  updater=$(find_lib threads.sh) || updater=""
  THREADS_SUMMARY="threads_state: ok
threads_link: not_needed
threads_linked: 0
threads_rejected: 0
threads_close_refused: 0
threads_unmeasured: 0
threads_calls: 0
threads_groups_failed: 0
threads_unassigned: 0"
  [ -n "$updater" ] || return 0
  from=$(pdate_shift "$TARGET_DATE" -13 d) || return 0
  THREADS_SUMMARY=$(printf '%s\n' "$THREAD_SOURCE_ROWS" | env \
    AUTODREAM_THREADS_TIMEOUT_BIN="$TIMEOUT_BIN" \
    THREADS_REFRESH_KEYS="${THREADS_REFRESH_KEYS:-}" \
    AUTODREAM_DIR="$AUTODREAM_DIR" \
    "$updater" update "$TARGET_DATE" 2>> "$RUN_LOG") || {
      THREADS_SUMMARY="threads_state: ok
threads_link: failed
threads_linked: 0
threads_rejected: 0
threads_close_refused: 0
threads_unmeasured: 0
threads_calls: 0
threads_groups_failed: 0
threads_unassigned: 0"
    }
  clean_work_bucket
}

run_threads_dashboard() {
  local renderer output status rc=0
  renderer=$(find_lib threads.sh) || renderer=""
  if [ -n "$renderer" ]; then
    output=$(env AUTODREAM_DIR="$AUTODREAM_DIR" DREAMS_DIR="$DREAMS_DIR" \
      /bin/bash "$renderer" render 2>> "$RUN_LOG") || rc=$?
    status=$(printf '%s\n' "$output" | sed -n 's/^threads_render: //p' | tail -1)
  else
    status=failed
  fi
  case "$status" in ok|stale|failed|skipped_unreadable) ;; *) status=failed ;; esac
  if [ "$rc" -ne 0 ] && [ "$status" = ok ]; then status=failed; fi
  THREADS_SUMMARY="${THREADS_SUMMARY}
threads_render: $status"
  case "$status" in failed|stale) log "WARNING: thread dashboard render $status; output was not replaced" ;; esac
  return 0
}

write_threads_report_input() {
  local reporter status unassigned
  reporter=$(find_lib threads.sh) || reporter=""
  [ -n "$reporter" ] || return 1
  status=$(printf '%s\n' "$THREADS_SUMMARY" | sed -n 's/^threads_link: //p' | tail -1)
  unassigned=$(printf '%s\n' "$THREADS_SUMMARY" | sed -n 's/^threads_unassigned: //p' | tail -1)
  env AUTODREAM_DIR="$AUTODREAM_DIR" DREAMS_DIR="$DREAMS_DIR" \
    AUTODREAM_THREADS_LINK_STATUS="${status:-failed}" AUTODREAM_THREADS_UNASSIGNED="${unassigned:-0}" \
    /bin/bash "$reporter" report "$TARGET_DATE" \
    > "$FINDINGS_DIR/dropped-threads.md" 2>> "$RUN_LOG"
}

pin_projects_from_rows() {
  awk -F'\t' '
    NF < 3 { next }
    !($2 in seen) { seen[$2] = 1; order[++n] = $2 }
    !(($2, $3) in pair) { pair[$2, $3] = 1; count[$2]++; cwd[$2] = $3 }
    END {
      for (i = 1; i <= n; i++) {
        p = order[i]
        printf "%s\t%s\n", p, (count[p] == 1 && cwd[p] != "?" ? cwd[p] : "")
      }
    }
  '
}

write_pin_projects() {
  local dir=$1
  rm -f "$dir/pin-projects.tsv" || return 1
  [ "${PIN_PROJECTS_BUILT:-0}" = "1" ] || return 1
  if [ -n "$PIN_PROJECTS_TSV" ]; then printf '%s\n' "$PIN_PROJECTS_TSV"; fi > "$dir/pin-projects.tsv.tmp" \
    && mv "$dir/pin-projects.tsv.tmp" "$dir/pin-projects.tsv"
}

write_session_cwds() {
  local dir=$1 tmp
  rm -f "$dir/session-cwds.tsv" || return 1
  [ "${PIN_PROJECTS_BUILT:-0}" = "1" ] || return 1
  tmp=$(mktemp "$dir/session-cwds.tsv.tmp.XXXXXX") || return 1
  if { [ -n "$SESSION_CWDS_TSV" ] && printf '%s\n' "$SESSION_CWDS_TSV"; } > "$tmp" \
     && mv -f "$tmp" "$dir/session-cwds.tsv"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

restore_pins_ledger() {
  local f="$1/pins-applied.tsv" cur
  [ "${PINS_LEDGER_OK:-1}" = "1" ] || return 1
  if [ "${PINS_LEDGER_PRESENT:-0}" != "1" ]; then
    [ -e "$f" ] || return 0
    log "pins-applied.tsv appeared while the models ran; removing it"
    rm -f "$f"
    return
  fi
  cur=$(cat -- "$f" 2>/dev/null && printf x) || cur=""
  [ "$cur" != "$PINS_LEDGER_SNAPSHOT_X" ] || return 0
  log "pins-applied.tsv changed while the models ran; restoring it"
  printf '%s' "${PINS_LEDGER_SNAPSHOT_X%x}" > "$f.tmp" && mv -f "$f.tmp" "$f"
}

net_up() { # net_up [-l secs] URL: exit 0 if that host answers (any HTTP reply beats no reply)
  local code rc hdr limit maxt up=1
  local -a bound=()
  limit="${AUTODREAM_NETUP_LIMIT:-8}"
  if [ "${1:-}" = "-l" ]; then limit="$2"; shift 2; fi
  [ -n "${1:-}" ] || return 0
  [ -z "${TIMEOUT_BIN:-}" ] || bound=("$TIMEOUT_BIN" -k 2 "$limit")
  hdr=$(mktemp "${TMPDIR:-/tmp}/netup.XXXXXX" 2>/dev/null) || hdr=""
  maxt=5; [ "$limit" -lt "$maxt" ] 2>/dev/null && maxt="$limit"
  code=$(${bound[@]+"${bound[@]}"} curl -s --max-time "$maxt" -o /dev/null ${hdr:+-D "$hdr"} -w '%{http_code}' "$1" 2>/dev/null); rc=$?
  { [ "$rc" -eq 127 ] || [ "$rc" -eq 126 ]; } && up=0
  if [ "$up" -ne 0 ] && [ -n "$code" ] && [ "$code" != "000" ]; then up=0; fi
  if [ "$up" -ne 0 ] && [ -n "$hdr" ] && grep -q '^HTTP/' "$hdr" 2>/dev/null; then up=0; fi
  [ -z "$hdr" ] || rm -f "$hdr"
  return "$up"
}

NET_DOWN_SECONDS=0

l1_probe_urls() {
  local src url
  while IFS=$'\t' read -r src url; do
    [ -n "$src" ] && [ -n "$url" ] || continue
    printf '%s\n' "$url"
  done <<< "${AUTODREAM_L1_PROBE_URLS:-}" | awk 'NF && !seen[$0]++'
}

l2_probe_url() { provider_probe_url "$L2_ENGINE" "$L2_MODEL" 2>/dev/null; }

wait_for_network() { # 0 = network is up, 1 = gave up after the cap; no-op when AUTODREAM_NETCHECK=0
  [ "${AUTODREAM_NETCHECK:-1}" != "0" ] || return 0
  [ -n "${1:-}" ] || return 0
  local start elapsed step left lim url down cap="${AUTODREAM_NETCHECK_CAP:-1800}" probe="${AUTODREAM_NETUP_LIMIT:-8}"
  case "$cap" in ''|*[!0-9]*) log "AUTODREAM_NETCHECK_CAP='$cap' is not a number; using 1800"; cap=1800 ;; esac
  start=$(date +%s)
  while :; do
    down=1; asked=0
    while IFS= read -r url; do
      left=$(( cap - ($(date +%s) - start) ))
      [ "$left" -ge 1 ] || [ "$asked" -eq 0 ] || break
      [ "$left" -ge 1 ] || left=1
      asked=1
      lim=$probe; [ "$left" -lt "$lim" ] && lim=$left
      if net_up -l "$lim" "$url"; then down=0; break; fi
      log "no answer from $url"
    done <<< "$1"
    [ "$down" -eq 1 ] || break
    elapsed=$(( $(date +%s) - start ))
    if [ "$elapsed" -ge "$cap" ]; then
      NET_DOWN_SECONDS=$((NET_DOWN_SECONDS + elapsed))
      log "network still down after ~${elapsed}s of checks (cap ${cap}s)"
      return 1
    fi
    log "waiting for network to return... (${elapsed}s)"
    step=$(( cap - elapsed )); [ "$step" -gt 15 ] && step=15
    sleep "$step"
  done
  [ -z "${elapsed:-}" ] || NET_DOWN_SECONDS=$((NET_DOWN_SECONDS + $(date +%s) - start))
  return 0
}

export L1_FINDINGS_OK='length == 1 and (.[0] | type == "object" and (.findings | type) == "array")'

l1_missing_count() { # count sessions in $SESSIONS_LIST that still have no findings JSON
  local m=0 s h
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    h=$(session_hash "$s") || { m=$((m + 1)); continue; }
    jq -s -e "$L1_FINDINGS_OK" "$FINDINGS_DIR/$h.json" >/dev/null 2>&1 || m=$((m + 1))
  done < "$SESSIONS_LIST"
  printf '%s' "$m"
}

l1_missing_engines() {
  local s h src e out=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    h=$(session_hash "$s") || continue
    jq -s -e "$L1_FINDINGS_OK" "$FINDINGS_DIR/$h.json" >/dev/null 2>&1 && continue
    src=$(printf '%s\n' "$AUTODREAM_SOURCE_MAP" | awk -F'\t' -v h="$h" '$1 == h { print $2; exit }')
    e=$(printf '%s\n' "$AUTODREAM_L1_ENGINES" | awk -F'\t' -v s="$src" '$1 == s { print $2; exit }')
    [ -n "$e" ] && out="$out$e"$'\n'
  done < "$SESSIONS_LIST"
  printf '%s' "$out" | sort -u
}

l1_chunk_totals() {
  local plans calls
  plans=$(awk 'NF >= 3 { n[$1] = $2; e[$1] = $3 } END { for (h in n) { s++; c += n[h]; x += e[h] } printf "%d %d %d", s, c, x }' \
            "$FINDINGS_DIR/l1-chunks.txt" 2>/dev/null)
  calls=$(grep -c . "$FINDINGS_DIR/l1-chunk-calls.txt" 2>/dev/null || true)
  printf '%s %s\n' "${plans:-0 0 0}" "${calls:-0}"
}

l1_chunk_answers() {
  find "$FINDINGS_DIR/.chunks" -type f -name '*.chunkout' 2>/dev/null | wc -l | tr -d ' '
}

findings_has_error() { # $1=findings file
  jq -e 'type == "object" and has("error")' "$1" >/dev/null 2>&1
}

findings_json_count() {
  find "$FINDINGS_DIR" -maxdepth 1 -type f -name '*.json' ! -name '*.stats.json' 2>/dev/null \
    | wc -l | tr -d ' '
}

worklist_hashes() {
  [ -f "$SESSIONS_LIST" ] || return 0
  local _s _h
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    _h=$(session_hash "$_s") || continue
    printf '%s\n' "$_h"
  done < "$SESSIONS_LIST"
}
reconcile_findings_with_worklist() {
  FINDINGS_OUTSIDE_WORKLIST=0; OUTSIDE_FINDINGS_NAMES=""
  local _hashes _f _h _dest _q="$FINDINGS_DIR/outside-worklist"
  _hashes=$(worklist_hashes)
  for _f in "$_q"/*.json; do
    [ -f "$_f" ] || continue
    _h=$(basename "$_f" .json)
    printf '%s\n' "$_hashes" | grep -qxF "$_h" || continue
    if [ -e "$FINDINGS_DIR/$_h.json" ]; then
      log "WARNING: $_h.json is in outside-worklist/ and in the findings dir; leaving the set-aside copy where it is"
      continue
    fi
    if mv "$_f" "$FINDINGS_DIR/$_h.json" 2>/dev/null; then
      log "restored $_h.json from outside-worklist/: its session is in this run's worklist again"
    else
      log "WARNING: could not restore $_f; this session will be triaged again"
    fi
  done
  for _f in "$FINDINGS_DIR"/*.json; do
    [ -f "$_f" ] || continue
    _h=$(basename "$_f" .json)
    case "$_h" in *[!0-9a-f]*|"") continue ;; esac
    [ "${#_h}" -eq 12 ] || continue
    printf '%s\n' "$_hashes" | grep -qxF "$_h" && continue
    _dest="$_q/$_h.json"
    [ ! -e "$_dest" ] || _dest="$_q/$_h.json.$(date +%s)"
    if ! { mkdir -p "$_q" && mv "$_f" "$_dest"; } 2>/dev/null; then
      log "WARNING: could not set aside $_f; L2 will read it though its session is not in this run's worklist"
      continue
    fi
    FINDINGS_OUTSIDE_WORKLIST=$((FINDINGS_OUTSIDE_WORKLIST + 1))
    OUTSIDE_FINDINGS_NAMES="${OUTSIDE_FINDINGS_NAMES:+$OUTSIDE_FINDINGS_NAMES }$_h"
  done
  if [ "$FINDINGS_OUTSIDE_WORKLIST" -gt 0 ]; then
    log "WARNING: $FINDINGS_OUTSIDE_WORKLIST findings JSON(s) belong to no session in this run's worklist; moved to $_q so L2 does not read them: $OUTSIDE_FINDINGS_NAMES"
  fi
}
L1_CACHE_DROPPED=0
drop_unacceptable_l1_cache() {
  L1_CACHE_DROPPED=0
  local _h _f _src _unrouted="" _unverified="" _chunks=0 _served=0
  [ "${AUTODREAM_L1_REQUIRE_SERVED:-0}" = 1 ] && _served=1
  while IFS= read -r _h; do
    [ -n "$_h" ] || continue
    _f="$FINDINGS_DIR/$_h.json"
    [ -f "$_f" ] || continue
    if l1_record_has_no_engine "$_f"; then
      _src=$(printf '%s\n' "$AUTODREAM_SOURCE_MAP" | awk -F'\t' -v h="$_h" '$1 == h { print $2; exit }')
      if l1_source_has_engine "$_src"; then
        rm -f "$_f" "$_f.served"
        L1_CACHE_DROPPED=$((L1_CACHE_DROPPED + 1)); _unrouted="${_unrouted:+$_unrouted }$_h"
        continue
      fi
    fi
    [ "$_served" = 1 ] || continue
    l1_record_is_runner_only "$_f" && continue
    [ "$(served_verdict "$_f")" = match ] && continue
    rm -f "$_f" "$_f.served"
    L1_CACHE_DROPPED=$((L1_CACHE_DROPPED + 1)); _unverified="${_unverified:+$_unverified }$_h"
  done < <(worklist_hashes)
  if [ "$_served" = 1 ]; then
    for _f in "$FINDINGS_DIR"/.chunks/*/*.chunkout; do
      [ -f "$_f" ] || continue
      [ "$(served_verdict "$_f")" = match ] && continue
      rm -f "$_f" "$_f.served"
      L1_CACHE_DROPPED=$((L1_CACHE_DROPPED + 1)); _chunks=$((_chunks + 1))
    done
  fi
  [ -z "$_unrouted" ] || log "dropped no-engine record(s) whose source now has an L1 engine, to triage again: $_unrouted"
  [ -z "$_unverified" ] && [ "$_chunks" -eq 0 ] \
    || log "AUTODREAM_L1_REQUIRE_SERVED=1: dropped cached L1 result(s) no served verdict vouches for, to triage again (sessions: ${_unverified:-none}; chunk answers: $_chunks)"
}
l1_record_has_no_engine() { # $1=findings JSON
  jq -s -e 'length == 1 and (.[0] | (.no_engine == true or ((.error // "") | tostring | startswith("no L1 engine for this session"))) and .findings == [])' "$1" >/dev/null 2>&1
}
l1_source_has_engine() { # $1=source adapter
  local _e _m
  case "$1" in ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;; esac
  _e=$(printf '%s\n' "$AUTODREAM_L1_ENGINES" | awk -F'\t' -v s="$1" '$1 == s { print $2; exit }')
  _m=$(printf '%s\n' "$AUTODREAM_L1_MODELS" | awk -F'\t' -v s="$1" '$1 == s { print $2; exit }')
  case "$_e" in ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;; esac
  [ -n "$_m" ] && [ -x "$ADAPTERS_DIR/$_e/adapter.sh" ]
}
l1_record_is_runner_only() { # $1=findings JSON
  [ "$(served_verdict "$1")" = runner ] || return 1
  jq -s -e 'length == 1 and .[0].findings == []' "$1" >/dev/null 2>&1
}
served_verdict() { cut -s -f4 "$1.served" 2>/dev/null | head -1; } # $1=answer -> its stored verdict
scan_worklist_leftovers() {
  L1_ERR_ORPHANED=0; ORPHAN_ERR_NAMES=""
  local _hashes _f _h
  _hashes=$(worklist_hashes)
  for _f in "$FINDINGS_DIR"/*.json.err; do
    [ -f "$_f" ] || continue
    _h=$(basename "$_f" .json.err)
    [ ! -f "$FINDINGS_DIR/$_h.json" ] || continue
    printf '%s\n' "$_hashes" | grep -qxF "$_h" && continue
    L1_ERR_ORPHANED=$((L1_ERR_ORPHANED + 1))
    ORPHAN_ERR_NAMES="${ORPHAN_ERR_NAMES:+$ORPHAN_ERR_NAMES }$_h"
  done
  if [ "$L1_ERR_ORPHANED" -gt 0 ]; then
    log "WARNING: $L1_ERR_ORPHANED .err file(s) have no findings JSON and belong to no session in this run's worklist, so nothing will retry them: $ORPHAN_ERR_NAMES"
  fi
}

day_slice() { # $1=transcript $2=slice path
  [ "$WINDOW_ON" = 1 ] || return 1
  bash "$SESSION_WINDOW" day-file "$1" "$WIN_START_EPOCH" "$WIN_END_EPOCH" "$2" </dev/null 2>/dev/null
}

compute_session_stats() {
  local session hash stats
  while IFS= read -r session; do
    [ -n "$session" ] || continue
    hash=$(session_hash "$session") || {
      log "  WARNING: could not derive an artifact hash for $session; no stats sidecar will exist for it"
      continue
    }
    stats="$FINDINGS_DIR/$hash.stats.json"
    rm -f "$stats"
    local src stats_rc=1 statsin="$session" normtmp="" daytmp="" slice_rc
    src=$(awk -F'\t' -v h="$hash" '$1 == h { print $2; exit }' "$FINDINGS_DIR/sessions-source.txt" 2>/dev/null)
    local own_adapter=0
    if [ -z "${AUTODREAM_STATS_BIN:-}" ] && [ -n "$src" ] && [ "$src" != "claude" ] \
       && [ -x "$(adapters_root 2>/dev/null)/$src/adapter.sh" ]; then
      own_adapter=1
      if [ "$(adapter_manifest_get "$src" '.normalize' 2>/dev/null)" = "true" ]; then
        normtmp="$FINDINGS_DIR/$hash.statsin.jsonl"
        if adapter_run "$src" normalize "$session" "$normtmp" >/dev/null 2>&1 && [ -s "$normtmp" ]; then
          statsin="$normtmp"
        else
          rm -f "$normtmp"; normtmp=""
        fi
      fi
    fi
    daytmp="$FINDINGS_DIR/$hash.statsday.jsonl"
    day_slice "$statsin" "$daytmp"; slice_rc=$?
    case "$slice_rc" in
      0) statsin="$daytmp"; SESSIONS_WINDOWED=$((SESSIONS_WINDOWED + 1)) ;;
      1) daytmp="" ;;
      *) daytmp=""; log "  WARNING: could not cut $session to $TARGET_DATE; its stats cover the whole transcript" ;;
    esac
    if [ "$own_adapter" = 1 ]; then
      adapter_run "$src" stats "$statsin" "$stats" >/dev/null 2>&1; stats_rc=$?
    elif [ -x "$STATS" ]; then
      "$STATS" "$statsin" "$stats" >/dev/null 2>&1; stats_rc=$?
    fi
    [ -z "$normtmp" ] || rm -f "$normtmp"
    [ -z "$daytmp" ] || rm -f "$daytmp"
    if [ "$stats_rc" -eq 0 ] && [ -s "$stats" ] && jq -e 'type == "object"' "$stats" >/dev/null 2>&1; then
      echo "stats: $session ($hash)" >&2
    else
      rm -f "$stats"
      echo "stats failed: $session ($hash); continuing without precomputed stats" >&2
    fi
  done < "$SESSIONS_LIST"
}

compute_overlap_stats() {
  OVERLAP_EVENTS=0
  SESSIONS_WITH_OVERLAP=0
  OVERLAP_MEASURED=0
  if [ ! -x "$OVERLAP" ]; then
    log "overlap not measured: overlap-stats.sh not found/executable (counts left at 0/0)"
    return 0
  fi
  local json events involved
  json=$("$OVERLAP" "$FINDINGS_DIR" 2>>"$RUN_LOG")
  if [ -z "$json" ]; then
    log "overlap not measured: overlap-stats.sh produced no output (counts left at 0/0)"
    return 0
  fi
  events=$(printf '%s' "$json" | jq -r '.overlap_events // empty' 2>/dev/null)
  involved=$(printf '%s' "$json" | jq -r '.sessions_with_overlap // empty' 2>/dev/null)
  if [ -z "$events" ] || [ -z "$involved" ]; then
    log "overlap not measured: overlap-stats.sh output was unparseable (counts left at 0/0)"
    return 0
  fi
  OVERLAP_EVENTS="$events"
  SESSIONS_WITH_OVERLAP="$involved"
  OVERLAP_MEASURED=1
  log "overlap: $OVERLAP_EVENTS pair(s), $SESSIONS_WITH_OVERLAP session(s) involved"
}

session_parent() {
  local d depth=0
  d=$(dirname "$1")
  while [ "$depth" -lt 6 ] && [ "$d" != / ] && [ "$d" != . ]; do
    [ -f "$d.jsonl" ] && { printf '%s' "$d.jsonl"; return 0; }
    d=$(dirname "$d"); depth=$((depth + 1))
  done
  return 1
}

fanout_rows() {
  local dir=$1 s hash parent
  [ -r "$dir/sessions.txt" ] || return 0
  while IFS= read -r s <&3; do
    [ -n "$s" ] || continue
    hash=$(session_hash "$s") || continue
    jq -e '.isSidechain == true or .nested == true' "$dir/$hash.stats.json" >/dev/null 2>&1 || continue
    parent=$(session_parent "$s") || case $s in
      */subagents/*) parent=${s%%/subagents/*}.jsonl ;;
      *) parent=$(dirname "$s").jsonl ;;
    esac
    printf '%s\t%s\n' "$hash" "$(session_hash "$parent")"
  done 3< "$dir/sessions.txt"
}

compute_fanout_stats() {
  local json hash row ungated=0 rows=""
  FANOUT_TOP=0; FANOUT_NESTED=0; FANOUT_PARENTS=0; FANOUT_LARGEST=0
  for json in "$FINDINGS_DIR"/*.json; do
    [ -f "$json" ] || continue
    case "$json" in *.stats.json) continue ;; esac
    grep -q '"skipped": *"below_noise_gate"' "$json" 2>/dev/null && continue
    ungated=$((ungated + 1))
    hash=$(basename "$json" .json)
    row=$(printf '%s\n' "$FANOUT_ROWS" | grep -m1 "^$hash"$'\t') || continue
    rows="${rows}${row}"$'\n'
  done
  if [ -n "$rows" ]; then printf '%s' "$rows" > "$FINDINGS_DIR/fanouts.tsv"; else : > "$FINDINGS_DIR/fanouts.tsv"; fi
  [ -n "$rows" ] || { FANOUT_TOP=$ungated; return 0; }
  FANOUT_NESTED=$(printf '%s' "$rows" | grep -c .)
  FANOUT_TOP=$((ungated - FANOUT_NESTED))
  FANOUT_PARENTS=$(printf '%s' "$rows" | cut -f2 | sort -u | grep -c .)
  FANOUT_LARGEST=$(printf '%s' "$rows" | cut -f2 | sort | uniq -c | sort -rn | awk 'NR == 1 { print $1 }')
}

write_rollup() {
  local out
  rm -f "$FINDINGS_DIR/rollup.tsv" "$FINDINGS_DIR/categories.tsv" "$FINDINGS_DIR/findings.tsv" 2>/dev/null
  if [ -z "$ROLLUP" ]; then
    log "WARNING: rollup.sh not found; L2 has no rollup.tsv to count from"
    printf 'rollup: helper missing\n' >> "$FINDINGS_DIR/run-stats.txt"
    return 0
  fi
  out=$(AUTODREAM_SOURCE_MAP="${AUTODREAM_SOURCE_MAP:-}" AUTODREAM_SESSION_ROWS="${SESSION_ROWS:-}" \
    bash "$ROLLUP" "$FINDINGS_DIR" 2>>"$RUN_LOG" | tail -1)
  case "$out" in
    "rollup: rows="*) ;;
    *) log "WARNING: rollup.sh failed; L2 has no rollup.tsv to count from"
       rm -f "$FINDINGS_DIR/rollup.tsv" "$FINDINGS_DIR/categories.tsv" "$FINDINGS_DIR/findings.tsv" 2>/dev/null
       printf 'rollup: failed\n' >> "$FINDINGS_DIR/run-stats.txt"
       return 0 ;;
  esac
  log "$out"
  printf '%s\n' "${out#rollup: }" | tr ' ' '\n' \
    | sed -n -e 's/^sandbox_sessions=\([0-9]*\)$/sandbox_sessions: \1/p' -e 's/^\([a-z_]*\)=\([0-9]*\)$/rollup_\1: \2/p' >> "$FINDINGS_DIR/run-stats.txt"
  printf 'sandbox_shape_denies_min: %s\n' "$AUTODREAM_SANDBOX_SHAPE_MIN" >> "$FINDINGS_DIR/run-stats.txt"
}

L1_CONFINED=no
L1_CONFINE_USING=none
L1_CONFINE_REASON="not_reached"
L1_CONFINED_ENGINES=""
L1_CONFINE_STATS=""
L1_STAGE_ROOT=""
L1_CONFINE_PROTECT=""
L1_CONFINED_STAT=no
L1_CONFINE_FATAL=""
l1_confine_setup() {
  local probe verdict reason eng d p ok_engines="" no_engines="" all_engines err sstage wrc swhy needed
  L1_CONFINED=no; L1_CONFINE_USING=none; L1_CONFINED_ENGINES=""; L1_CONFINE_STATS=""; L1_CONFINE_FATAL=""; L1_SETUP_SKIPPED=""
  L1_STAGE_ROOT="$AUTODREAM_DIR/staging/run-$$"
  L1_CONFINE_PROTECT="$AUTODREAM_DIR:$FINDINGS_DIR:$DREAMS_DIR"
  for d in "$AUTODREAM_DIR"/staging/run-*; do
    [ -d "$d" ] || continue
    p=${d##*run-}
    case "$p" in ""|*[!0-9]*) continue ;; esac
    kill -0 "$p" 2>/dev/null && continue
    rm -rf "$d"
  done
  if [ "${AUTODREAM_L1_CONFINE:-1}" = 0 ]; then
    L1_CONFINE_REASON="disabled (AUTODREAM_L1_CONFINE=0)"
  elif [ -z "$L1_CONFINER" ]; then
    L1_CONFINE_REASON="l1-confine.sh not found"
  else
    probe=$(bash "$L1_CONFINER" probe 2>/dev/null) || probe=""
    verdict=$(printf '%s' "$probe" | cut -f1)
    reason=$(printf '%s' "$probe" | cut -f2-)
    if [ "$verdict" != yes ]; then
      L1_CONFINE_REASON="${reason:-the probe printed nothing}"
    else
      L1_CONFINED=yes
      L1_CONFINE_USING="$reason"
      L1_CONFINE_REASON="ok"
    fi
  fi
  if [ -z "$(l1_missing_engines)" ] && [ "$L1_CONFINED" = yes ]; then
    L1_CONFINED_STAT="n/a"
    L1_CONFINE_REASON="no L1 work this run: every session already has findings"
    L1_SETUP_SKIPPED=$(printf '%s\n' "$AUTODREAM_L1_ENGINES" | awk -F'\t' 'NF >= 2 && $2 != "" && !seen[$2]++ { printf "%s ", $2 }')
    log "L1 confinement not set up: $L1_CONFINE_REASON (engines that may not start this run: ${L1_SETUP_SKIPPED:-none})"
  elif [ "$L1_CONFINED" = yes ]; then
    for p in "$AUTODREAM_DIR" "$FINDINGS_DIR" "$DREAMS_DIR"; do
      case "$p" in
        *:*) L1_CONFINE_FATAL="a protected directory path holds a colon, so the protect list would split it: $p"; break ;;
        /*) ;;
        *) L1_CONFINE_FATAL="a protected directory path is not absolute: $p"; break ;;
      esac
    done
    all_engines=$(printf '%s' "$AUTODREAM_L1_ENGINES" | awk -F'\t' 'NF >= 2 && $2 != "" && !seen[$2]++ { print $2 }')
    needed=$(l1_missing_engines)
    all_engines=$(printf '%s\n' "$all_engines" | grep -Fx -f <(printf '%s\n' "$needed") 2>/dev/null || true)
    L1_SETUP_SKIPPED=$(printf '%s\n' "$AUTODREAM_L1_ENGINES" | awk -F'\t' -v need="$(printf '%s' "$needed" | tr '\n' ' ')" 'BEGIN { n = split(need, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 } NF >= 2 && $2 != "" && !($2 in want) && !seen[$2]++ { printf "%s ", $2 }')
    while IFS= read -r eng; do
      [ -n "$eng" ] || continue
      "$ADAPTERS_DIR/$eng/adapter.sh" l1-writes >/dev/null 2>&1; wrc=$?
      if [ "$wrc" -ne 2 ]; then
        sstage="$L1_STAGE_ROOT/.setup-$eng"; err=""
        if ( umask 077; mkdir -p "$sstage" ) 2>/dev/null \
           && err=$(L1_STAGE_ROOT="$L1_STAGE_ROOT" L1_CONFINE_PROTECT="$L1_CONFINE_PROTECT" bash "$L1_CONFINER" engine-prefix "$ADAPTERS_DIR/$eng/adapter.sh" "$sstage" 2>&1 >/dev/null); then
          ssrc=$(printf '%s\n' "$AUTODREAM_L1_ENGINES" | awk -F'\t' -v e="$eng" '$2 == e { print $1; exit }')
          smodel=$(printf '%s\n' "$AUTODREAM_L1_MODELS" | awk -F'\t' -v s="$ssrc" '$1 == s { print $2; exit }')
          err=$("$ADAPTERS_DIR/$eng/adapter.sh" l1-stage-env "$sstage" "$smodel" 2>&1 >/dev/null); wrc=$?
          case "$wrc" in
            0|2)
              ok_engines="${ok_engines:+$ok_engines }$eng"
              L1_CONFINE_STATS="${L1_CONFINE_STATS}l1_confined_$(printf '%s' "$eng" | tr '-' '_'): yes"$'\n' ;;
            4)
              no_engines="${no_engines:+$no_engines }$eng"
              swhy=$(printf '%s' "${err:-no reason given}" | head -c 300 | tr '\n\t' '  ')
              L1_CONFINE_STATS="${L1_CONFINE_STATS}l1_confined_$(printf '%s' "$eng" | tr '-' '_'): no"$'\n'"l1_confined_$(printf '%s' "$eng" | tr '-' '_')_reason: model ${smodel:-none}: $swhy"$'\n'
              log "WARNING: the $eng engine runs unconfined (model ${smodel:-none}): $swhy; use an API-key model to confine it" ;;
            *)
              [ -n "$L1_CONFINE_FATAL" ] || L1_CONFINE_FATAL="the $eng engine's state directory cannot be prepared: $(printf '%s' "${err:-no reason given}" | head -c 300 | tr '\n\t' '  ')" ;;
          esac
        else
          [ -n "$L1_CONFINE_FATAL" ] || L1_CONFINE_FATAL="the $eng engine's sandbox cannot be built: $(printf '%s' "${err:-the staging directory could not be made}" | head -c 300 | tr '\n\t' '  ')"
        fi
        rm -rf "$sstage"
      else
        no_engines="${no_engines:+$no_engines }$eng"
        L1_CONFINE_STATS="${L1_CONFINE_STATS}l1_confined_$(printf '%s' "$eng" | tr '-' '_'): no"$'\n'"l1_confined_$(printf '%s' "$eng" | tr '-' '_')_reason: the $eng adapter declares no write profile (l1-writes)"$'\n'
        log "WARNING: the $eng engine runs unconfined: its adapter declares no write profile (l1-writes)"
      fi
    done <<< "$all_engines"
    L1_CONFINED_ENGINES="$ok_engines"
    L1_CONFINED_STAT=yes
    if [ -n "$no_engines" ]; then
      L1_CONFINED_STAT=partial
      [ -n "$ok_engines" ] || L1_CONFINED_STAT=no
      L1_CONFINE_REASON="engines that run unconfined: $no_engines (no write profile, or a model a throwaway state cannot serve)"
    fi
    log "L1 workers confined with $L1_CONFINE_USING: writes only to their staging directory under $L1_STAGE_ROOT and the engine state paths"
  else
    L1_CONFINED_STAT=no
    [ "${AUTODREAM_L1_CONFINE:-1}" = 0 ] || log "WARNING: L1 workers run unconfined (l1_confined: no): $L1_CONFINE_REASON"
  fi
  export L1_CONFINER L1_CONFINED L1_CONFINED_ENGINES L1_SETUP_SKIPPED L1_STAGE_ROOT L1_CONFINE_PROTECT DREAMS_DIR
  export AUTODREAM_WORK_BUCKET="$WORK_BUCKET"
}
l1_confine_stat_lines() {
  printf 'l1_confined: %s\n' "$L1_CONFINED_STAT"
  printf 'l1_confine_tool: %s\n' "$L1_CONFINE_USING"
  printf 'l1_confine_reason: %s\n' "$L1_CONFINE_REASON"
  printf 'l1_confine_extra: %s\n' "${AUTODREAM_L1_WRITES_EXTRA:-none}"
  [ "$L1_CONFINE_USING" != bwrap ] || printf 'l1_confine_note: bwrap prefix rules bind existing files only\n'
  printf '%s' "$L1_CONFINE_STATS"
}

dispatch_l1() { # one parallel pass; idempotent worker → only the still-missing sessions run
  [ -s "$SESSIONS_LIST" ] || return 0
  tr '\n' '\0' < "$SESSIONS_LIST" | xargs -0 -n 1 -P "$FANOUT" bash -c '
    session="$1"
    hashout=$(printf "%s" "$session" | shasum -a 1 2>/dev/null) || exit 0
    hash=${hashout:0:12}
    case "$hash" in
      [0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]) : ;;
      *) exit 0 ;;
    esac
    t0=$(date +%s)
    output="$FINDINGS_DIR/$hash.json"
    errlog="$output.err"
    outlog="$output.out"

    jq -s -e "$L1_FINDINGS_OK" "$output" >/dev/null 2>&1 && exit 0
    if [ -e "$output" ]; then
      mv -f "$output" "$output.rejected" 2>/dev/null || rm -f "$output"
      rm -f "$output.served"
    fi

    if [ ! -r "$session" ]; then
      jq -cn --arg p "$session" "{session_path: \$p, error: \"session file not readable at dispatch\", findings: []}" > "$output"
      printf "runner\t-\t-\trunner\n" > "$output.served"
      rm -f "$errlog"
      echo "skip (unreadable): $session ($hash)" >&2
      exit 0
    fi

    statsfile="$FINDINGS_DIR/$hash.stats.json"
    if [ -s "$statsfile" ]; then
      gate=$(jq -r --argjson min_turns "${AUTODREAM_MIN_USER_TURNS:-2}" --argjson min_minutes "${AUTODREAM_MIN_MINUTES:-1}" "if (.isSidechain == true) or ((.tool_call_count // 0) >= 5) then 0 elif (.user_message_count // 0) < \$min_turns then 1 elif ((.duration_minutes // 0) > 0) and ((.duration_minutes // 0) < \$min_minutes) then 1 else 0 end" "$statsfile" 2>/dev/null)
      if [ "$gate" = "1" ]; then
        jq -cn --arg p "$session" "{session_path: \$p, skipped: \"below_noise_gate\", findings: []}" > "$output"
        printf "runner\t-\t-\trunner\n" > "$output.served"
        rm -f "$errlog"
        echo "gated (below noise threshold): $session ($hash)" >&2
        exit 0
      fi
    fi

    readpath="$session"
    slimfile=""
    normfile=""
    wsrc=$(printf "%s\n" "$AUTODREAM_SOURCE_MAP" | awk -F"\t" -v h="$hash" "\$1 == h { print \$2; exit }")
    case " $AUTODREAM_NORMALIZE_SOURCES " in
      *" $wsrc "*)
        normfile="$FINDINGS_DIR/$hash.norm.jsonl"
        normerr=$("$ADAPTERS_DIR/$wsrc/adapter.sh" normalize "$session" "$normfile" 2>&1 >/dev/null | head -c 300)
        if [ ! -s "$normfile" ]; then
          rm -f "$normfile"
          jq -cn --arg p "$session" --arg a "$wsrc" --arg why "$normerr" \
            "{session_path: \$p, error: (\"session could not be normalized by the \" + \$a + \" adapter: \" + \$why), findings: []}" > "$output"
          printf "runner\t-\t-\trunner\n" > "$output.served"
          rm -f "$errlog"
          echo "skip (not normalizable): $session ($hash)" >&2
          exit 0
        fi
        readpath="$normfile"
        ;;
    esac
    dayfile=""
    if [ "${WINDOW_ON:-0}" = 1 ]; then
      dayfile="$FINDINGS_DIR/$hash.day.jsonl"
      if bash "$SESSION_WINDOW" day-file "$readpath" "$WIN_START_EPOCH" "$WIN_END_EPOCH" "$dayfile" </dev/null 2>/dev/null; then
        readpath="$dayfile"
      else
        rm -f "$dayfile"; dayfile=""
      fi
    fi
    sz=$(wc -c < "$readpath" | tr -d " ")
    slimsrc=""
    if [ "${sz:-0}" -gt "${AUTODREAM_SLIM_BYTES:-262144}" ] && [ -x "$SLIM" ]; then
      slimfile="$FINDINGS_DIR/$hash.slim.jsonl"
      slimsrc="$readpath"
      if AUTODREAM_SLIM_RESHAPE="${L1_CHUNKING:-0}" AUTODREAM_SLIM_FULL="${L1_CHUNKING:-0}" "$SLIM" "$readpath" "$slimfile" 2>/dev/null && [ -s "$slimfile" ]; then
        readpath="$slimfile"
        echo "slimmed: $session ($sz bytes) ($hash)" >&2
      else
        rm -f "$slimfile"; slimfile=""
      fi
    fi

    src=$(printf "%s\n" "$AUTODREAM_SOURCE_MAP" | awk -F"\t" -v h="$hash" "\$1 == h { print \$2; exit }")
    model=$(printf "%s\n" "$AUTODREAM_L1_MODELS" | awk -F"\t" -v s="$src" "\$1 == s { print \$2; exit }")
    engine=$(printf "%s\n" "$AUTODREAM_L1_ENGINES" | awk -F"\t" -v s="$src" "\$1 == s { print \$2; exit }")
    argv=()
    envs=()
    case "$src" in
      ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) src="" ;;
    esac
    case "$engine" in
      ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) engine="" ;;
    esac
    if [ -n "$src" ] && [ -n "$engine" ] && [ -n "$model" ] && [ -x "$ADAPTERS_DIR/$engine/adapter.sh" ]; then
      while IFS= read -r -d "" arg; do argv+=("$arg"); done < <("$ADAPTERS_DIR/$engine/adapter.sh" l1-argv "$model" 2>/dev/null)
      while IFS= read -r line; do [ -n "$line" ] && envs+=("$line"); done < <("$ADAPTERS_DIR/$engine/adapter.sh" l1-env 2>/dev/null)
    fi
    if [ "${#argv[@]}" -eq 0 ]; then
      rm -f "$slimfile" "$normfile" "$dayfile"
      jq -cn --arg p "$session" --arg s "$src" --arg m "$model" "{session_path: \$p, no_engine: true, error: (\"no L1 engine for this session (source [\" + \$s + \"], model [\" + \$m + \"])\"), findings: []}" > "$output"
      printf "runner\t-\t-\trunner\n" > "$output.served"
      rm -f "$errlog"
      echo "skip (no engine): $session ($hash)" >&2
      exit 0
    fi

    chunked=0; nchunks=1; elided=0; chunkroot=""; l1_blocked=0
    if [ "${L1_CHUNKING:-0}" = 1 ]; then
      csz=$(wc -c < "$readpath" | tr -d " ")
      if [ "${csz:-0}" -gt "$AUTODREAM_L1_CHUNK_BYTES" ]; then
        chunkroot="$FINDINGS_DIR/.chunks/$hash"
        cinfo=""
        if ( umask 077; mkdir -p "$chunkroot/in" ) 2>/dev/null; then
          cinfo=$(bash "$CHUNKER" "$readpath" "$chunkroot/in" "$AUTODREAM_L1_CHUNK_BYTES" "$AUTODREAM_L1_MAX_CHUNKS" 2>/dev/null) || cinfo=""
        fi
        read -r nchunks elided <<< "$cinfo"
        case "$nchunks" in ""|*[!0-9]*) nchunks=0 ;; esac
        case "$elided" in ""|*[!0-9]*) elided=0 ;; esac
        if [ "$nchunks" -ge 1 ]; then
          chunked=1
          printf "%s %s %s\n" "$hash" "$nchunks" "$elided" >> "$FINDINGS_DIR/l1-chunks.txt"
          echo "chunked: $session ($hash) $nchunks chunks ($elided elided)" >&2
        else
          nchunks=1; elided=0
          rm -rf "$chunkroot/in"
          echo "WARNING: chunker failed for $session ($hash); falling back to the capped head/tail slim" >&2
          [ -n "$slimfile" ] || slimfile="$FINDINGS_DIR/$hash.slim.jsonl"
          if AUTODREAM_SLIM_FULL=0 AUTODREAM_SLIM_RESHAPE=0 "$SLIM" "${slimsrc:-$readpath}" "$slimfile" 2>/dev/null && [ -s "$slimfile" ]; then
            readpath="$slimfile"
          else
            cap="${AUTODREAM_SLIM_CAP:-262144}"
            case "$cap" in ""|*[!0-9]*) cap=262144 ;; esac
            if ( umask 077; head -c "$cap" "$readpath" > "$slimfile.cap" ) 2>/dev/null && mv -f "$slimfile.cap" "$slimfile"; then
              readpath="$slimfile"
            else
              rm -f "$slimfile.cap"; l1_blocked=1
            fi
          fi
        fi
      fi
    fi

    cd "$WORK_DIR" 2>/dev/null || true
    l1wrap=()
    [ -n "$TIMEOUT_BIN" ] && l1wrap=("$TIMEOUT_BIN" -k "$L1_KILL_GRACE" "$AUTODREAM_L1_TIMEOUT")
    l1_chunk_note() { # $1=i $2=n $3=chunks dropped from the middle
      printf "This transcript is chunk %s of %s of ONE session, split at line boundaries. Other workers triage the other chunks. A tool call and its result can fall in different chunks, and the opening goal and the final outcome may be in a chunk other than yours. Long lines were cut by the slimmer, so a cut line is not malformed input. Report only what is in this chunk, and judge the outcome from the end state of this chunk. The stats below describe the whole session (or the report day, when a note above says so), not this chunk: copy them verbatim." "$1" "$2"
      if [ "${3:-0}" -gt 0 ]; then
        printf " %s chunks from the middle of the session were omitted for size." "$3"
      fi
    }
    l1_infra_fail() {
      netdown=staging
      printf "%s %s %s\n" "$hash" "${AUTODREAM_CURRENT_ROUND:-1}" staging >> "$FINDINGS_DIR/l1-netdown.txt"
      printf "the runner could not set this worker up; no stub, the session is left for a later run\n" >> "$3"
      return 1
    }
    l1_attempt() {
      if [ -z "${L1_STAGE_ROOT:-}" ]; then
        printf "no staging root is set, so there is nowhere to stage the answer for %s\n" "${l1_subject:-$session}" >> "$3"
        l1_infra_fail "$@"; return 1
      fi
      l1ans_name=$(basename "$2")
      l1stage="$L1_STAGE_ROOT/$hash.$l1ans_name"
      [ ! -L "$l1stage/tmp" ] || rm -f "$l1stage/tmp"
      if ! { [ ! -L "$l1stage" ] && ( umask 077; mkdir -p "$l1stage/tmp" ) 2>/dev/null && [ ! -L "$l1stage/tmp" ] && l1stage=$(cd "$l1stage" && pwd -P); }; then
        printf "could not make the staging directory %s for %s\n" "$l1stage" "${l1_subject:-$session}" >> "$3"
        l1_infra_fail "$@"; return 1
      fi
      l1ans="$l1stage/$l1ans_name"
      rm -f "$l1ans" "$2"
      l1pre=()
      l1senv=()
      case " ${L1_SETUP_SKIPPED:-} " in
        *" $engine "*)
          printf "the %s engine was not prepared at setup (it had no work then) and is not run unconfined now\n" "$engine" >> "$3"
          l1_infra_fail "$@"; return 1 ;;
      esac
      case " ${L1_CONFINED_ENGINES:-} " in
        *" $engine "*)
          l1serr=$(mktemp "$L1_STAGE_ROOT/senv.XXXXXX") || { printf "could not make a temp file for the state setup of %s\n" "${l1_subject:-$session}" >> "$3"; l1_infra_fail "$@"; return 1; }
          l1sout=$("$ADAPTERS_DIR/$engine/adapter.sh" l1-stage-env "$l1stage" 2>"$l1serr"); l1src=$?
          if [ "$l1src" -ne 0 ] && [ "$l1src" -ne 2 ]; then
            printf "the state directory for %s could not be prepared in the stage: %s\n" "${l1_subject:-$session}" "$(head -c 200 "$l1serr" | tr "\n" " ")" >> "$3"
            rm -f "$l1serr"
            l1_infra_fail "$@"; return 1
          fi
          rm -f "$l1serr"
          if [ "$l1src" -eq 0 ]; then
            while IFS= read -r l1e; do [ -n "$l1e" ] && l1senv+=("$l1e"); done <<< "$l1sout"
          fi
          while IFS= read -r -d "" l1wa; do l1pre+=("$l1wa"); done < <(bash "$L1_CONFINER" engine-prefix "$ADAPTERS_DIR/$engine/adapter.sh" "$l1stage" 2>>"$3")
          if [ "${#l1pre[@]}" -eq 0 ]; then
            printf "the sandbox for %s could not be built, and a confined run does not fall back to an unconfined worker\n" "${l1_subject:-$session}" >> "$3"
            l1_infra_fail "$@"; return 1
          fi
          ;;
      esac
      l1start=$(date +%s)
      {
        printf "Session transcript to analyze (literal absolute path): %s\n" "$1"
        printf "Write your findings JSON to this literal absolute path: %s\n\n" "$l1ans"
        cat "$AUTODREAM_DIR/SESSION_TRIAGE.md"
        if [ -n "$src" ] && [ -r "$ADAPTERS_DIR/$src/triage.md" ]; then
          printf "\n"
          cat "$ADAPTERS_DIR/$src/triage.md"
        fi
        if [ -n "$dayfile" ]; then
          printf "\n## Report day\n\nThis transcript is the part of a longer session that was recorded on %s (local time). Records from other days were removed, so it can open in the middle of a task and end before the task does. The stats below describe this part only.\n" "$TARGET_DATE"
        fi
        if [ -n "${5:-}" ]; then
          printf "\n## Chunk note\n\n%s\n" "$5"
        fi
        if [ -s "$FINDINGS_DIR/$hash.stats.json" ]; then
          printf "\n## Precomputed session stats (authoritative — copy these into your output)\n\n\`\`\`json\n"
          cat "$FINDINGS_DIR/$hash.stats.json"
          printf "\n\`\`\`\n"
        fi
      } | ${l1wrap[@]+"${l1wrap[@]}"} ${l1pre[@]+"${l1pre[@]}"} env ${envs[@]+"${envs[@]}"} "TMPDIR=$l1stage/tmp" ${l1senv[@]+"${l1senv[@]}"} "${argv[@]}" > "$4" 2> "$3"
      l1rc="${PIPESTATUS[1]}"
      l1elapsed=$(($(date +%s) - l1start))
      rm -rf "$2.stage"
      if mv -f "$l1ans" "$2.stage" 2>/dev/null; then
        if [ -f "$2.stage" ] && [ ! -L "$2.stage" ] && [ -s "$2.stage" ]; then
          mv -f "$2.stage" "$2" || rm -rf "$2.stage" "$2"
        else
          [ ! -L "$2.stage" ] || printf "the answer path was a symlink; it was not read\n" >> "$3"
          rm -rf "$2.stage"
        fi
      fi
      if [ -n "$TIMEOUT_BIN" ] && { [ "$l1rc" = "124" ] || [ "$l1rc" = "137" ]; } \
         && [ "$l1elapsed" -ge "$AUTODREAM_L1_TIMEOUT" ]; then
        printf "worker exceeded AUTODREAM_L1_TIMEOUT=%ss and was killed with its process group (rc=%s)\n" \
          "$AUTODREAM_L1_TIMEOUT" "$l1rc" >> "$3"
        printf "%s\n" "$hash" >> "$FINDINGS_DIR/l1-timeouts.txt"
        rm -f "$2"
      fi

      l1served=$("$ADAPTERS_DIR/$engine/adapter.sh" served "$4" "$model" 2>/dev/null) || l1served=""
      l1smodels=$(printf "%s" "$l1served" | cut -f1)
      l1scost=$(printf "%s" "$l1served" | cut -s -f2)
      l1sverdict=$(printf "%s" "$l1served" | cut -s -f3)
      case "$l1sverdict" in match|mismatch) ;; *) l1sverdict=unmeasured ;; esac
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$hash" "$engine" "$model" "${l1smodels:-unknown}" "$l1scost" "$l1sverdict" >> "$FINDINGS_DIR/l1-served.tsv"
      if [ "${AUTODREAM_L1_REQUIRE_SERVED:-0}" = 1 ] && [ -s "$2" ] && [ "$l1sverdict" != match ]; then
        if [ "$l1sverdict" = mismatch ]; then
          printf "the call was answered by [%s], not the requested model [%s]; its findings are discarded (AUTODREAM_L1_REQUIRE_SERVED=1)\n" "$l1smodels" "$model" >> "$3"
        else
          printf "the %s engine did not report which model answered, so the call cannot be held to the requested model [%s]; its findings are discarded (AUTODREAM_L1_REQUIRE_SERVED=1)\n" "$engine" "$model" >> "$3"
        fi
        rm -f "$2" "$2.served"
        return 1
      fi

      if [ -n "${5:-}" ]; then
        l1_ok() { bash "$MERGER" --check "$1"; }
      else
        l1_ok() { jq -s -e "$L1_FINDINGS_OK" "$1" >/dev/null 2>&1; }
      fi
      if [ -s "$2" ] && ! l1_ok "$2"; then
        printf "worker wrote output with no usable .findings key; treating as a failure\n" >> "$3"
        head -c 2000 "$2" >> "$3" 2>/dev/null
        rm -f "$2"
      fi

      rm -f "$2.served"
      if [ -s "$2" ]; then
        printf "%s\t%s\t%s\t%s\n" "$engine" "$model" "${l1smodels:-unknown}" "$l1sverdict" > "$2.served"
        rm -rf "$l1stage"
        return 0
      fi
      printf "worker produced no findings JSON for %s (incomplete run: the engine exited without writing output)\n" "${l1_subject:-$session}" >> "$3"
      printf "worker exit code: %s after %ss\n" "$l1rc" "$l1elapsed" >> "$3"
      if [ -s "$4" ]; then
        printf -- "--- worker stdout, last 40 lines ---\n" >> "$3"
        tail -n 40 "$4" >> "$3"
      else
        printf "worker stdout was empty\n" >> "$3"
      fi
      rm -f "$4"
      netdown=unknown
      probeurl=$(printf "%s\n" "${AUTODREAM_L1_PROBE_URLS:-}" | awk -F"\t" -v s="$src" "\$1 == s { print \$2; exit }")
      if [ -n "$probeurl" ]; then
        probehost=${probeurl#*://}; probehost=${probehost%%/*}
        netcode=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$probeurl" 2>/dev/null)
        netrc=$?
        if [ "$netrc" -eq 127 ] || [ "$netrc" -eq 126 ]; then
          printf "curl could not be run here (exit %s: not found, or not executable); this failure is unclassified, not an outage\n" "$netrc" >> "$3"
        elif [ -z "$netcode" ] || [ "$netcode" = "000" ]; then
          netdown=true
        else
          netdown=false
        fi
        if [ "$netdown" = "true" ]; then
          printf "no route to %s when this worker failed (curl http_code=%s)\n" "$probehost" "${netcode:-000}" >> "$3"
        fi
      fi
      if [ "$netdown" != "true" ] && [ -r "$FAILURE_CLASS" ] \
         && (. "$FAILURE_CLASS"; provider_is_permanent "$3"); then
        netdown=provider
        printf "provider refusal when this worker failed; no stub, the session is left for a later run\n" >> "$3"
      fi
      if [ "$netdown" != "unknown" ]; then
        printf "%s %s %s\n" "$hash" "${AUTODREAM_CURRENT_ROUND:-1}" "$netdown" >> "$FINDINGS_DIR/l1-netdown.txt"
      fi
      return 1
    }
    netdown=unknown
    if [ "$l1_blocked" = 1 ]; then
      printf "no bounded input could be made for %s; skipping the engine call this round\n" "$session" >> "$errlog"
      echo "WARNING: no bounded input for $session ($hash); skipping L1 this round" >&2
    elif [ "$chunked" = 1 ]; then
      parts=(); cfail=0; cfirst=""; ci=1
      ccfg=$( { cat "$AUTODREAM_DIR/SESSION_TRIAGE.md" 2>/dev/null
                if [ -n "$src" ] && [ -r "$ADAPTERS_DIR/$src/triage.md" ]; then cat "$ADAPTERS_DIR/$src/triage.md"; fi
                printf "%s %s %s %s %s\n" "$src" "$engine" "$model" "$nchunks" "$elided"
                cat "$FINDINGS_DIR/$hash.stats.json" 2>/dev/null; } | shasum -a 1 2>/dev/null | cut -c1-8 )
      while [ "$ci" -le "$nchunks" ]; do
        cin=$(printf "%s/in/chunk-%02d.jsonl" "$chunkroot" "$ci")
        csha=$(shasum -a 1 "$cin" 2>/dev/null | cut -c1-12)
        cout=$(printf "%s/%02d-%s-%s.chunkout" "$chunkroot" "$ci" "$csha" "$ccfg")
        parts+=("$cout")
        if bash "$MERGER" --check "$cout"; then
          echo "reuse: chunk $ci/$nchunks of $session ($hash)" >&2
        else
          rm -f "$cout"
          cerr=$(printf "%s/%02d.err" "$chunkroot" "$ci")
          cof=$(printf "%s/%02d.out" "$chunkroot" "$ci")
          printf "%s %s %s\n" "$hash" "${AUTODREAM_CURRENT_ROUND:-1}" "$ci" >> "$FINDINGS_DIR/l1-chunk-calls.txt"
          l1_subject="chunk $ci/$nchunks of $session"
          if l1_attempt "$cin" "$cout" "$cerr" "$cof" "$(l1_chunk_note "$ci" "$nchunks" "$elided")"; then
            rm -f "$cerr" "$cof"
          else
            cfail=1
            [ -n "$cfirst" ] || cfirst="$cerr"
            if [ "$netdown" = "true" ] || [ "$netdown" = "provider" ] || [ "$netdown" = "staging" ]; then break; fi
          fi
          l1_subject=""
        fi
        ci=$((ci + 1))
      done
      if [ "$cfail" = 0 ]; then
        if bash "$MERGER" --session "$session" --elided "$elided" "${parts[@]}" > "$output.merge" 2>> "$errlog" \
           && [ -s "$output.merge" ] && jq -s -e "$L1_FINDINGS_OK" "$output.merge" >/dev/null 2>&1; then
          mv -f "$output.merge" "$output"
          mverdict=match; mmodels=""
          for cpart in "${parts[@]}"; do
            cpv=$(cut -s -f4 "$cpart.served" 2>/dev/null | head -1)
            cpm=$(cut -s -f3 "$cpart.served" 2>/dev/null | head -1)
            mmodels="$mmodels,${cpm:-unknown}"
            case "$cpv" in
              match) ;;
              mismatch) mverdict=mismatch ;;
              *) [ "$mverdict" = mismatch ] || mverdict=unmeasured ;;
            esac
          done
          mmodels=$(printf "%s\n" "${mmodels#,}" | tr "," "\n" | sort -u | paste -s -d "," -)
          printf "%s\t%s\t%s\t%s\n" "$engine" "$model" "$mmodels" "$mverdict" > "$output.served"
        else
          rm -f "$output.merge" "${parts[@]}" "${parts[@]/%/.served}"
          printf "merging the %s chunk answers of %s failed; they were discarded so the next round redoes them\n" "$nchunks" "$session" >> "$errlog"
        fi
      else
        cp "$cfirst" "$errlog" 2>/dev/null
      fi
    else
      l1_attempt "$readpath" "$output" "$errlog" "$outlog"
    fi

    if [ -s "$output" ]; then
      for tmpcopy in "$slimfile" "$normfile" "$dayfile"; do
        [ -n "$tmpcopy" ] || continue
        jq -c --arg a "$tmpcopy" --arg b "$session" "walk(if type == \"string\" then split(\$a) | join(\$b) else . end)" "$output" > "$output.rw" 2>/dev/null \
          && mv "$output.rw" "$output" || rm -f "$output.rw"
      done
      rm -f "$slimfile" "$normfile" "$dayfile"
      rm -f "$errlog" "$outlog"
      echo "ok: $session ($hash) [$(($(date +%s) - t0))s]"
    else
      rm -f "$slimfile" "$normfile" "$dayfile"
      if [ "$netdown" = "true" ] || [ "$netdown" = "provider" ] || [ "$netdown" = "staging" ]; then
        failwhy="provider refusal"
        [ "$netdown" != "true" ] || failwhy="network down"
        [ "$netdown" != "staging" ] || failwhy="runner setup failed"
        echo "FAIL ($failwhy; no stub, left for a later run): $session ($hash) [$(($(date +%s) - t0))s] — see $errlog" >&2
      elif [ "${AUTODREAM_CURRENT_ROUND:-1}" -ge "${AUTODREAM_L1_ROUNDS:-5}" ]; then
        sz=$(wc -c < "$session" 2>/dev/null | tr -d " ")
        lines=$(wc -l < "$session" 2>/dev/null | tr -d " ")
        cmeta="{}"
        [ "$chunked" = 1 ] && cmeta="{\"chunks\":$nchunks,\"chunks_elided\":$elided}"
        jq -cn --arg p "$session" --arg r "${AUTODREAM_L1_ROUNDS:-5}" --argjson b "${sz:-0}" --argjson l "${lines:-0}" --argjson sl "$([ -n "$slimfile" ] && echo true || echo false)" --argjson cm "$cmeta" \
          "{session_path: \$p, error: (\"worker exited without findings JSON after \" + \$r + \" rounds\"), meta: ({bytes: \$b, lines: \$l, slimmed: \$sl} + \$cm), findings: []}" > "$output"
        printf "runner\t-\t-\trunner\n" > "$output.served"
        echo "FAIL (metadata stub written): $session ($hash) [$(($(date +%s) - t0))s] — see $errlog" >&2
      else
        echo "FAIL: $session ($hash) [$(($(date +%s) - t0))s] — see $errlog" >&2
      fi
    fi
    if [ -n "$chunkroot" ]; then
      rm -rf "$chunkroot/in"
      if [ -s "$output" ]; then rm -rf "$chunkroot"; fi
    fi
  ' _
  if [ "${L1_CHUNKING:-0}" = 1 ]; then
    rm -rf "$FINDINGS_DIR"/.chunks/*/in 2>/dev/null
    rm -f "$FINDINGS_DIR"/*.slim.jsonl "$FINDINGS_DIR"/*.slim.jsonl.cap "$FINDINGS_DIR"/*.day.jsonl "$FINDINGS_DIR"/*.norm.jsonl 2>/dev/null
    rmdir "$FINDINGS_DIR/.chunks" 2>/dev/null
  fi
  return 0
}

write_adapter_inputs() {
  local inv="$FINDINGS_DIR/skills-inventory.txt" facts="$FINDINGS_DIR/adapter-facts.md"
  local srcs src out any_ok=0 body
  srcs=$(printf '%s\n' "$AUTODREAM_SOURCE_MAP" | awk -F'\t' 'NF >= 2 && !seen[$2]++ { print $2 }')
  body=""
  for src in $ENABLED_ADAPTERS; do
    if out=$(adapter_run "$src" skills-inventory 2>/dev/null); then
      any_ok=1
      body="${body}${out}"$'\n'
    else
      log "  skills inventory unavailable from the $src adapter"
    fi
  done
  if [ "$any_ok" = "1" ]; then
    {
      printf '# skills-inventory.txt — authoritative active on-disk skill list for L2 (adapters: %s)\n' "$(printf '%s' "$ENABLED_ADAPTERS" | tr ' ' ',')"
      printf '%s' "$body" | awk -F'\t' 'NF && !seen[$1]++'
    } > "$inv" 2>/dev/null || printf '# skills-inventory.txt unavailable\n' > "$inv"
  else
    printf '# skills-inventory.txt unavailable\n' > "$inv"
  fi
  : > "$facts" 2>/dev/null || return 0
  for src in $srcs; do
    [ -f "$(adapters_root 2>/dev/null)/$src/facts.md" ] || continue
    {
      printf '## Source: %s\n\n' "$src"
      cat "$(adapters_root)/$src/facts.md"
      printf '\n'
    } >> "$facts" 2>/dev/null || true
  done
  return 0
}

unassembled_dates() {
  local window="${AUTODREAM_UNASSEMBLED_WINDOW:-7}" root="$AUTODREAM_DIR/findings"
  local epoch="${AUTODREAM_MARKER_EPOCH:-2026-08-19}"
  local d date_label report found out="" legacy=""
  [ -d "$root" ] || { printf '|'; return 0; }
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    date_label=$(basename "$d")
    [ "$date_label" = "$TARGET_DATE" ] && continue
    found=$(find "$d" -maxdepth 1 -type f -name '*.json' ! -name '*.stats.json' 2>/dev/null | head -1)
    local why=""
    if [ -z "$found" ]; then
      why=$(sed -n 's/^fatal: //p' "$d/run-stats.txt" 2>/dev/null | head -1 | tr ',' ';')
      [ -n "$why" ] || continue
    fi
    report="$DREAMS_DIR/$date_label.md"
    if [ -s "$report" ]; then
      report_finishes "$report" "$date_label" && continue
      if [[ "$date_label" < "$epoch" ]]; then
        legacy="${legacy:+$legacy, }$date_label"
        continue
      fi
    fi
    out="${out:+$out, }$date_label${why:+ (${why})}"
  done < <(find "$root" -maxdepth 1 -type d -name '2[0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]' 2>/dev/null \
    | sort | tail -n "$window")
  printf '%s|%s' "$out" "$legacy"
}
report_collector_fingerprint() {
  local f lib
  lib="$(dirname "$REPORT_SCRIPTS")/portable.sh"
  [ -r "$lib" ] || lib="$(dirname "$(readlink "$REPORT_SCRIPTS" 2>/dev/null || echo "$REPORT_SCRIPTS")")/portable.sh"
  for f in "$REPORT_SCRIPTS" "$lib"; do
    shasum -a 256 -- "$f" 2>/dev/null | cut -d' ' -f1 | grep -E '^[0-9a-f]{64}$' || return 1
  done
}

fingerprint_unchanged() {
  local now
  [ -n "$2" ] || return 1
  now=$("$1") || return 1
  [ "$now" = "$2" ]
}

report_output_fingerprint() {
  local f h
  cd "$FINDINGS_DIR" 2>/dev/null || return 1
  for f in report-index.txt report-*.md; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    h=$(shasum -a 256 -- "$f" 2>/dev/null | cut -d' ' -f1) || return 1
    printf '%s' "$h" | grep -Eq '^[0-9a-f]{64}$' || return 1
    printf '%s %s\n' "$f" "$h"
  done
}

report_scripts_unavailable() { # $1=why
  log "report scripts unavailable: $1"
  find "$FINDINGS_DIR" -maxdepth 1 \( -name 'report-*.md' -o -name report-index.txt \) -exec rm -rf {} + || return 1
  printf '# report-scripts: unavailable (%s); nothing was collected\n' "$1" > "$FINDINGS_DIR/report-index.txt" || return 1
}

report_scripts_stats() {
  local idx="$FINDINGS_DIR/report-index.txt" first n names
  first=$(sed -n 1p "$idx" 2>/dev/null)
  case "$first" in
    '# report-scripts: unavailable'*) n=unavailable ;;
    '# report-scripts: none configured'*) n=off ;;
    '# report-scripts: '[0-9]*' entries'*) n=${first#'# report-scripts: '}; n=${n%% *} ;;
    *) n=unavailable ;;
  esac
  names=$(awk -F'\t' 'NR > 1 && $1 !~ /^#/ && $2 != "ok" { printf "%s%s", sep, $1; sep = "," }' "$idx" 2>/dev/null)
  printf 'report_scripts: %s\nreport_scripts_not_ok: %s\n' "$n" "${names:-none}" >> "$FINDINGS_DIR/run-stats.txt"
}

collect_operator_notes() {
  if [ -x "$VAULT_NOTES" ]; then
    "$VAULT_NOTES" collect "$FINDINGS_DIR" || log "operator-note collection failed (continuing)"
  else
    log "vault-notes.sh not found at $VAULT_NOTES; skipping operator-note collection"
  fi
}

collect_x_bookmarks() {
  rm -f "$FINDINGS_DIR/x-bookmarks-fetch.txt" "$FINDINGS_DIR/x-bookmarks-queryid.txt"
  if [ -x "$XBOOKMARKS" ]; then
    "$XBOOKMARKS" collect "$FINDINGS_DIR" || log "x-bookmark collection failed (continuing)"
  else
    log "x-bookmarks.sh not found at $XBOOKMARKS; skipping bookmark collection"
  fi
}

record_x_bookmark_stats() {
  XQID_SOURCE=not_attempted
  if [ -s "$FINDINGS_DIR/x-bookmarks-queryid.txt" ]; then
    XQID_SOURCE=$(tr -d '[:space:]' < "$FINDINGS_DIR/x-bookmarks-queryid.txt")
    [ -n "$XQID_SOURCE" ] || XQID_SOURCE=not_attempted
  fi
  printf 'x_queryid_source: %s\n' "$XQID_SOURCE" >> "$FINDINGS_DIR/run-stats.txt"

  XFETCH_PATH=not_attempted; XFETCH_CAUSE=""
  if [ -s "$FINDINGS_DIR/x-bookmarks-fetch.txt" ]; then
    XFETCH_PATH=$(sed -n 1p "$FINDINGS_DIR/x-bookmarks-fetch.txt" | tr -d '[:space:]')
    XFETCH_CAUSE=$(sed -n 2p "$FINDINGS_DIR/x-bookmarks-fetch.txt" | tr '\t\r' '  ')
    [ -n "$XFETCH_PATH" ] || XFETCH_PATH=not_attempted
  fi
  printf 'x_fetch_path: %s\n' "$XFETCH_PATH" >> "$FINDINGS_DIR/run-stats.txt"
  [ -z "$XFETCH_CAUSE" ] || printf 'x_fetch_browser_cause: %s\n' "$XFETCH_CAUSE" >> "$FINDINGS_DIR/run-stats.txt"
}

prune_finished_worktrees() {
  PRUNE_SUMMARY="prune: not configured"
  if [ -z "${AUTODREAM_PRUNE_ROOTS:-}" ]; then
    :
  elif [ -x "$PRUNE_WORKTREES" ]; then
    PRUNE_SUMMARY=$("$PRUNE_WORKTREES" "$FINDINGS_DIR" 2>>"$RUN_LOG" | tail -1) || PRUNE_SUMMARY="prune: failed"
    [ -n "$PRUNE_SUMMARY" ] || PRUNE_SUMMARY="prune: failed"
    log "$PRUNE_SUMMARY (details: $FINDINGS_DIR/worktree-prune.md)"
  else
    log "prune-worktrees.sh not found at $PRUNE_WORKTREES; skipping worktree prune"
    PRUNE_SUMMARY="prune: helper missing"
  fi
  printf 'worktree_prune: %s\n' "$PRUNE_SUMMARY" >> "$FINDINGS_DIR/run-stats.txt"
}

list_repos_to_triage() {
  TRIAGE_SUMMARY="triage: off"
  rm -f "$FINDINGS_DIR/triage-candidates.md" "$FINDINGS_DIR/triage-candidates.tsv" 2>/dev/null
  if [ "${AUTODREAM_TRIAGE_SUGGEST:-1}" = 0 ]; then
    :
  elif [ -x "$TRIAGE_CANDIDATES" ]; then
    TRIAGE_SUMMARY=$(printf '%s\n' "$SESSION_ROWS" | "$TRIAGE_CANDIDATES" "$FINDINGS_DIR" 2>>"$RUN_LOG" | tail -1) || TRIAGE_SUMMARY="triage: failed"
    [ -n "$TRIAGE_SUMMARY" ] || TRIAGE_SUMMARY="triage: failed"
    log "$TRIAGE_SUMMARY (details: $FINDINGS_DIR/triage-candidates.md)"
  else
    log "triage-candidates.sh not found at $TRIAGE_CANDIDATES; skipping the triage list"
    TRIAGE_SUMMARY="triage: helper missing"
  fi
  printf 'triage_candidates: %s\n' "$TRIAGE_SUMMARY" >> "$FINDINGS_DIR/run-stats.txt"
}

resolve_l2_command() {
  L2_ENGINE=$(review_engine)
  L2_MODEL=$(adapter_l2_model "$L2_ENGINE" 2>/dev/null) || L2_MODEL=""
  log "L2 engine: $L2_ENGINE, model: ${L2_MODEL:-<engine default>}"
  printf 'l2_engine: %s\n' "$L2_ENGINE" >> "$FINDINGS_DIR/run-stats.txt"
  printf 'l2_model: %s\n' "${L2_MODEL:-default}" >> "$FINDINGS_DIR/run-stats.txt"
  L2_ARGV=()
  while IFS= read -r -d "" _a; do L2_ARGV+=("$_a"); done < <(adapter_run "$L2_ENGINE" l2-argv ${L2_MODEL:+"$L2_MODEL"} 2>/dev/null)
  L2_ENVS=()
  while IFS= read -r _l; do [ -n "$_l" ] && L2_ENVS+=("$_l"); done < <(adapter_run "$L2_ENGINE" l1-env 2>/dev/null)
  unset _a _l
  if [ "${#L2_ARGV[@]}" -eq 0 ] && [ "$L2_ENGINE" = "claude" ]; then
    log "  the claude adapter printed no L2 command here (an adapters/ tree that predates l2-argv); using the built-in claude invocation"
    # shellcheck source=/dev/null
    L2_SYS=$(_l=$(find_lib l2-prompt.sh) && . "$_l" && l2_system_prompt) || L2_SYS=""
    if [ -n "$L2_SYS" ]; then
      L2_ARGV=("$CLAUDE_BIN" --print --permission-mode bypassPermissions ${L2_MODEL:+--model "$L2_MODEL"} \
        --no-session-persistence --tools Glob Read --disable-slash-commands --strict-mcp-config \
        --settings '{"disableAllHooks":true}' \
        --append-system-prompt "$L2_SYS")
    else
      log "WARNING: the built-in claude invocation needs prompts/L2_SYSTEM.txt through bin/l2-prompt.sh, and neither could be read"
    fi
  fi
  if [ "${#L2_ARGV[@]}" -eq 0 ]; then
    log "WARNING: the $L2_ENGINE adapter produced no L2 command; every L2 attempt will fail"
    L2_ARGV=(false)
  fi
}

move_stale_report_aside() {
  CONSUME_SAFE=1
  PINS_SAFE=1
  if [ -s "$REPORT_PATH" ]; then
    STALE_REPORT="$REPORT_PATH.stale-$(date +%s)"
    if mv "$REPORT_PATH" "$STALE_REPORT"; then
      log "existing report for $TARGET_DATE moved aside to $STALE_REPORT before rebuilding"
    else
      log "WARNING: could not move the existing report aside; this run will NOT archive notes or mark bookmarks read, because a stale report can no longer be told apart from a fresh one"
      STALE_REPORT=""
      CONSUME_SAFE=0
    fi
  fi
}

retire_superseded_report_copies() {
  if [ -f "$REPORT_PATH" ] && [ "$L2_ATTEMPTED" = "1" ] && { [ "$L2_DELIVERED" != "1" ] || ! report_complete; }; then
    PARTIAL_REPORT="$REPORT_PATH.partial-$(date +%s)"
    if mv "$REPORT_PATH" "$PARTIAL_REPORT"; then
      log "WARNING: every L2 attempt left an incomplete report; moved it to $PARTIAL_REPORT so a later trigger retries this date"
    else
      log "WARNING: an incomplete report is at $REPORT_PATH and could not be moved aside; later triggers will treat this date as done"
    fi
  fi

  if [ -n "${STALE_REPORT:-}" ] && [ -s "$STALE_REPORT" ]; then
    if report_complete; then
      rm -f "$STALE_REPORT" && log "rebuild succeeded; discarded the superseded report copy"
    else
      log "this run produced no complete report; the previous one for $TARGET_DATE is still at $STALE_REPORT"
    fi
  fi
  if [ "${L2_DELIVERED:-0}" = 1 ] && report_complete; then drop_stale_report_copies; fi

  if report_complete; then
    for partial in "$REPORT_PATH".partial-*; do
      [ -e "$partial" ] || continue
      if rm -f "$partial"; then log "discarded superseded partial report $partial"; fi
    done
  elif [ -n "${PARTIAL_REPORT:-}" ] && [ -s "$PARTIAL_REPORT" ]; then
    log "the incomplete report for $TARGET_DATE is readable at $PARTIAL_REPORT"
  fi
}

apply_memory_pins() {
  PINS="$FINDINGS_DIR/pins.jsonl"
  if [ -s "$PINS" ] && { ! report_complete || [ "${CONSUME_SAFE:-1}" != "1" ] || [ "$PINS_SAFE" != "1" ]; }; then
    log "skipping memory pins: no complete report from this run stands behind $PINS"
  elif [ -s "$PINS" ] && ! write_pin_projects "$FINDINGS_DIR"; then
    log "skipping memory pins: could not write pin-projects.tsv, so no project is authorized"
  elif [ -s "$PINS" ] && ! restore_pins_ledger "$FINDINGS_DIR"; then
    log "skipping memory pins: could not restore pins-applied.tsv, so duplicates cannot be ruled out"
  elif [ -s "$PINS" ]; then
    if bash "$APPLY_PINS" "$FINDINGS_DIR" "$TARGET_DATE" >> "$RUN_LOG" 2>&1; then
      log "memory pins: $(tr '\n' ' ' 2>/dev/null < "$FINDINGS_DIR/pins-result.txt" || echo "counters unavailable")"
    else
      log "memory pin counters unavailable: apply-pins exited non-zero (check pins-applied.tsv for what it stored; unstored pins stay in $PINS)"
    fi
  fi
}

check_report_citations() {
  if [ -x "$CITECHECK" ]; then
    if CITE_OUT=$("$CITECHECK" "$REPORT_PATH" "$FINDINGS_DIR" 2>>"$RUN_LOG"); then
      printf '%s\n' "$CITE_OUT" >> "$FINDINGS_DIR/run-stats.txt"
      CITE_BAD=$(printf '%s\n' "$CITE_OUT" | awk -F': ' '/^citations_(unresolved|to_gated): /{n+=$2} END{print n+0}')
      if [ "$CITE_BAD" -gt 0 ]; then
        log "WARNING: $CITE_BAD report citation(s) do not resolve to a triaged session — see citations_* in run-stats.txt"
      else
        log "citations: all resolved to triaged sessions"
      fi
    else
      printf 'citations_total: unmeasured\ncitations_unresolved: unmeasured\ncitations_to_gated: unmeasured\n' \
        >> "$FINDINGS_DIR/run-stats.txt"
      log "citations: check did not run (keys recorded as unmeasured)"
    fi
  fi
}

archive_consumed_inputs() {
  NORMAL_TARGET_DATE="${AUTODREAM_CONSUME_DATE:-$(pdate_yesterday)}"
  if ! report_complete; then
    log "report is present but carries no open-questions marker; skipping vault-notes archive and x-bookmark mark-read rather than consuming input against a truncated report"
  else
    if [ -x "$VAULT_NOTES" ]; then
      "$VAULT_NOTES" publish "$REPORT_PATH" || log "vault report publish failed (continuing)"
    fi
    if [ "${CONSUME_SAFE:-1}" != "1" ]; then
      log "skipping vault-notes archive and x-bookmark mark-read: a stale report could not be moved aside, so this report cannot be attributed to this run"
    elif [ "$TARGET_DATE" = "$NORMAL_TARGET_DATE" ]; then
      if [ -x "$VAULT_NOTES" ]; then
        "$VAULT_NOTES" archive "$FINDINGS_DIR" || log "vault note archive failed (notes stay in the inbox)"
      fi
      if [ -x "$XBOOKMARKS" ]; then
        "$XBOOKMARKS" mark-read "$FINDINGS_DIR" || log "x-bookmark mark-read failed (they stay unread)"
      fi
    else
      log "target date $TARGET_DATE is not $NORMAL_TARGET_DATE (today's normal nightly date); skipping vault-notes archive and x-bookmark mark-read so today's inbox/unread bookmarks aren't consumed by this reprocess (still collected as L2 context)"
    fi
  fi
}

run_dream_triage() {
  if [ "${AUTODREAM_TRIAGE:-0}" = "1" ] && [ "$L2_DELIVERED" = "1" ] && report_complete; then
    if [ -x "$TRIAGE_DREAM" ]; then
      log "dream triage: running ($TRIAGE_DREAM)"
      env AUTODREAM_DIR="$AUTODREAM_DIR" DREAMS_DIR="$DREAMS_DIR" PROJECTS_DIR="$PROJECTS_DIR" \
        AUTODREAM_L2_ENGINE="$L2_ENGINE" "$TRIAGE_DREAM" "$TARGET_DATE" >> "$RUN_LOG" 2>&1 \
        || log "dream triage produced no worklist (continuing)"
      clean_work_bucket
    else
      log "dream triage requested but triage-dream.sh was not found; skipping"
    fi
  fi
}

run() {
  log "===== autodream start: $(date) ====="
  log "runner: $RUNNER_COMMIT$([ "$RUNNER_DIRTY" = "yes" ] && echo " (dirty)")"
  log "target date: $TARGET_DATE"
  if ! acquire_run_lock; then
    log "another run for $TARGET_DATE holds the lock (pid ${RUN_LOCK_HOLDER:-unknown}, $RUN_LOCK); nothing to do"
    return 0
  fi
  log "findings:    $FINDINGS_DIR"
  log "report:      $REPORT_PATH"
  log "fanout:      $FANOUT"
  log "claude:      $CLAUDE_BIN"
  if [ -n "$TIMEOUT_BIN" ]; then
    log "l1 timeout:  $AUTODREAM_L1_TIMEOUT s via $TIMEOUT_BIN"
  else
    log "WARNING: no timeout binary found (brew install coreutils); L1 workers run unbounded and one hang stops the run"
  fi

  probe_roots

  write_unindexed_flag

  _UNASSEMBLED_RAW=$(unassembled_dates)
  UNASSEMBLED="${_UNASSEMBLED_RAW%%|*}"
  LEGACY_MARKER="${_UNASSEMBLED_RAW##*|}"
  if [ -n "$UNASSEMBLED" ]; then
    log "WARNING: these dates have findings but no complete report: $UNASSEMBLED"
    log "         rebuild one cheaply with: $AUTODREAM_DIR/autodream-now.sh <date>"
  fi
  if [ -n "$LEGACY_MARKER" ]; then
    log "note: unmarked reports predating AUTODREAM_MARKER_EPOCH (treated as complete): $LEGACY_MARKER"
  fi

  sweep_stranded_pins

  if report_finishes_date && [ "${AUTODREAM_FORCE:-0}" != "1" ]; then
    log "report already exists for $TARGET_DATE ($REPORT_PATH); nothing to do (AUTODREAM_FORCE=1 to rebuild)"
    write_run_outcome noop
    return 0
  fi
  if [ -s "$REPORT_PATH" ] && [ "${AUTODREAM_FORCE:-0}" != "1" ]; then
    log "report at $REPORT_PATH lacks the open-questions marker; treating $TARGET_DATE as unfinished and rebuilding it"
  fi

  if [ -r "$PREFLIGHT" ]; then
    if ! bash "$PREFLIGHT" --l2-bin "$CLAUDE_BIN" 2>>"$RUN_LOG"; then
      log_fatal "preflight failed; see the MISSING lines in this log. Nothing was enumerated."
      fatal_exit
      return 1
    fi
  else
    log "WARNING: preflight not readable at $PREFLIGHT; the shared-dependency check did NOT run"
  fi

  sync_remote_roots

  if [ "$WINDOW_ON" = 1 ]; then
    log "scanning for sessions with a record between $TARGET_DATE and $NEXT_DATE (placed by the timestamps inside each transcript; a file with none by its mtime)..."
  else
    log "scanning for sessions modified between $TARGET_DATE and $NEXT_DATE..."
  fi
  export ADAPTERS_REJECT_LOG="$FINDINGS_DIR/.adapters-rejected"
  : > "$ADAPTERS_REJECT_LOG" 2>/dev/null || true
  scan_roots || { fatal_exit; return 1; }
  build_source_sidecar || { fatal_exit; return 1; }
  if [ -n "${AUTODREAM_L2_ENGINE:-}" ] && ! adapters_list 2>/dev/null | grep -qxF "$AUTODREAM_L2_ENGINE"; then
    log_fatal "AUTODREAM_L2_ENGINE=$AUTODREAM_L2_ENGINE is not an accepted adapter (accepted: $(adapters_list 2>/dev/null | tr '\n' ' ')). Refusing to start."
    fatal_exit; return 1
  fi
  # shellcheck source=/dev/null
  if ! (_l=$(find_lib l2-prompt.sh) && . "$_l" && l2_system_prompt >/dev/null 2>&1); then
    log_fatal "prompts/L2_SYSTEM.txt (read through bin/l2-prompt.sh) was not found beside run.sh, its link target or in AUTODREAM_DIR. Refusing to start."
    fatal_exit; return 1
  fi
  _l2e=$(review_engine)
  if [ "$_l2e" != "claude" ] && [ -n "$_l2e" ]; then
    _l2m=$(adapter_l2_model "$_l2e" 2>/dev/null) || _l2m=""
    if ! adapter_run "$_l2e" l2-argv ${_l2m:+"$_l2m"} 2>/dev/null | head -c 1 | grep -q .; then
      log_fatal "the $_l2e adapter cannot produce an L2 command (model [${_l2m:-none}]); set AUTODREAM_L2_MODEL_$(printf '%s' "$_l2e" | tr 'a-z-' 'A-Z_'). Refusing to start."
      fatal_exit; return 1
    fi
  fi
  if ! engine_login_ok "$_l2e"; then
    log_fatal "the $_l2e engine, which writes the summary, fails its login check ($LOGIN_REFUSAL). Refusing to start."
    fatal_exit; return 1
  fi

  if [ -x "$PRUNE" ]; then
    "$PRUNE" --filter < "$SESSIONS_LIST.raw" > "$SESSIONS_LIST" 2>/dev/null || cp "$SESSIONS_LIST.raw" "$SESSIONS_LIST"
  else
    cp "$SESSIONS_LIST.raw" "$SESSIONS_LIST"
  fi
  COUNT_AFTER_PRUNE=$(wc -l < "$SESSIONS_LIST" | tr -d ' ')
  EXCLUDED=$(( RAW - COLLIDED_DROPPED - COUNT_AFTER_PRUNE ))
  [ "$EXCLUDED" -lt 0 ] && EXCLUDED=0

  SKIPPED_EMPTY=0
  if [ "${AUTODREAM_SKIP_EMPTY:-1}" != "0" ]; then
    filter_empty_sessions < "$SESSIONS_LIST" > "$SESSIONS_LIST.nonempty" \
      && mv "$SESSIONS_LIST.nonempty" "$SESSIONS_LIST" \
      || rm -f "$SESSIONS_LIST.nonempty"
  fi
  COUNT=$(wc -l < "$SESSIONS_LIST" | tr -d ' ')
  SKIPPED_EMPTY=$(( COUNT_AFTER_PRUNE - COUNT ))
  if [ "$L1_CHUNKING" = 1 ]; then
    log "L1 chunked triage on: worker input over $AUTODREAM_L1_CHUNK_BYTES bytes is read in chunks, at most $AUTODREAM_L1_MAX_CHUNKS per session (worst case $AUTODREAM_L1_MAX_CHUNKS engine calls for one session in one round); AUTODREAM_L1_CHUNK_BYTES=0 turns it off"
  elif [ "$AUTODREAM_L1_CHUNK_BYTES" -gt 0 ]; then
    log "WARNING: chunked triage is configured (AUTODREAM_L1_CHUNK_BYTES=$AUTODREAM_L1_CHUNK_BYTES) but chunk-transcript.sh or merge-chunks.sh was not found; oversized transcripts are read the old way, the head/tail slim"
  fi
  log "found $RAW session files; excluded $EXCLUDED autodream-own, skipped $SKIPPED_EMPTY empty; $COUNT to triage; $OUT_OF_WINDOW out of window (modified since the day began, nothing inside it)"

  sweep_killed_leftovers
  if [ "$COUNT" -eq 0 ]; then
    log "no sessions to triage; writing stub report and exiting"
    THREAD_SOURCE_ROWS=$(thread_source_rows "$(pdate_shift "$TARGET_DATE" -13 d)" "$TARGET_DATE" 2>/dev/null) || THREAD_SOURCE_ROWS=""
    THREADS_REFRESH_KEYS=""
    run_threads_update
    write_threads_report_input || printf '## Dropped threads\n\n> WARNING: dropped thread report could not be generated.\n' > "$FINDINGS_DIR/dropped-threads.md"
    run_threads_dashboard
    local refused=$(( REJECTED_PATHS + HASH_COLLISIONS ))
    reconcile_findings_with_worklist
    scan_worklist_leftovers
    local early_err_files; early_err_files=$(ls -1 "$FINDINGS_DIR"/*.json.err 2>/dev/null | wc -l | tr -d ' ')
    {
      printf '# Autodream run self-audit — %s\n' "$TARGET_DATE"
      printf 'runner_commit: %s\n' "$RUNNER_COMMIT"
      printf 'runner_dirty: %s\n' "$RUNNER_DIRTY"
      printf 'sessions_found_raw: %s\n' "$RAW"
      printf 'sessions_triaged: 0\n'
      printf 'self_sessions_excluded: %s\n' "$EXCLUDED"
      printf 'sessions_skipped_empty: %s\n' "$SKIPPED_EMPTY"
      printf 'sessions_rejected_path: %s\n' "$REJECTED_PATHS"
      printf 'sessions_out_of_window: %s\n' "$OUT_OF_WINDOW"
      printf 'session_window: %s\n' "$([ "$WINDOW_ON" = 1 ] && echo on || echo off)"
      printf 'sessions_windowed: 0\n'
      printf 'sessions_duplicate_path: %s\n' "$DUPLICATE_PATHS"
      printf 'sessions_hash_collision: %s\n' "$HASH_COLLISIONS"
      printf 'sessions_dropped_to_collision: %s\n' "$COLLIDED_DROPPED"
      printf 'sidecar_stale_rows: %s\n' "$SIDECAR_STALE_ROWS"
      printf 'roots_partially_enumerated: %s\n' "$PARTIAL_ROOTS"
      printf 'roots_unavailable: %s\n' "$ROOTS_UNAVAILABLE"
      printf 'roots_failed: %s\n' "$ROOTS_FAILED"
      printf 'session_roots: %s\n' "$(( $(printf '%s' "$SESSION_ROOTS" | tr -cd ':' | wc -c) + 1 ))"
      printf 'session_roots_list: %s\n' "$SESSION_ROOTS"
      printf '%s' "$REMOTE_SYNC_LINES"
      printf 'adapters_rejected: %s\n' "$(adapters_rejected 2>/dev/null)"
      printf 'adapters_enabled: %s\n' "$(printf '%s' "$ENABLED_ADAPTERS" | tr ' ' ',' | sed 's/,$//')"
      printf 'sessions_by_source: %s\n' "${SESSIONS_BY_SOURCE:-none}"
      printf 'sessions_dropped_after_failures: 0\n'
      printf 'gated: 0\n'
      printf 'l1_rounds_max: %s\n' "${AUTODREAM_L1_ROUNDS:-5}"
      printf 'l1_rounds_used: 0\n'
      printf 'l1_timeout_bin: %s\n' "${TIMEOUT_BIN:-none}"
      printf 'l1_timeout_seconds: %s\n' "$AUTODREAM_L1_TIMEOUT"
      printf 'l1_timed_out: 0\n'
      printf 'l1_warmup: not_reached\n'
      printf 'l1_confined: not_reached\n'
      printf 'l1_breaker_fired: not_reached\n'
      printf 'l1_chunk_bytes: %s\n' "$([ "$L1_CHUNKING" = 1 ] && echo "$AUTODREAM_L1_CHUNK_BYTES" || echo 0)"
      printf 'l1_max_chunks: %s\n' "$AUTODREAM_L1_MAX_CHUNKS"
      printf 'l1_chunked_sessions: 0\n'
      printf 'l1_chunks: 0\n'
      printf 'l1_chunk_calls: 0\n'
      printf 'l1_chunks_elided: 0\n'
      printf 'l1_findings_written: 0\n'
      printf 'l1_missing_after_retries: 0\n'
      printf 'l1_err_files: %s\n' "$early_err_files"
      printf 'l1_err_files_orphaned: %s\n' "$L1_ERR_ORPHANED"
      printf 'l1_findings_outside_worklist: %s\n' "$FINDINGS_OUTSIDE_WORKLIST"
      printf 'l1_findings_with_error: 0\n'
      printf 'l1_errored_silent: 0\n'
      printf 'l1_errored_provider: 0\n'
      printf 'l1_errored_unclassified: 0\n'
      printf 'l1_sessions_already_done_at_start: 0\n'
      printf 'l1_cache_dropped: 0\n'
      printf 'l1_sessions_freshly_processed: 0\n'
      printf 'l1_elapsed_seconds: 0\n'
      printf 'oversized_total: 0\n'
      printf 'oversized_errored: 0\n'
      printf 'oversized_errored_silent: 0\n'
      printf 'oversized_errored_provider: 0\n'
      printf 'oversized_errored_unclassified: 0\n'
      printf 'oversized_unmeasurable: %s\n' "${OVERSIZED_UNMEASURABLE:-0}"
      printf 'stats_sidecars_unparseable: 0\n'
      printf 'overlap_measured: no\n'
      printf 'overlap_events: 0\n'
      printf 'sessions_with_overlap: 0\n'
      printf 'sessions_top_level: 0\nsessions_nested: 0\nfanout_parents: 0\nlargest_fanout: 0\n'
      printf 'unassembled_dates: %s\n' "${UNASSEMBLED:-}"
    } > "$FINDINGS_DIR/run-stats.txt" 2>/dev/null || true
    printf '%s\n' "$THREADS_SUMMARY" >> "$FINDINGS_DIR/run-stats.txt" 2>/dev/null || true
    cat > "$REPORT_PATH.tmp" <<EOF
# Autodream — $TARGET_DATE

No sessions were triaged on this date.

$( if [ "${ROOTS_FAILED:-0}" -gt 0 ] || [ "${ROOTS_UNAVAILABLE:-0}" -gt 0 ]; then
     printf '%s of %s configured session root(s) were unreadable or failed to enumerate, so this run did not read the whole store. Nothing was triaged from what it did read. See roots_failed and roots_unavailable in run-stats.txt — whether this was an empty night is unknown.' \
       "$(( ROOTS_FAILED + ROOTS_UNAVAILABLE ))" "$ROOTS_CONFIGURED"
   elif [ "$REMOTE_SYNC_SHORT" -gt 0 ]; then
     printf '%s of %s remote host(s) in AUTODREAM_REMOTE_ROOTS were not fully synced, so their sessions from this day may be missing. See remote_sync_* in run-stats.txt — whether this was an empty night is unknown.' \
       "$REMOTE_SYNC_SHORT" "$REMOTE_SYNC_TOTAL"
   elif [ "$RAW" -eq 0 ] && [ "$refused" -eq 0 ] && [ "$OUT_OF_WINDOW" -gt 0 ]; then
     printf 'No session had a record inside this day. %s file(s) modified since it began hold none and belong to another day. See sessions_out_of_window in run-stats.txt.' \
       "$OUT_OF_WINDOW"
   elif [ "$RAW" -eq 0 ] && [ "$refused" -eq 0 ]; then
     printf 'No session files were modified.'
   else
     printf 'Nothing was triaged. %s session file(s) were enumerated (%s autodream-own, %s with no substantive turns); a further %s path(s) were refused before enumeration, and %s hash-collision event(s) each dropped two or more paths. See run-stats.txt — this is not an empty night.' \
       "$RAW" "$EXCLUDED" "$SKIPPED_EMPTY" "$REJECTED_PATHS" "$HASH_COLLISIONS"
   fi )

$( if [ "$REMOTE_SHORT_UNREADABLE" -gt 0 ]; then
     printf '%s earlier night(s) had no readable report, so whether a remote host missed them could not be checked. See remote_short_scan_unreadable in run-stats.txt.\n\n' "$REMOTE_SHORT_UNREADABLE"
   fi
   if [ "$REMOTE_MIRROR_UNKNOWN" -gt 0 ]; then
     printf '%s remote mirror(s) could not be measured tonight (unknown in remote_mirror_files_* and remote_mirror_bytes_*), so the walk of them may have been incomplete.' "$REMOTE_MIRROR_UNKNOWN"
   fi )

(Generated $(date -u +%Y-%m-%dT%H:%M:%SZ))

AUTODREAM_QUESTIONS_BEGIN
## Open questions for the user

$( if [ "$REMOTE_SHORT_QCOUNT" -gt 0 ]; then
     printf '%s' "$REMOTE_SHORT_QUESTIONS"
   else
     printf 'None; no sessions were triaged on this date.\n'
   fi )

<!-- autodream:open-questions=$REMOTE_SHORT_QCOUNT -->
AUTODREAM_QUESTIONS_END
$(remote_short_line)
EOF
    STUB_WRITTEN=$?
    if [ -s "$FINDINGS_DIR/dropped-threads.md" ]; then
      awk -v section="$FINDINGS_DIR/dropped-threads.md" '
        $0 == "AUTODREAM_QUESTIONS_BEGIN" {
          while ((getline line < section) > 0) print line
          close(section)
          print ""
        }
        { print }
      ' "$REPORT_PATH.tmp" > "$REPORT_PATH.threads" && mv "$REPORT_PATH.threads" "$REPORT_PATH.tmp"
    fi
    if [ "$STUB_WRITTEN" = 0 ] && mv -f "$REPORT_PATH.tmp" "$REPORT_PATH"; then
      drop_stale_report_copies
    else
      rm -f "$REPORT_PATH.tmp" "$REPORT_PATH.threads"
      log_fatal "could not publish the report for $TARGET_DATE (no sessions were triaged, and the stub could not be staged or renamed into place)"
      fatal_exit
      return 1
    fi
    if [ -x "$AUTODREAM_DIR/question-streaks.sh" ]; then
      env AUTODREAM_DIR="$AUTODREAM_DIR" "$AUTODREAM_DIR/question-streaks.sh" update "$REPORT_PATH" "$FINDINGS_DIR" \
        || log "question-streaks returned non-zero (continuing)"
    fi
    if [ "$STUB_WRITTEN" -eq 0 ] && report_complete; then
      write_run_outcome delivered
    else
      log "WARNING: the stub report for $TARGET_DATE could not be written (exit $STUB_WRITTEN); not reporting it as delivered"
    fi
    return 0
  fi

  compute_session_stats

  compute_overlap_stats
  FANOUT_ROWS=$(fanout_rows "$FINDINGS_DIR")

  PIN_PROJECTS_BUILT=0
  PIN_PROJECTS_TSV=""
  SESSION_CWDS_TSV=""
  SESSION_ROWS=""
  if SESSION_ROWS=$(session_rows "$FINDINGS_DIR") \
     && PIN_PROJECTS_TSV=$(printf '%s\n' "$SESSION_ROWS" | pin_projects_from_rows) \
     && SESSION_CWDS_TSV=$(printf '%s\n' "$SESSION_ROWS" | awk -F'\t' 'NF >= 3 { print $1 "\t" $3 }'); then
    PIN_PROJECTS_BUILT=1
  else
    log "WARNING: could not build the pin authorization list; this run will not store memory pins"
  fi

  PINS_LEDGER_PRESENT=0
  PINS_LEDGER_SNAPSHOT_X=""
  PINS_LEDGER_OK=1
  if [ -e "$FINDINGS_DIR/pins-applied.tsv" ]; then
    if PINS_LEDGER_SNAPSHOT_X=$(cat -- "$FINDINGS_DIR/pins-applied.tsv" 2>/dev/null && printf x); then
      PINS_LEDGER_PRESENT=1
    else
      log "WARNING: could not read pins-applied.tsv; this run will not store memory pins"
      PINS_LEDGER_OK=0
    fi
  fi

  REPORT_SNAPSHOT=""
  REPORT_COLLECTOR_FP=""
  if [ -x "$REPORT_SCRIPTS" ]; then
    REPORT_COLLECTOR_FP=$(report_collector_fingerprint) || REPORT_COLLECTOR_FP=""
    REPORT_SNAPSHOT=$(AUTODREAM_DIR="$AUTODREAM_DIR" "$REPORT_SCRIPTS" snapshot 2>/dev/null) || REPORT_SNAPSHOT="#unavailable"
  fi

  REPORT_SEAM_OK=1
  REPORT_OUT_FP=""
  if [ ! -x "$REPORT_SCRIPTS" ]; then
    report_scripts_unavailable "report-scripts.sh not found at $REPORT_SCRIPTS" || REPORT_SEAM_OK=0
  elif ! fingerprint_unchanged report_collector_fingerprint "$REPORT_COLLECTOR_FP"; then
    report_scripts_unavailable "report-scripts.sh or portable.sh changed since the run started, or could not be hashed" || REPORT_SEAM_OK=0
  else
    REPORT_SNAPSHOT_FILE=$(mktemp "${TMPDIR:-/tmp}/report-snapshot.XXXXXX") \
      && printf '%s\n' "${REPORT_SNAPSHOT:-#unavailable}" > "$REPORT_SNAPSHOT_FILE" \
      && AUTODREAM_DIR="$AUTODREAM_DIR" "$REPORT_SCRIPTS" collect "$FINDINGS_DIR" "$REPORT_SNAPSHOT_FILE" \
      || report_scripts_unavailable "report-script collection failed" || REPORT_SEAM_OK=0
    rm -f "${REPORT_SNAPSHOT_FILE:-}"
  fi
  if [ "$REPORT_SEAM_OK" != 1 ]; then
    log_fatal "cannot clear the earlier run's report files in $FINDINGS_DIR; refusing to let L2 read them as tonight's"
    fatal_exit; return 1
  fi
  REPORT_OUT_FP=$(report_output_fingerprint) || REPORT_OUT_FP=""

  export CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1
  export CLAUDE_BIN AUTODREAM_DIR FINDINGS_DIR SLIM WORK_DIR
  export WINDOW_ON SESSION_WINDOW WIN_START_EPOCH WIN_END_EPOCH TARGET_DATE
  export L1_CHUNKING CHUNKER MERGER AUTODREAM_L1_CHUNK_BYTES AUTODREAM_L1_MAX_CHUNKS
  ADAPTERS_DIR=$(adapters_root)
  AUTODREAM_SOURCE_MAP=$(cat "$FINDINGS_DIR/sessions-source.txt" 2>/dev/null)
  THREAD_SOURCE_ROWS=$(thread_source_rows "$(pdate_shift "$TARGET_DATE" -13 d)" "$TARGET_DATE" 2>/dev/null) || THREAD_SOURCE_ROWS=""
  THREADS_STATE_PATH=${AUTODREAM_THREADS_STATE:-$AUTODREAM_DIR/threads.jsonl}
  THREADS_STATE_SNAPSHOT='[]'
  if [ -f "$THREADS_STATE_PATH" ]; then
    THREADS_STATE_SNAPSHOT=$(jq -cs '.' "$THREADS_STATE_PATH" 2>/dev/null) || THREADS_STATE_SNAPSHOT=""
  fi
  thread_refresh_pending "$THREADS_STATE_SNAPSHOT" "$THREAD_SOURCE_ROWS"
  AUTODREAM_L1_MODELS=""
  AUTODREAM_L1_ENGINES=""
  AUTODREAM_L1_PROBE_URLS=""
  local _src _model _purl _engine _reviewer
  _reviewer=$(review_engine)
  while IFS= read -r _src; do
    [ -n "$_src" ] || continue
    _engine=$(adapter_l1_engine "$_src" "$_reviewer" 2>/dev/null) || _engine=""
    _model=""
    if [ -n "$_engine" ]; then
      _model=$(adapter_l1_model "$_src" "$_reviewer" 2>/dev/null) || _model=""
    else
      log "WARNING: the L1 engine chosen for adapter $_src names no accepted adapter; its sessions will not be triaged"
    fi
    AUTODREAM_L1_MODELS="${AUTODREAM_L1_MODELS}${_src}"$'\t'"${_model}"$'\n'
    AUTODREAM_L1_ENGINES="${AUTODREAM_L1_ENGINES}${_src}"$'\t'"${_engine}"$'\n'
    _purl=$(provider_probe_url "$_engine" "$_model" 2>/dev/null) || _purl=""
    AUTODREAM_L1_PROBE_URLS="${AUTODREAM_L1_PROBE_URLS}${_src}"$'\t'"${_purl}"$'\n'
    [ -n "$_model" ] || log "WARNING: no L1 model resolves for adapter $_src; its sessions will not be triaged"
    if [ -n "$_engine" ] && [ "$_engine" != "$_src" ]; then
      log "L1 model for $_src: ${_model:-<none>} (on the $_engine engine)"
    else
      log "L1 model for $_src: ${_model:-<none>}"
    fi
  done < <(printf '%s\n' "$AUTODREAM_SOURCE_MAP" | awk -F'\t' 'NF >= 2 && !seen[$2]++ { print $2 }')
  AUTODREAM_NORMALIZE_SOURCES=""
  while IFS= read -r _src; do
    [ -n "$_src" ] || continue
    [ "$(adapter_manifest_get "$_src" '.normalize' 2>/dev/null)" = "true" ] \
      && AUTODREAM_NORMALIZE_SOURCES="${AUTODREAM_NORMALIZE_SOURCES:+$AUTODREAM_NORMALIZE_SOURCES }$_src"
  done < <(printf '%s\n' "$AUTODREAM_SOURCE_MAP" | awk -F'\t' 'NF >= 2 && !seen[$2]++ { print $2 }')
  local _eng
  while IFS= read -r _eng; do
    [ -n "$_eng" ] || continue
    engine_login_ok "$_eng" && continue
    log "WARNING: the $_eng engine fails its login check ($LOGIN_REFUSAL); the sessions it would read will not be triaged"
    AUTODREAM_L1_ENGINES=$(printf '%s' "$AUTODREAM_L1_ENGINES" | awk -F'\t' -v e="$_eng" 'BEGIN { OFS = "\t" } $2 == e { $2 = "" } { print }')$'\n'
  done < <(printf '%s' "$AUTODREAM_L1_ENGINES" | awk -F'\t' 'NF >= 2 && $2 != "" && !seen[$2]++ { print $2 }')
  export ADAPTERS_DIR AUTODREAM_SOURCE_MAP AUTODREAM_L1_MODELS AUTODREAM_L1_ENGINES AUTODREAM_L1_PROBE_URLS AUTODREAM_NORMALIZE_SOURCES
  export AUTODREAM_L1_ROUNDS
  export TIMEOUT_BIN AUTODREAM_L1_TIMEOUT L1_KILL_GRACE FAILURE_CLASS

  : > "$FINDINGS_DIR/l1-timeouts.txt"
  : > "$FINDINGS_DIR/l1-netdown.txt"
  if [ "$L1_CHUNKING" = 1 ]; then
    : > "$FINDINGS_DIR/l1-chunks.txt"
    : > "$FINDINGS_DIR/l1-chunk-calls.txt"
  fi

  reconcile_findings_with_worklist
  drop_unacceptable_l1_cache

  clean_work_bucket  # start clean: drop any stub left by a prior run's workers
  l1_confine_setup
  if [ -n "$L1_CONFINE_FATAL" ]; then
    rm -rf "$L1_STAGE_ROOT" 2>/dev/null
    log_fatal "L1 confinement cannot be set up, so no worker was started: $L1_CONFINE_FATAL"
    fatal_exit
    return 1
  fi

  L1_PRECACHED=$(l1_missing_count)
  L1_PRECACHED=$(( COUNT - L1_PRECACHED ))

  L1_WARMUP=skipped
  if [ "${AUTODREAM_L1_WARMUP:-1}" = "0" ]; then
    :
  elif [ -z "$TIMEOUT_BIN" ]; then
    L1_WARMUP=skipped_no_timeout
    log "L1 auth warmup skipped: no timeout binary, and an unbounded warmup can wedge the run before every retry path"
  else
    L1_WARMUP=ok
    while IFS=$'\t' read -r _wsrc _wmodel; do
      [ -n "$_wsrc" ] && [ -n "$_wmodel" ] || continue
      _weng=$(printf '%s\n' "$AUTODREAM_L1_ENGINES" | awk -F'\t' -v s="$_wsrc" '$1 == s { print $2; exit }')
      [ -n "$_weng" ] || continue
      _wargv=(); _wenv=()
      while IFS= read -r -d "" _a; do _wargv+=("$_a"); done < <(adapter_run "$_weng" warmup-argv "$_wmodel" 2>/dev/null)
      while IFS= read -r _l; do [ -n "$_l" ] && _wenv+=("$_l"); done < <(adapter_run "$_weng" l1-env 2>/dev/null)
      if [ "${#_wargv[@]}" -eq 0 ]; then
        L1_WARMUP=failed
        log "L1 auth warmup FAILED for $_wsrc: the adapter printed no warmup command"
        continue
      fi
      _werr="$FINDINGS_DIR/l1-warmup.$_wsrc.err"
      _wout=$(printf 'ping\n' | env ${_wenv[@]+"${_wenv[@]}"} "$TIMEOUT_BIN" -k 10 "$AUTODREAM_L1_WARMUP_TIMEOUT" "${_wargv[@]}" 2>"$_werr")
      _wrc=$?
      _wword=$(printf '%s' "$_wout" | tr -d '[:space:][:punct:]' | tr '[:upper:]' '[:lower:]')
      if [ "$_wrc" -eq 0 ] && [ "$_wword" = "ok" ]; then
        log "L1 auth warmup ok ($_wsrc)"
      else
        L1_WARMUP=failed
        log "L1 auth warmup FAILED for $_wsrc (exit $_wrc): stdout=[${_wout:-<empty>}] stderr=[$(head -c 300 "$_werr" 2>/dev/null | tr '\n' ' ')]"
      fi
    done < <(printf '%s' "$AUTODREAM_L1_MODELS")
    unset _wsrc _wmodel _weng _wargv _wenv _a _l _werr _wout _wrc _wword
  fi

  L1_START=$(date +%s)
  L1_ROUNDS="${AUTODREAM_L1_ROUNDS:-5}"
  MISSING=$COUNT
  LAST_ROUND_RUN=0
  NET_DEFERRED=no
  NET_DEFERRED_CAUSE=none
  L1_NOPROGRESS=0
  L1_BREAKER=no
  for round in $(seq 1 "$L1_ROUNDS"); do
    if ! wait_for_network "$(l1_probe_urls)"; then
      NET_DEFERRED=yes
      NET_DEFERRED_CAUSE=network
      log "L1 round $round not dispatched: no route to the API. Deferring $TARGET_DATE for a later run."
      break
    fi
    log "L1 triage round $round/$L1_ROUNDS (fanout=$FANOUT)..."
    export AUTODREAM_CURRENT_ROUND="$round"
    round_start_missing=$(l1_missing_count)
    round_start_chunks=$(l1_chunk_answers)
    dispatch_l1
    LAST_ROUND_RUN="$round"
    MISSING=$(l1_missing_count)
    L1_DONE=$(findings_json_count)
    log "L1 round $round: $L1_DONE done, $MISSING still missing"
    [ "$MISSING" -eq 0 ] && break
    if [ "$MISSING" -lt "$round_start_missing" ] || [ "$(l1_chunk_answers)" -gt "$round_start_chunks" ]; then
      L1_NOPROGRESS=0
    else
      L1_NOPROGRESS=$((L1_NOPROGRESS + 1))
    fi
    if [ "$L1_NOPROGRESS" -ge 2 ] && [ "$round" -lt "$L1_ROUNDS" ]; then
      L1_BREAKER=yes
      log "L1 circuit breaker: $L1_NOPROGRESS consecutive rounds recovered nothing ($MISSING still missing) as of round $round. Failure is deterministic; skipping $((L1_ROUNDS - round - 1)) retry round(s) and dispatching the stub round."
      export AUTODREAM_CURRENT_ROUND="$L1_ROUNDS"
      dispatch_l1
      LAST_ROUND_RUN="$L1_ROUNDS"
      MISSING=$(l1_missing_count)
      L1_DONE=$(findings_json_count)
      log "L1 stub round: $L1_DONE done, $MISSING still missing"
      break
    fi
    if [ "$round" -lt "$L1_ROUNDS" ]; then
      log "L1 retrying $MISSING missing session(s) after a network/sleep check..."
      sleep "${AUTODREAM_RETRY_WAIT:-60}"
    fi
  done
  if [ "$MISSING" -gt 0 ] && [ "$LAST_ROUND_RUN" -gt 0 ] \
     && [ -s "$FINDINGS_DIR/l1-netdown.txt" ] \
     && awk -v r="$LAST_ROUND_RUN" '$2 == r && $3 == "staging" { found = 1 } END { exit !found }' "$FINDINGS_DIR/l1-netdown.txt"; then
    rm -rf "$L1_STAGE_ROOT" 2>/dev/null
    clean_work_bucket
    log_fatal "the runner could not set up L1 workers for $MISSING session(s) in round $LAST_ROUND_RUN (stage directory, engine state or sandbox; the .err files in $FINDINGS_DIR name the cause); no stub was written, so $TARGET_DATE has no report and a later run retries it"
    fatal_exit
    return 1
  fi
  if [ "$MISSING" -gt 0 ] && [ "$LAST_ROUND_RUN" -gt 0 ] \
     && [ -s "$FINDINGS_DIR/l1-netdown.txt" ] \
     && awk -v r="$LAST_ROUND_RUN" '$2 == r && ($3 == "true" || $3 == "provider") { found = 1 } END { exit !found }' \
          "$FINDINGS_DIR/l1-netdown.txt"; then
    NET_DEFERRED=yes
    NET_DEFERRED_CAUSE=network
    awk -v r="$LAST_ROUND_RUN" '$2 == r && $3 == "provider" { found = 1 } END { exit !found }' "$FINDINGS_DIR/l1-netdown.txt" && NET_DEFERRED_CAUSE=provider
    log "L1 finished with $MISSING session(s) missing and round $LAST_ROUND_RUN failing with no route or a provider refusal — deferring $TARGET_DATE for a later run ($NET_DEFERRED_CAUSE)"
  fi
  L1_ELAPSED=$(( $(date +%s) - L1_START ))
  rm -rf "$L1_STAGE_ROOT" 2>/dev/null
  rmdir "$AUTODREAM_DIR/staging" 2>/dev/null
  clean_work_bucket
  L1_OK=$(findings_json_count)
  L1_FAIL=$(ls -1 "$FINDINGS_DIR"/*.json.err 2>/dev/null | wc -l | tr -d " ")
  scan_worklist_leftovers
  read -r L1_CHUNKED_SESSIONS L1_CHUNKS L1_CHUNKS_ELIDED L1_CHUNK_CALLS <<< "$(l1_chunk_totals)"
  L1_ERRORED=0
  L1_ERRORED_SILENT=0
  L1_ERRORED_PROVIDER=0
  L1_ERRORED_UNCLASSIFIED=0
  for findingsfile in "$FINDINGS_DIR"/*.json; do
    [ -f "$findingsfile" ] || continue
    case "$findingsfile" in *.stats.json) continue ;; esac
    findings_has_error "$findingsfile" || continue
    L1_ERRORED=$((L1_ERRORED + 1))
    failure_class=$(classify_failure "$findingsfile.err")
    case "$failure_class" in
      silent) L1_ERRORED_SILENT=$((L1_ERRORED_SILENT + 1)) ;;
      provider) L1_ERRORED_PROVIDER=$((L1_ERRORED_PROVIDER + 1)) ;;
      unclassified) L1_ERRORED_UNCLASSIFIED=$((L1_ERRORED_UNCLASSIFIED + 1)) ;;
    esac
  done
  GATED=$(find "$FINDINGS_DIR" -maxdepth 1 -type f -name '*.json' ! -name '*.stats.json' \
    -exec grep -l '"skipped": *"below_noise_gate"' {} + 2>/dev/null | wc -l | tr -d " ")
  compute_fanout_stats
  log "L1 done in ${L1_ELAPSED}s: $L1_OK done ($L1_ERRORED with errors: $L1_ERRORED_SILENT silent, $L1_ERRORED_PROVIDER provider, $L1_ERRORED_UNCLASSIFIED unclassified; $GATED gated), $MISSING missing (.err files: $L1_FAIL)"

  OVERSIZED_TOTAL=0
  OVERSIZED_ERRORED=0
  OVERSIZED_ERRORED_SILENT=0
  OVERSIZED_ERRORED_PROVIDER=0
  OVERSIZED_ERRORED_UNCLASSIFIED=0
  STATS_SIDECARS_UNPARSEABLE=0
  OVERSIZED_UNMEASURABLE=0
  while IFS= read -r session; do
    [ -n "$session" ] || continue
    hash=$(session_hash "$session") || {
      OVERSIZED_UNMEASURABLE=$((OVERSIZED_UNMEASURABLE + 1))
      log "  WARNING: could not derive an artifact hash for $session; excluded from the oversized gate as unmeasurable"
      continue
    }
    statsfile="$FINDINGS_DIR/$hash.stats.json"
    sz=""
    [ -s "$statsfile" ] && sz=$(jq -r '.transcript_bytes | numbers | floor' "$statsfile" 2>/dev/null)
    case "$sz" in ''|*[!0-9]*) sz="" ;; esac
    if [ -z "$sz" ]; then
      STATS_SIDECARS_UNPARSEABLE=$((STATS_SIDECARS_UNPARSEABLE + 1))
      sz=$(wc -c < "$session" 2>/dev/null | tr -d ' ')
      case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    fi
    if [ "$sz" -gt "${AUTODREAM_SLIM_BYTES:-262144}" ]; then
      OVERSIZED_TOTAL=$((OVERSIZED_TOTAL + 1))
      findingsfile="$FINDINGS_DIR/$hash.json"
      if [ -f "$findingsfile" ] && findings_has_error "$findingsfile"; then
        OVERSIZED_ERRORED=$((OVERSIZED_ERRORED + 1))
        failure_class=$(classify_failure "$findingsfile.err")
        case "$failure_class" in
          silent) OVERSIZED_ERRORED_SILENT=$((OVERSIZED_ERRORED_SILENT + 1)) ;;
          provider) OVERSIZED_ERRORED_PROVIDER=$((OVERSIZED_ERRORED_PROVIDER + 1)) ;;
          unclassified) OVERSIZED_ERRORED_UNCLASSIFIED=$((OVERSIZED_ERRORED_UNCLASSIFIED + 1)) ;;
        esac
      fi
    fi
  done < "$SESSIONS_LIST"
  log "oversized: $OVERSIZED_TOTAL session(s) over ${AUTODREAM_SLIM_BYTES:-262144} bytes ($OVERSIZED_ERRORED errored: $OVERSIZED_ERRORED_SILENT silent, $OVERSIZED_ERRORED_PROVIDER provider, $OVERSIZED_ERRORED_UNCLASSIFIED unclassified)"
  if [ "$STATS_SIDECARS_UNPARSEABLE" -gt 0 ]; then
    log "stats sidecars unparseable: $STATS_SIDECARS_UNPARSEABLE of $COUNT (sizes fell back to a live read; gated/oversized counts are degraded)"
  fi

  if command -v python3 >/dev/null 2>&1; then
    SESSION_ROWS="$SESSION_ROWS" python3 - "$FINDINGS_DIR" <<'PY'
import glob, json, os, sys
findings_dir = sys.argv[1]
projects = {}
for row in os.environ.get("SESSION_ROWS", "").splitlines():
    parts = row.split("\t")
    if len(parts) >= 2 and parts[1]:
        projects[parts[0]] = parts[1]
fixed = 0
for path in sorted(glob.glob(os.path.join(findings_dir, "*.json"))):
    proj = projects.get(os.path.basename(path)[:-len(".json")])
    if not proj:
        continue
    try:
        with open(path) as f:
            data = json.load(f)
    except (ValueError, OSError):
        continue  # malformed JSON: leave for the triage-failures report section
    if not isinstance(data, dict):
        continue  # valid JSON that is not an object (`[]`, `null`): nothing to normalize
    if data.get("project") != proj:
        data["project"] = proj
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, path)
        fixed += 1
print(fixed)
PY
    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
      log "normalized project field from session path"
    else
      log "WARNING: project-field normalization exited nonzero; some findings keep the project the L1 model wrote"
    fi
  else
    log "python3 not found; skipping project-field normalization (L2 grouping may show dupes)"
  fi

  SKILLS_ENFORCED=0
  SKILLS_DROPPED=0
  SKILLS_FAILED=0
  for fjson in "$FINDINGS_DIR"/*.json; do
    case "$fjson" in *.stats.json) continue ;; esac
    [ -s "$fjson" ] || continue
    jq -s -e "$L1_FINDINGS_OK" "$fjson" >/dev/null 2>&1 || continue
    sidecar="${fjson%.json}.stats.json"
    skilltmp="$fjson.skills.tmp"
    if ! jq -e 'type == "object" and (["skills_invoked", "skills_invoked_count", "skills_invoked_counts", "skills_authored"] - keys | length == 0)' "$sidecar" >/dev/null 2>&1; then
      if jq 'del(.skills_invoked, .skills_invoked_count, .skills_invoked_counts, .skills_authored)' \
          "$fjson" > "$skilltmp" 2>/dev/null && [ -s "$skilltmp" ]; then
        mv "$skilltmp" "$fjson"
        SKILLS_DROPPED=$((SKILLS_DROPPED + 1))
      else
        rm -f "$skilltmp"
        SKILLS_FAILED=$((SKILLS_FAILED + 1))
      fi
      continue
    fi
    if jq --slurpfile sc "$sidecar" '
          . as $f
          | (($sc[0]) // {}) as $st
          | reduce ("skills_invoked", "skills_invoked_count", "skills_authored", "skills_invoked_counts") as $k
              ($f; if ($st | has($k)) then .[$k] = $st[$k] else . end)
        ' "$fjson" > "$skilltmp" 2>/dev/null && [ -s "$skilltmp" ]; then
      mv "$skilltmp" "$fjson"
      SKILLS_ENFORCED=$((SKILLS_ENFORCED + 1))
    else
      rm -f "$skilltmp"
      SKILLS_FAILED=$((SKILLS_FAILED + 1))
    fi
  done
  log "enforced mechanical skill fields from sidecars on $SKILLS_ENFORCED findings file(s); removed unmeasured skill fields from $SKILLS_DROPPED whose sidecar was missing, unreadable, or incomplete; $SKILLS_FAILED rewrite(s) failed"

  thread_refresh_accepted

  DROPPED_AFTER_FAILURES=$(( RAW - COLLIDED_DROPPED - L1_OK - EXCLUDED - SKIPPED_EMPTY ))
  [ "$DROPPED_AFTER_FAILURES" -lt 0 ] && DROPPED_AFTER_FAILURES=0
  L1_FRESHLY_PROCESSED=$(( L1_OK - L1_PRECACHED ))
  [ "$L1_FRESHLY_PROCESSED" -lt 0 ] && L1_FRESHLY_PROCESSED=0
  SESSION_ROOT_COUNT=$(( $(printf '%s' "$SESSION_ROOTS" | tr -cd ':' | wc -c) + 1 ))
  {
    printf '# Autodream run self-audit — %s\n' "$TARGET_DATE"
    printf 'runner_commit: %s\n' "$RUNNER_COMMIT"
    printf 'runner_dirty: %s\n' "$RUNNER_DIRTY"
    printf 'session_roots: %s\n' "$SESSION_ROOT_COUNT"
    printf 'session_roots_list: %s\n' "$SESSION_ROOTS"
    printf '%s' "${REMOTE_SYNC_LINES:-}"
    printf 'sessions_found_raw: %s\n' "$RAW"
    printf 'sessions_rejected_path: %s\n' "$REJECTED_PATHS"
    printf 'sessions_out_of_window: %s\n' "$OUT_OF_WINDOW"
    printf 'session_window: %s\n' "$([ "$WINDOW_ON" = 1 ] && echo on || echo off)"
    printf 'sessions_windowed: %s\n' "${SESSIONS_WINDOWED:-0}"
    printf 'roots_partially_enumerated: %s\n' "$PARTIAL_ROOTS"
    printf 'roots_unavailable: %s\n' "$ROOTS_UNAVAILABLE"
    printf 'roots_failed: %s\n' "$ROOTS_FAILED"
    printf 'adapters_enabled: %s\n' "$(printf '%s' "$ENABLED_ADAPTERS" | tr ' ' ',' | sed 's/,$//')"
    printf 'adapters_rejected: %s\n' "$(adapters_rejected 2>/dev/null)"
    printf 'sessions_by_source: %s\n' "$SESSIONS_BY_SOURCE"
    printf 'sessions_duplicate_path: %s\n' "$DUPLICATE_PATHS"
    printf 'sessions_hash_collision: %s\n' "$HASH_COLLISIONS"
    printf 'self_sessions_excluded: %s\n' "$EXCLUDED"
    printf 'sessions_skipped_empty: %s\n' "$SKIPPED_EMPTY"
    printf 'sessions_triaged: %s\n' "$COUNT"
    printf 'gated: %s\n' "$GATED"
    printf 'sessions_dropped_to_collision: %s\n' "$COLLIDED_DROPPED"
    printf 'sidecar_stale_rows: %s\n' "$SIDECAR_STALE_ROWS"
    printf 'sessions_dropped_after_failures: %s\n' "$DROPPED_AFTER_FAILURES"
    printf 'l1_rounds_used: %s\n' "$LAST_ROUND_RUN"
    printf 'l1_rounds_max: %s\n' "$L1_ROUNDS"
    printf 'l1_timeout_bin: %s\n' "${TIMEOUT_BIN:-none}"
    printf 'l1_timeout_seconds: %s\n' "$AUTODREAM_L1_TIMEOUT"
    printf 'l1_timed_out: %s\n' "$(sort -u "$FINDINGS_DIR/l1-timeouts.txt" 2>/dev/null | grep -c . || true)"
    printf 'l1_warmup: %s\n' "${L1_WARMUP:-not_reached}"
    l1_confine_stat_lines
    while IFS=$'\t' read -r _msrc _mval; do
      [ -n "$_msrc" ] || continue
      printf 'l1_model_%s: %s\n' "$(printf '%s' "$_msrc" | tr '-' '_')" "${_mval:-none}"
    done <<< "$AUTODREAM_L1_MODELS"
    while IFS=$'\t' read -r _msrc _mval; do
      [ -n "$_msrc" ] || continue
      printf 'l1_engine_%s: %s\n' "$(printf '%s' "$_msrc" | tr '-' '_')" "${_mval:-none}"
    done <<< "${AUTODREAM_L1_ENGINES:-}"
    while IFS=$'\t' read -r _msrc _pprov _pauth _pplan _pacct _pexp; do
      [ -n "$_msrc" ] || continue
      printf 'login_%s: provider=%s auth=%s plan=%s account=%s expires=%s\n' "$(printf '%s' "$_msrc" | tr '-' '_')" "$_pprov" "$_pauth" "$_pplan" "$_pacct" "${_pexp:-unknown}"
    done <<< "${ENGINE_LOGINS:-}"
    if [ -s "$FINDINGS_DIR/l1-served.tsv" ]; then
      printf 'l1_served_models: %s\n' "$(cut -f4 "$FINDINGS_DIR/l1-served.tsv" | sort | uniq -c | awk '{ printf "%s%s=%s", (NR > 1 ? " " : ""), $2, $1 }')"
      printf 'l1_served_mismatch: %s\n' "$(awk -F'\t' '$6 == "mismatch"' "$FINDINGS_DIR/l1-served.tsv" | wc -l | tr -d ' ')"
      printf 'l1_served_unmeasured: %s\n' "$(awk -F'\t' '$6 != "match" && $6 != "mismatch"' "$FINDINGS_DIR/l1-served.tsv" | wc -l | tr -d ' ')"
      printf 'l1_cost_usd_estimate: %s\n' "$(awk -F'\t' '$5 != "" { s += $5 } END { printf "%.4f", s }' "$FINDINGS_DIR/l1-served.tsv")"
      printf 'l1_cost_unmeasured: %s\n' "$(awk -F'\t' '$5 == ""' "$FINDINGS_DIR/l1-served.tsv" | wc -l | tr -d ' ')"
    else
      printf 'l1_served_models: none\nl1_served_mismatch: 0\nl1_served_unmeasured: 0\nl1_cost_usd_estimate: 0.0000\nl1_cost_unmeasured: 0\n'
    fi
    printf 'l1_breaker_fired: %s\n' "${L1_BREAKER:-not_reached}"
    printf 'l1_chunk_bytes: %s\n' "$([ "$L1_CHUNKING" = 1 ] && echo "$AUTODREAM_L1_CHUNK_BYTES" || echo 0)"
    printf 'l1_max_chunks: %s\n' "$AUTODREAM_L1_MAX_CHUNKS"
    printf 'l1_chunked_sessions: %s\n' "${L1_CHUNKED_SESSIONS:-0}"
    printf 'l1_chunks: %s\n' "${L1_CHUNKS:-0}"
    printf 'l1_chunk_calls: %s\n' "${L1_CHUNK_CALLS:-0}"
    printf 'l1_chunks_elided: %s\n' "${L1_CHUNKS_ELIDED:-0}"
    printf 'l1_findings_written: %s\n' "$L1_OK"
    printf 'l1_findings_with_error: %s\n' "$L1_ERRORED"
    printf 'l1_errored_silent: %s\n' "$L1_ERRORED_SILENT"
    printf 'l1_errored_provider: %s\n' "$L1_ERRORED_PROVIDER"
    printf 'l1_errored_unclassified: %s\n' "$L1_ERRORED_UNCLASSIFIED"
    printf 'oversized_total: %s\n' "$OVERSIZED_TOTAL"
    printf 'oversized_errored: %s\n' "$OVERSIZED_ERRORED"
    printf 'oversized_errored_silent: %s\n' "$OVERSIZED_ERRORED_SILENT"
    printf 'oversized_errored_provider: %s\n' "$OVERSIZED_ERRORED_PROVIDER"
    printf 'oversized_errored_unclassified: %s\n' "$OVERSIZED_ERRORED_UNCLASSIFIED"
    printf 'oversized_unmeasurable: %s\n' "${OVERSIZED_UNMEASURABLE:-0}"
    printf 'stats_sidecars_unparseable: %s\n' "$STATS_SIDECARS_UNPARSEABLE"
    printf 'l1_missing_after_retries: %s\n' "$MISSING"
    printf 'l1_err_files: %s\n' "$L1_FAIL"
    printf 'l1_err_files_orphaned: %s\n' "$L1_ERR_ORPHANED"
    printf 'l1_findings_outside_worklist: %s\n' "$FINDINGS_OUTSIDE_WORKLIST"
    printf 'l1_sessions_already_done_at_start: %s\n' "$L1_PRECACHED"
    printf 'l1_cache_dropped: %s\n' "$L1_CACHE_DROPPED"
    printf 'l1_sessions_freshly_processed: %s\n' "$L1_FRESHLY_PROCESSED"
    printf 'l1_elapsed_seconds: %s\n' "$L1_ELAPSED"
    printf 'overlap_measured: %s\n' "$([ "$OVERLAP_MEASURED" = "1" ] && echo yes || echo no)"
    printf 'overlap_events: %s\n' "$OVERLAP_EVENTS"
    printf 'sessions_with_overlap: %s\n' "$SESSIONS_WITH_OVERLAP"
    printf 'sessions_top_level: %s\n' "$FANOUT_TOP"
    printf 'sessions_nested: %s\n' "$FANOUT_NESTED"
    printf 'fanout_parents: %s\n' "$FANOUT_PARENTS"
    printf 'largest_fanout: %s\n' "$FANOUT_LARGEST"
    printf 'skills_unmeasured: %s\n' "${SKILLS_DROPPED:-0}"
    printf 'skills_enforcement_failed: %s\n' "${SKILLS_FAILED:-0}"
    printf 'unassembled_dates: %s\n' "${UNASSEMBLED:-}"
    printf 'legacy_marker_reports: %s\n' "${LEGACY_MARKER:-}"
    printf 'network_down_seconds: %s\n' "$NET_DOWN_SECONDS"
    printf 'network_deferred: %s\n' "$NET_DEFERRED"
    printf 'l1_deferred_cause: %s\n' "$NET_DEFERRED_CAUSE"
    if [ "$NET_DOWN_SECONDS" -gt 0 ] \
       && ! awk '$3 == "true" { found = 1 } END { exit !found }' \
              "$FINDINGS_DIR/l1-netdown.txt" 2>/dev/null; then
      printf 'network_flapped: yes\n'
    else
      printf 'network_flapped: no\n'
    fi
  } > "$FINDINGS_DIR/run-stats.txt"

  NET_DOWN_SECONDS_PRE_L2="$NET_DOWN_SECONDS"

  if [ "$NET_DEFERRED" = "yes" ]; then
    log "deferring $TARGET_DATE: L2 would summarize $((COUNT - MISSING)) of $COUNT sessions"
    log "a later run will retry the $MISSING session(s) still missing; findings so far are kept"
    printf 'network_down_seconds_l2: 0\n' >> "$FINDINGS_DIR/run-stats.txt"
    printf 'network_deferred_l2: no\n' >> "$FINDINGS_DIR/run-stats.txt"
    clean_work_bucket
    return 1
  fi

  changelog_window

  collect_operator_notes

  collect_x_bookmarks

  if ! fingerprint_unchanged report_output_fingerprint "$REPORT_OUT_FP"; then
    report_scripts_unavailable "the report files changed after collection or could not be hashed (an L1 worker that is not confined can write here)" || {
      log_fatal "cannot clear the report files in $FINDINGS_DIR after they changed; refusing to let L2 read them"
      fatal_exit; return 1
    }
  fi
  report_scripts_stats

  record_x_bookmark_stats

  prune_finished_worktrees

  list_repos_to_triage

  write_rollup

  thread_refresh_accepted
  run_threads_update
  write_threads_report_input || printf '## Dropped threads\n\n> WARNING: dropped thread report could not be generated.\n' > "$FINDINGS_DIR/dropped-threads.md"
  run_threads_dashboard
  printf '%s\n' "$THREADS_SUMMARY" >> "$FINDINGS_DIR/run-stats.txt"

  write_adapter_inputs

  resolve_l2_command

  move_stale_report_aside

  L2_ATTEMPTS="${AUTODREAM_L2_ATTEMPTS:-3}"
  L2_ATTEMPTED=0
  L2_DELIVERED=0
  L2_START=$(date +%s)
  L2_STDOUT="$FINDINGS_DIR/report.stdout"   # L2 holds no Write tool: the report arrives on stdout
  L2_RC=1
  for attempt in $(seq 1 "$L2_ATTEMPTS"); do
    L2_ATTEMPTED=1
    log "L2 aggregation attempt $attempt/$L2_ATTEMPTS..."
    if [ -e "$FINDINGS_DIR/pins.jsonl" ]; then
      if STALE_PINS=$(mktemp "$FINDINGS_DIR/pins.jsonl.stale-XXXXXX") \
         && mv -f "$FINDINGS_DIR/pins.jsonl" "$STALE_PINS"; then
        log "moved an earlier pins.jsonl aside before this attempt"
      else
        log "WARNING: could not move an earlier pins.jsonl aside; this run will not store memory pins"
        PINS_SAFE=0
        if [ -n "${STALE_PINS:-}" ] && [ -f "$STALE_PINS" ] && [ ! -s "$STALE_PINS" ]; then
          rm -f "$STALE_PINS"
        fi
      fi
    fi
    L2_PIDFILE=$(mktemp "${TMPDIR:-/tmp}/l2pid.XXXXXX" 2>/dev/null) || L2_PIDFILE=/dev/null
    l2_diag_start 2>/dev/null || true
    (
      cd "$WORK_DIR" 2>/dev/null || true
      {
        printf "Findings directory to aggregate (literal absolute path): %s\n" "$FINDINGS_DIR"
        printf "Dropped threads runner input (literal absolute path): %s/dropped-threads.md\n" "$FINDINGS_DIR"
        printf "Report destination (literal absolute path): %s\n\n" "$REPORT_PATH"
        cat "$AUTODREAM_DIR/PROMPT.md"
      } | env ${L2_ENVS[@]+"${L2_ENVS[@]}"} /bin/sh -c 'printf %s "$$" > "$0" 2>/dev/null; exec "$@"' "$L2_PIDFILE" ${L2_ARGV[@]+"${L2_ARGV[@]}"}
    ) > "$L2_STDOUT"

    L2_RC=$?
    l2_diag_end "$attempt" "$L2_ATTEMPTS" "$L2_RC" "$L2_PIDFILE" 2>/dev/null || true
    [ "$L2_PIDFILE" = /dev/null ] || rm -f "$L2_PIDFILE"
    L2_SENTINEL=0
    report_has_sentinel "$L2_STDOUT" && L2_SENTINEL=1
    if [ "$L2_SENTINEL" = "1" ] && [ "$PINS_SAFE" = "1" ]; then
      if report_pin_lines "$L2_STDOUT" > "$FINDINGS_DIR/pins.jsonl.tmp" \
         && [ -s "$FINDINGS_DIR/pins.jsonl.tmp" ] && mv -f "$FINDINGS_DIR/pins.jsonl.tmp" "$FINDINGS_DIR/pins.jsonl"; then
        log "wrote $(wc -l < "$FINDINGS_DIR/pins.jsonl" | tr -d ' ') proposed pin(s) from the L2 pin block"
        write_pin_projects "$FINDINGS_DIR" || log "WARNING: could not write pin-projects.tsv; these pins wait for a later run that can"
      else
        rm -f "$FINDINGS_DIR/pins.jsonl.tmp"
      fi
    fi
    L2_COMPLETE=0
    if report_has_sentinel "$L2_STDOUT"; then
      write_session_cwds "$FINDINGS_DIR" || log "WARNING: could not write session-cwds.tsv; Lately will fall back to project buckets"
      if report_body "$L2_STDOUT" > "$REPORT_PATH.body" \
         && { awk '!/^<!-- autodream:remote-short=.* -->$/' "$REPORT_PATH.body" && remote_short_line; } > "$REPORT_PATH.tmp" \
         && mv "$REPORT_PATH.tmp" "$REPORT_PATH"; then
        L2_COMPLETE=1
      else
        log "WARNING: could not stage the sentinel-stripped report at $REPORT_PATH"
      fi
      rm -f "$REPORT_PATH.body"
    elif [ -s "$L2_STDOUT" ]; then
      log "WARNING: L2 stdout carried no AUTODREAM_REPORT_END sentinel; keeping the whole capture as a degraded report (incomplete, will retry)"
      cat "$L2_STDOUT" > "$REPORT_PATH.tmp" && mv "$REPORT_PATH.tmp" "$REPORT_PATH" 2>/dev/null || true
    fi
    report_after_sentinel "$L2_STDOUT" >> "$RUN_LOG" 2>/dev/null || true
    L2_DELIVERED=$L2_COMPLETE
    if [ "$L2_DELIVERED" = "1" ] && report_complete; then
      break
    fi
    if [ -s "$REPORT_PATH" ]; then
      if report_complete; then
        log "L2 attempt $attempt wrote a complete-looking report but no AUTODREAM_REPORT_END sentinel; not a validated delivery, retrying (exit $L2_RC)"
      else
        L2_INCOMPLETE_CAUSE=$(report_incomplete_cause "$REPORT_PATH")
        log "L2 attempt $attempt left a report with ${L2_INCOMPLETE_CAUSE:-no open-questions marker}; treating it as truncated and retrying (exit $L2_RC)"
      fi
    else
      log "L2 attempt $attempt wrote no report (exit $L2_RC)"
    fi
    if [ "$attempt" -lt "$L2_ATTEMPTS" ]; then
      if ! wait_for_network "$(l2_probe_url)"; then
        NET_DEFERRED=yes
        log "L2 retry not attempted: no route to the API — deferring $TARGET_DATE for a later run"
        break
      fi
      sleep "${AUTODREAM_RETRY_WAIT:-60}"
    fi
  done
  clean_work_bucket  # all workers have exited; remove their AI-title stubs

  if [ "${AUTODREAM_NETCHECK:-1}" != "0" ] && [ "$L2_DELIVERED" != "1" ] && ! net_up "$(l2_probe_url)"; then
    NET_DEFERRED=yes
    log "L2 produced no report and the API is unreachable; recording this as a network deferral"
  fi
  printf 'network_down_seconds_l2: %s\n' "$(( NET_DOWN_SECONDS - NET_DOWN_SECONDS_PRE_L2 ))" >> "$FINDINGS_DIR/run-stats.txt"
  printf 'network_deferred_l2: %s\n' "$NET_DEFERRED" >> "$FINDINGS_DIR/run-stats.txt"

  L2_ELAPSED=$(( $(date +%s) - L2_START ))
  log "L2 done in ${L2_ELAPSED}s (exit $L2_RC, $attempt attempt(s))"

  retire_superseded_report_copies

  if [ -f "$REPORT_PATH" ]; then
    log "report bytes: $(wc -c < "$REPORT_PATH" | tr -d ' ')"
    if [ "$L2_DELIVERED" = "1" ] && report_complete; then write_run_outcome delivered; fi

    if [ -x "$AUTODREAM_DIR/question-streaks.sh" ]; then
      env AUTODREAM_DIR="$AUTODREAM_DIR" "$AUTODREAM_DIR/question-streaks.sh" update "$REPORT_PATH" "$FINDINGS_DIR" \
        || log "question-streaks returned non-zero (continuing)"
    fi

    apply_memory_pins

    check_report_citations

    if [ -x "$AUTODREAM_DIR/notify.sh" ]; then
      log "writing open-questions inbox file..."
      "$AUTODREAM_DIR/notify.sh" "$REPORT_PATH" || log "notify step returned non-zero (continuing)"
    fi

    archive_consumed_inputs

    run_dream_triage
  else
    log "WARNING: no report at $REPORT_PATH"
  fi

  log "===== autodream end: $(date) ====="
  if [ "$L2_DELIVERED" = "1" ] && report_complete; then
    return 0
  fi
  if [ "${L2_RC:-0}" -ne 0 ]; then
    return "$L2_RC"
  fi
  return 1
}

trap '' PIPE
trap release_run_lock EXIT
if [ -t 1 ]; then
  run 2>&1 | tee -a "$RUN_LOG"
  exit "${PIPESTATUS[0]}"
fi
echo "autodream: logging to $RUN_LOG"
run >> "$RUN_LOG" 2>&1
exit $?
