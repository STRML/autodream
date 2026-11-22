#!/usr/bin/env bash
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
# The one-shot job gets the scheduled job's environment (that is where a login setting
# such as CLAUDE_CONFIG_DIR lives), so a manual run uses the same login as the nightly.
#
# Everything is auto-detected — nothing is hardcoded to a particular user or host.
set -euo pipefail

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
# Installed copies are symlinks: a merge updates them before install.sh links a new helper.
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

# ---------------------------------------------------------------- arg parsing --
DATE_ARG=""
FORCE=0
WATCH=0
DRYRUN=0
for a in "$@"; do
  case "$a" in
    --force)   FORCE=1 ;;
    --watch)   WATCH=1 ;;
    --dry-run) DRYRUN=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) DATE_ARG="$a" ;;
    *) echo "autodream-now: unknown argument '$a'" >&2; exit 64 ;;
  esac
done

# ----------------------------------------------------- resolve our own location --
# macOS has no `readlink -f`; walk the symlink chain by hand. The helper is
# symlinked into $AUTODREAM_DIR by install.sh, so resolving gets us the real bin/.
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

# ------------------------------------------------------------- state locations --
# Defaults mirror run.sh's own defaults; honor the same env overrides so a
# customized install (different AUTODREAM_DIR / DREAMS_DIR) still works.
# Resolve the install dir from our own location, the same idiom as the siblings.
# scheduler-label.sh decides ownership by comparing a plist's runner dir against this value,
# so a hardcoded default never matched a custom-path install (./install.sh /custom) and the
# .ondemand label silently left that install's namespace. Unresolved BASH_SOURCE on purpose:
# the symlink's own directory is the install dir, while BIN_DIR above resolves through to
# the repo.
_src="${BASH_SOURCE[0]}"; _lib="$(dirname "$_src")/lib-install-dir.sh"
# Installed copies are symlinks: a merge updates them before install.sh links a new helper.
[ -r "$_lib" ] || _lib="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/lib-install-dir.sh"
# shellcheck source=/dev/null
. "$_lib"
resolve_install_dir "$_src"
# The same default run.sh uses, so --watch and the plist point where run.sh writes.
DREAMS_DIR="${DREAMS_DIR:-$HOME/.claude/dreams}"
mkdir -p "$AUTODREAM_DIR/logs"

# Target date: explicit arg, else "yesterday" computed exactly like run.sh does —
# plain system-local BSD date, no TZ override, so we can never disagree with run.sh
# about which day "yesterday" is.
if [ -n "$DATE_ARG" ]; then
  TARGET="$DATE_ARG"
else
  TARGET="$(pdate_yesterday)"
fi

# --------------------------------------------------------------- launchd label --
UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"
# Reuse the base label from OUR installed scheduled job so the transient label sits in the
# same namespace. scheduler-label.sh owns that decision for install.sh too; it will not hand
# back a label belonging to another autodream install. A conflict on the default name is not
# fatal here, because we only borrow the namespace.
BASE_LABEL="$("$BIN_DIR/scheduler-label.sh" "$AUTODREAM_DIR" 2>/dev/null || true)"
[ -n "$BASE_LABEL" ] || BASE_LABEL="com.$(id -un | tr -dc 'a-zA-Z0-9').autodream"
# The on-demand label always carries a hash of the resolved install dir. The bootout below
# evicts whatever holds this label, and another install's on-demand plist lives in its own
# AUTODREAM_DIR where no scan can see it. Two installs share a base label whenever one holds
# the default or neither has a scheduled job, so no base-label check can rule the collision
# out. pwd -P keeps the hash the same for a trailing slash or a symlinked path, so bootout
# still finds this install's prior run.
INSTALL_REAL="$(cd "$AUTODREAM_DIR" 2>/dev/null && pwd -P)" || INSTALL_REAL="${AUTODREAM_DIR%/}"
LABEL="${BASE_LABEL}.ondemand.$(printf '%s' "$INSTALL_REAL" | shasum -a 1 | cut -c1-8)"
PLIST="$AUTODREAM_DIR/${LABEL}.plist"

# ----------------------------------------------------------------------- PATH --
# launchd agents start with a minimal PATH. Seed it with the dirs of the tools the
# pipeline shells out to (claude, git, bash) plus the usual suspects.
path_dirs=""
for tool in claude git bash; do
  if b="$(command -v "$tool" 2>/dev/null)"; then
    d="$(cd "$(dirname "$b")" && pwd)"
    case ":$path_dirs:" in *":$d:"*) ;; *) path_dirs="${path_dirs:+$path_dirs:}$d" ;; esac
  fi
