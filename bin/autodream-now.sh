#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
# autodream-now.sh — run the autodream pipeline NOW via launchd, detached from any
# foreground/background timeout (Claude Code background Bash tasks cap at ~10 min,
# ssh sessions die on disconnect, etc). launchd owns the process, so the run
# survives the caller going away and has no time cap.
#
# It bootstraps a TRANSIENT one-shot LaunchAgent (label "<base>.ondemand.<install hash>") that runs
# run.sh once and exits. It never touches the scheduled nightly job.
#
# Usage:
#   autodream-now.sh [YYYY-MM-DD] [--force] [--watch] [--dry-run]
#     YYYY-MM-DD   date to process (default: yesterday, same as run.sh)
#     --force      set AUTODREAM_FORCE=1 (rebuild even if a report already exists)
#     --watch      tail this run's log until it writes a complete report (exit 0) or ends
#                  without one (exit 1)
#     --dry-run    print the generated plist + launchctl commands; don't run anything
#
EOF
}

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

DATE_ARG=""
FORCE=0
WATCH=0
DRYRUN=0
for a in "$@"; do
  case "$a" in
    --force)   FORCE=1 ;;
    --watch)   WATCH=1 ;;
    --dry-run) DRYRUN=1 ;;
    -h|--help) usage; exit 0 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) DATE_ARG="$a" ;;
    *) echo "autodream-now: unknown argument '$a'" >&2; exit 64 ;;
  esac
done