done
PATH_VAL="${path_dirs:+$path_dirs:}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ------------------------------------------------------ build the plist content --
# EnvironmentVariables: PATH always, plus any path overrides the caller set, plus FORCE.
env_xml="        <key>PATH</key><string>${PATH_VAL}</string>
"
env_xml+="        <key>AUTODREAM_DIR</key><string>${AUTODREAM_DIR}</string>
"
env_xml+="        <key>DREAMS_DIR</key><string>${DREAMS_DIR}</string>
"
[ "$FORCE" = 1 ] && env_xml+="        <key>AUTODREAM_FORCE</key><string>1</string>
"

# The scheduled job's environment, minus the four keys set above. A login setting lives
# there: a host whose nightly runs on a non-default Claude profile sets CLAUDE_CONFIG_DIR
# in the job, and a one-shot plist built from PATH alone ran the CLI on the default
# profile. With no login there, every L2 attempt wrote "Not logged in · Please run /login"
# and the date stayed unassembled. The caller's own shell environment is deliberately NOT
# copied: a terminal inside another Claude profile would run the job under that login.
# scheduler-label.sh --plist applies the same ownership rule the label uses, so a plist
# that merely shares the label is never read. No scheduled job means nothing is inherited,
# which is the old behavior. A scheduled job whose environment cannot be read (no plutil, no
# jq on the job's own PATH or the caller's, a plist that will not convert) refuses the launch:
# copying nothing would start the run logged out again, the failure this exists to prevent.
# $1=variable to set, $2=text -> the text with & < > escaped, trailing newlines kept (a
# command substitution would strip them, so the text carries a sentinel through sed).
xml_escape_into() {
  local out
  out="$(printf '%sx' "$2" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
  printf -v "$1" '%s' "${out%x}"
}
SCHED_PLIST="$("$BIN_DIR/scheduler-label.sh" --plist "$AUTODREAM_DIR" 2>/dev/null || true)"
INHERITED_KEYS=""
if [ -n "$SCHED_PLIST" ]; then
  ENV_WORK="$(mktemp -d "${TMPDIR:-/tmp}/autodream-now.XXXXXX")" || { echo "autodream-now: cannot make a scratch directory" >&2; exit 65; }
  # AUTODREAM_JQ_BIN names the jq to use (the tests point it at a failing one); else the job's own PATH
  # is searched first, because the caller's PATH may lack /opt/homebrew/bin where jq often lives.
  JQ_BIN="${AUTODREAM_JQ_BIN:-$(PATH="$PATH_VAL:$PATH" command -v jq 2>/dev/null || true)}"
  PLUTIL_BIN="$(PATH="$PATH_VAL:$PATH" command -v plutil 2>/dev/null || true)"
  if [ -z "$JQ_BIN" ] || [ -z "$PLUTIL_BIN" ]; then
    rm -rf "$ENV_WORK"
    echo "autodream-now: the scheduled job $SCHED_PLIST has an environment to copy and this needs both plutil and jq (not found); refusing to launch logged out" >&2
    exit 65
  fi
  # A key the plist does not have is an empty environment, not a failure; a plist that will not
  # convert, or a jq that fails, is.
  "$PLUTIL_BIN" -convert json -o "$ENV_WORK/job.json" "$SCHED_PLIST" 2>/dev/null \
    && "$JQ_BIN" -j '(.EnvironmentVariables // {}) | to_entries[] | select(.value | type == "string") | .key, "\u0000", .value, "\u0000"' "$ENV_WORK/job.json" > "$ENV_WORK/env.nul" 2>/dev/null \
    || { rm -rf "$ENV_WORK"; echo "autodream-now: could not read the environment of the scheduled job $SCHED_PLIST; refusing to launch logged out" >&2; exit 65; }
  # NUL-separated key/value pairs, so no value can be split or unescaped on the way through.
  ek=""; ev=""   # set by xml_escape_into (printf -v)
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

# This launch's id. run.sh writes it beside how the run ended (logs/run-<date>.outcome), and --watch
# reads that and nothing else, so the line cannot be mixed up with an earlier run's.
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