resolve() {
  local p="$1" t
  while [ -L "$p" ]; do
    t="$(readlink "$p")"
    case "$t" in
      /*) p="$t" ;;
      *)  p="$(cd "$(dirname "$p")" && pwd)/$t" ;;
    esac
  done
  printf '%s\n' "$p"
}
SELF="$(resolve "${BASH_SOURCE[0]}")"
BIN_DIR="$(cd "$(dirname "$SELF")" && pwd)"
RUN_SH="$BIN_DIR/run.sh"
[ -f "$RUN_SH" ] || { echo "autodream-now: run.sh not found next to $SELF" >&2; exit 70; }

_src="${BASH_SOURCE[0]}"; _lib="$(dirname "$_src")/lib-install-dir.sh"
[ -r "$_lib" ] || _lib="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/lib-install-dir.sh"
# shellcheck source=/dev/null
. "$_lib"
resolve_install_dir "$_src"
DREAMS_DIR="${DREAMS_DIR:-$HOME/.claude/dreams}"
mkdir -p "$AUTODREAM_DIR/logs"

if [ -n "$DATE_ARG" ]; then
  TARGET="$DATE_ARG"
else
  TARGET="$(pdate_yesterday)"
fi

UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"
BASE_LABEL="$("$BIN_DIR/scheduler-label.sh" "$AUTODREAM_DIR" 2>/dev/null || true)"
[ -n "$BASE_LABEL" ] || BASE_LABEL="com.$(id -un | tr -dc 'a-zA-Z0-9').autodream"
INSTALL_REAL="$(cd "$AUTODREAM_DIR" 2>/dev/null && pwd -P)" || INSTALL_REAL="${AUTODREAM_DIR%/}"
LABEL="${BASE_LABEL}.ondemand.$(printf '%s' "$INSTALL_REAL" | shasum -a 1 | cut -c1-8)"
PLIST="$AUTODREAM_DIR/${LABEL}.plist"

path_dirs=""
for tool in claude git bash; do
  if b="$(command -v "$tool" 2>/dev/null)"; then
    d="$(cd "$(dirname "$b")" && pwd)"
    case ":$path_dirs:" in *":$d:"*) ;; *) path_dirs="${path_dirs:+$path_dirs:}$d" ;; esac
  fi
done
PATH_VAL="${path_dirs:+$path_dirs:}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

env_xml="        <key>PATH</key><string>${PATH_VAL}</string>
"
env_xml+="        <key>AUTODREAM_DIR</key><string>${AUTODREAM_DIR}</string>
"
env_xml+="        <key>DREAMS_DIR</key><string>${DREAMS_DIR}</string>
"
[ "$FORCE" = 1 ] && env_xml+="        <key>AUTODREAM_FORCE</key><string>1</string>
"

xml_escape_into() {
  local out
  out="$(printf '%sx' "$2" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
  printf -v "$1" '%s' "${out%x}"
}
SCHED_PLIST="$("$BIN_DIR/scheduler-label.sh" --plist "$AUTODREAM_DIR" 2>/dev/null || true)"
INHERITED_KEYS=""
if [ -n "$SCHED_PLIST" ]; then
  ENV_WORK="$(mktemp -d "${TMPDIR:-/tmp}/autodream-now.XXXXXX")" || { echo "autodream-now: cannot make a scratch directory" >&2; exit 65; }
  JQ_BIN="${AUTODREAM_JQ_BIN:-$(PATH="$PATH_VAL:$PATH" command -v jq 2>/dev/null || true)}"
  PLUTIL_BIN="$(PATH="$PATH_VAL:$PATH" command -v plutil 2>/dev/null || true)"
  if [ -z "$JQ_BIN" ] || [ -z "$PLUTIL_BIN" ]; then
    rm -rf "$ENV_WORK"
    echo "autodream-now: the scheduled job $SCHED_PLIST has an environment to copy and this needs both plutil and jq (not found); refusing to launch logged out" >&2
    exit 65
  fi
  if ! {
    "$PLUTIL_BIN" -convert json -o "$ENV_WORK/job.json" "$SCHED_PLIST" 2>/dev/null \
      && "$JQ_BIN" -j '(.EnvironmentVariables // {}) | to_entries[] | select(.value | type == "string") | .key, "\u0000", .value, "\u0000"' "$ENV_WORK/job.json" > "$ENV_WORK/env.nul" 2>/dev/null
  }; then
    rm -rf "$ENV_WORK"
    echo "autodream-now: could not read the environment of the scheduled job $SCHED_PLIST; refusing to launch logged out" >&2
    exit 65
  fi
  ek=""; ev=""
  while IFS= read -r -d '' k && IFS= read -r -d '' v; do
    case "$k" in PATH|AUTODREAM_DIR|DREAMS_DIR|AUTODREAM_FORCE|AUTODREAM_RUN_TOKEN) continue ;; esac
    xml_escape_into ek "$k"
    xml_escape_into ev "$v"
    env_xml+="        <key>${ek}</key><string>${ev}</string>
"
    INHERITED_KEYS="${INHERITED_KEYS:+$INHERITED_KEYS }$k"
  done < "$ENV_WORK/env.nul"
  rm -rf "$ENV_WORK"
fi

RUN_TOKEN="$(date +%s).$$.$RANDOM"
env_xml+="        <key>AUTODREAM_RUN_TOKEN</key><string>${RUN_TOKEN}</string>
"

ONDEMAND_OUT="$AUTODREAM_DIR/logs/ondemand.out.log"
ONDEMAND_ERR="$AUTODREAM_DIR/logs/ondemand.err.log"

read -r -d '' PLIST_BODY <<PLIST || true
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${RUN_SH}</string>
        <string>${TARGET}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
${env_xml}    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>AbandonProcessGroup</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>${ONDEMAND_OUT}</string>
    <key>StandardErrorPath</key>
    <string>${ONDEMAND_ERR}</string>
</dict>
</plist>
PLIST

LOG="$AUTODREAM_DIR/logs/run-$TARGET.log"
REPORT="$DREAMS_DIR/$TARGET.md"

if [ "$DRYRUN" = 1 ]; then
  echo "# would write $PLIST :"
  printf '%s\n' "$PLIST_BODY"
  echo
  echo "# would run:"
  echo "launchctl bootout   $DOMAIN/$LABEL   # (ignore failure if not loaded)"
  echo "launchctl bootstrap $DOMAIN $PLIST   # RunAtLoad fires the one-shot run"
  echo "# log:    $LOG"
  echo "# report: $REPORT"
  echo "# env from the scheduled job: ${INHERITED_KEYS:-none}${SCHED_PLIST:+ ($SCHED_PLIST)}"
  exit 0
fi

print_out="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null)" || print_out=""
holder_pid="$(sed -n '/^[[:space:]]*pid = [0-9]/{s/^[[:space:]]*pid = \([0-9][0-9]*\).*/\1/;p;q;}' <<<"$print_out")"
if [ -n "$holder_pid" ]; then
  holder_date="$(sed -n 's#.*<string>\([0-9]\{4\}-[0-9][0-9]-[0-9][0-9]\)</string>.*#\1#p' "$PLIST" 2>/dev/null | head -n 1)"
  echo "autodream-now: a run for ${holder_date:-another date} is still going (pid $holder_pid, label $LABEL)." >&2
  echo "  Launching now would kill it. Wait for it, or stop it first: launchctl bootout $DOMAIN/$LABEL" >&2
  exit 75
fi

( umask 077; rm -f "$PLIST"; printf '%s\n' "$PLIST_BODY" > "$PLIST" )
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$PLIST" >/dev/null || { echo "autodream-now: generated plist failed plutil lint" >&2; exit 65; }
fi

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
LOG_START=0
[ -f "$LOG" ] && LOG_START="$(wc -c < "$LOG" | tr -d ' ')"
launchctl bootstrap "$DOMAIN" "$PLIST"

echo "autodream: launched $LABEL for $TARGET (detached, no time cap)"
echo "  run log: $LOG"
echo "  report:  $REPORT"
echo "  this run's launchd stderr: $ONDEMAND_ERR"
echo "  env from the scheduled job: ${INHERITED_KEYS:-none}"

if [ "$WATCH" = 0 ]; then
  echo "Tail it with:  tail -f \"$LOG\""
  exit 0
fi

echo "Watching (Ctrl-C to stop watching; the run keeps going) ..."
for _ in $(seq 1 120); do [ -f "$LOG" ] && break; sleep 1; done
[ -f "$LOG" ] || { echo "log never appeared at $LOG; check $ONDEMAND_ERR" >&2; exit 1; }

tail -c +"$((LOG_START + 1))" -f "$LOG" &
TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null || true' EXIT

OUTCOME="${LOG%.log}.outcome"
job_finished() {
  local out
  out="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null)" || return 0
  grep -qE '^[[:space:]]*pid = [0-9]' <<<"$out" && return 1
  grep -qE '^[[:space:]]*runs = [1-9]' <<<"$out"
}
outcome_of_this_run() {
  [ -f "$OUTCOME" ] || return 0
  awk -v t="$RUN_TOKEN" '$1 == t { s = $2 } END { if (s != "") print s }' "$OUTCOME" 2>/dev/null
}

POLL="${AUTODREAM_WATCH_POLL:-5}"
deadline=$(( $(date +%s) + 90*60 ))
exit_on_outcome() {
  case "$1" in
    delivered) sleep 1; echo; echo "✓ report ready: $REPORT"; exit 0 ;;
    noop)
      sleep 1; echo
      if [ "$FORCE" = 1 ]; then
        echo "✗ the run ended without writing a new report; the previous one is unchanged: $REPORT" >&2
        exit 1
      fi
      echo "✓ report already existed; nothing to rebuild: $REPORT"
      exit 0 ;;
  esac
}
while :; do
  exit_on_outcome "$(outcome_of_this_run)"
  if job_finished; then
    sleep 1
    exit_on_outcome "$(outcome_of_this_run)"
    echo
    echo "✗ the run ended without delivering a report for $TARGET." >&2
    echo "  Why is in $LOG (and $ONDEMAND_ERR); an incomplete capture, if any, is at $REPORT.partial-*" >&2
    if [ "$FORCE" = 1 ] && [ -s "$REPORT" ]; then
      echo "  --force wrote nothing new: the previous one is unchanged: $REPORT" >&2
    fi
    exit 1
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo
    echo "gave up watching after 90 min; run may still be going — check $LOG" >&2
    exit 1
  fi
  sleep "$POLL"
done