# ------------------------------------------------------------------ go go go --
# Every on-demand run for this install shares one label, and `bootout` below kills the
# process behind it. Launching a second date while the first was still running evicted
# the first mid-run, with no report and no error (#78). A loaded job with a live pid is
# in flight: refuse, and name the date that holds the label. A loaded job with no pid has
# finished and is safe to boot out. This has to run before the plist is rewritten, because
# the holder's date is read back out of the old plist.
# Capture first and parse the capture: a pipeline under pipefail could lose a pid it had read.
# A print that fails means the label is not loaded; nothing to protect.
print_out="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null)" || print_out=""
holder_pid="$(sed -n '/^[[:space:]]*pid = [0-9]/{s/^[[:space:]]*pid = \([0-9][0-9]*\).*/\1/;p;q;}' <<<"$print_out")"
if [ -n "$holder_pid" ]; then
  holder_date="$(sed -n 's#.*<string>\([0-9]\{4\}-[0-9][0-9]-[0-9][0-9]\)</string>.*#\1#p' "$PLIST" 2>/dev/null | head -n 1)"
  echo "autodream-now: a run for ${holder_date:-another date} is still going (pid $holder_pid, label $LABEL)." >&2
  echo "  Launching now would kill it. Wait for it, or stop it first: launchctl bootout $DOMAIN/$LABEL" >&2
  exit 75
fi

# Owner-only: the body now carries the scheduled job's environment, which can hold more
# than paths. launchd only refuses group- or world-writable agent plists, so 600 loads.
( umask 077; rm -f "$PLIST"; printf '%s\n' "$PLIST_BODY" > "$PLIST" )
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$PLIST" >/dev/null || { echo "autodream-now: generated plist failed plutil lint" >&2; exit 65; }
fi

# Clear any finished instance, then bootstrap. RunAtLoad is the ONLY trigger — fires the
# one-shot run exactly once. Do NOT also kickstart, or a fast run (e.g. the
# idempotency no-op) would execute twice.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# Taken before bootstrap, for --watch: a date's log already holds every earlier attempt's lines.
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

# --------------------------------------------------------------------- --watch --
echo "Watching (Ctrl-C to stop watching; the run keeps going) ..."
# Wait for the log to materialize.
for _ in $(seq 1 120); do [ -f "$LOG" ] && break; sleep 1; done
[ -f "$LOG" ] || { echo "log never appeared at $LOG; check $ONDEMAND_ERR" >&2; exit 1; }

# This run's lines only: the log for a date accumulates every earlier attempt.
tail -c +"$((LOG_START + 1))" -f "$LOG" &
TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null || true' EXIT

# Two separate questions.
#   Did this run deliver? Only run.sh knows, so it says so: one line in logs/run-<date>.outcome,
#   "<this launch's token> delivered|noop". Nothing else counts: not a report file that looks complete
#   (run.sh keeps a marker-bearing capture with no AUTODREAM_REPORT_END sentinel at the report path
#   between L2 attempts, and a killed run leaves it there), not the file's mtime (a whole second, so a
#   report written in the launch second reads as new), not a log line (the log also holds model text),
#   and not a completeness predicate evaluated here (another config's questions epoch, and the runner
#   accepts a legacy report before that epoch that has no marker). The token is this launch's own, so
#   an earlier run's line is never read as this one's.
#   Is the run over? launchd has run the job and holds no process for it. Without this, a run whose
#   every attempt failed was watched for the full 90 minutes.
OUTCOME="${LOG%.log}.outcome"
job_finished() { # 0 once launchd has run the job and no process is left
  local out
  out="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null)" || return 0   # unloaded: nothing to wait for
  grep -qE '^[[:space:]]*pid = [0-9]' <<<"$out" && return 1
  grep -qE '^[[:space:]]*runs = [1-9]' <<<"$out"                      # runs = 0: not started yet
}
outcome_of_this_run() { # delivered | noop | (nothing yet)
  [ -f "$OUTCOME" ] || return 0
  awk -v t="$RUN_TOKEN" '$1 == t { s = $2 } END { if (s != "") print s }' "$OUTCOME" 2>/dev/null
}

POLL="${AUTODREAM_WATCH_POLL:-5}"
# Generous ceiling (90 min) since real runs can be long.
deadline=$(( $(date +%s) + 90*60 ))
report_outcome() { # $1=delivered|noop -> prints the verdict and exits; returns when there is none
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
  report_outcome "$(outcome_of_this_run)"
  if job_finished; then
    sleep 1
    report_outcome "$(outcome_of_this_run)"   # the line can land just before the job exits
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
