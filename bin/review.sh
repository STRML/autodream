#!/bin/bash

set -u

usage(){
  cat <<'EOF'
Open an interactive Claude session with the latest autodream report preloaded
and instructions to walk through the open questions one at a time.

Usage: review.sh                  # opens latest report
       review.sh YYYY-MM-DD       # opens specific report
       review.sh --force [DATE]   # open even if there is nothing to triage

A report with nothing to triage does not get a session. Most nights the
report has no open questions, and launching claude just to be told "nothing
to do" costs a full session's tokens to print one line. Instead we detect
that case here and print the line ourselves. The check is deliberately
conservative: anything we cannot classify launches the session, because a
false "nothing to do" silently swallows real questions, while a false launch
only wastes tokens. --force bypasses it.

Where the triage session lands is controlled by AUTODREAM_TRIAGE_SURFACE
(set in $AUTODREAM_DIR/config, see config.example):
  inline  (default)  run the claude session right here in the current terminal
  cmux               launch it in its own cmux workspace

Why this knob exists: launching review.sh as a shell script makes macOS route
it to whatever app is the default handler for public.shell-script (iTerm2 on
this host), so the triage kept opening in iTerm2. `cmux` gives it a dedicated
workspace instead. Env vars override the config file; config overrides defaults.

The session runs on AUTODREAM_REVIEW_MODEL (default opus), passed as --model; a config
line or an environment variable of that name picks another.
EOF
}

_src="${BASH_SOURCE[0]}"
source_sibling(){
  local f; f="$(dirname "$_src")/$1"
  [ -r "$f" ] || f="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/$1"
  # shellcheck source=/dev/null
  . "$f"
}
source_sibling portable.sh
source_sibling lib-install-dir.sh
resolve_install_dir "$_src" review.sh
source_sibling report-format.sh

__env_dreams="${DREAMS_DIR:-}"; __env_claude="${CLAUDE_BIN:-}"
__env_surface="${AUTODREAM_TRIAGE_SURFACE:-}"; __env_cmux="${CMUX_BIN:-}"
__env_focus="${AUTODREAM_TRIAGE_FOCUS:-}"; __env_model="${AUTODREAM_REVIEW_MODEL:-}"
CONFIG_FILE="${AUTODREAM_CONFIG:-$AUTODREAM_DIR/config}"
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
[ -n "$__env_dreams" ] && DREAMS_DIR="$__env_dreams"
[ -n "$__env_claude" ] && CLAUDE_BIN="$__env_claude"
[ -n "$__env_surface" ] && AUTODREAM_TRIAGE_SURFACE="$__env_surface"
[ -n "$__env_cmux" ] && CMUX_BIN="$__env_cmux"
[ -n "$__env_focus" ] && AUTODREAM_TRIAGE_FOCUS="$__env_focus"
[ -n "$__env_model" ] && AUTODREAM_REVIEW_MODEL="$__env_model"

DREAMS_DIR="${DREAMS_DIR:-$(dirname "$AUTODREAM_DIR")/dreams}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
AUTODREAM_TRIAGE_SURFACE="${AUTODREAM_TRIAGE_SURFACE:-inline}"
AUTODREAM_REVIEW_MODEL="${AUTODREAM_REVIEW_MODEL:-opus}"
CMUX_BIN="${CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
AUTODREAM_TRIAGE_FOCUS="${AUTODREAM_TRIAGE_FOCUS:-false}"
[ "$AUTODREAM_TRIAGE_FOCUS" = "true" ] || AUTODREAM_TRIAGE_FOCUS="false"

FORCE=0
POSITIONAL=""
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "review.sh: unknown option: $arg" >&2; exit 2 ;;
    *)
      if [ -n "$POSITIONAL" ]; then
        echo "review.sh: expected one date, got '$POSITIONAL' and '$arg'" >&2
        exit 2
      fi
      POSITIONAL="$arg" ;;
  esac
done

if [ -n "$POSITIONAL" ]; then
  REPORT="$DREAMS_DIR/$POSITIONAL.md"
else
  REPORT=$(ls -t "$DREAMS_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md 2>/dev/null | head -1)
fi

if [ -z "${REPORT:-}" ] || [ ! -f "$REPORT" ]; then
  echo "review.sh: no autodream report found"
  echo "  looked in: $DREAMS_DIR"
  echo "  try: $(dirname "$0")/run.sh"
  exit 1
fi

DATE=$(basename "$REPORT" .md)

skip_notice(){
  echo "autodream $DATE: $1"
  echo "  report:      $REPORT"
  echo "  open anyway: $(basename "$0") --force $DATE"
}

if [ "$FORCE" -eq 0 ]; then
  if report_is_triaged "$REPORT"; then
    COUNT=$(report_decision_count "$REPORT" | tr -d ' ')
    if [ "$COUNT" -eq 1 ] 2>/dev/null; then
      skip_notice "already triaged (1 decision logged)."
    elif [ "$COUNT" -gt 1 ] 2>/dev/null; then
      skip_notice "already triaged ($COUNT decisions logged)."
    else
      skip_notice "already triaged."
    fi
    exit 0
  fi
  if [ "$(report_open_questions "$REPORT")" = "0" ]; then
    skip_notice "no open questions, nothing to triage."
    exit 0
  fi
fi

marker_age(){ echo $(( $(date +%s) - $(pstat_mtime "$LAUNCH_MARKER" || date +%s) )); }

if [ "$AUTODREAM_TRIAGE_SURFACE" = "cmux" ]; then
  CMUX="$CMUX_BIN"; [ -x "$CMUX" ] || CMUX=$(command -v cmux 2>/dev/null || true)
  if [ -n "$CMUX" ] && [ -x "$CMUX" ]; then
    LOGS_DIR="$AUTODREAM_DIR/logs"
    if ! mkdir -p "$LOGS_DIR"; then
      echo "review.sh: cannot create logs dir $LOGS_DIR" >&2
      exit 1
    fi
    REPORT_KEY=$(shasum -a 256 "$REPORT" 2>/dev/null | awk '{print $1}')
    if [ -z "$REPORT_KEY" ]; then
      echo "review.sh: shasum unavailable; cannot compute report digest, aborting triage" >&2
      exit 1
    fi
    LAUNCH_MARKER="$LOGS_DIR/review-launched-$DATE-$REPORT_KEY"
    LAUNCH_CONFIRMED="$LAUNCH_MARKER.confirmed"
    if [ ! -f "$CLAUDE_BIN" ] || [ ! -x "$CLAUDE_BIN" ]; then
      echo "review.sh: claude binary not found or not executable ($CLAUDE_BIN); not launching triage workspace" >&2
      exit 1
    fi
    CLAIM_GRACE=900
    CLAIMED_OWN=0
    find "$LOGS_DIR" -maxdepth 1 -name 'review-launched-*' -mtime +14 -delete 2>/dev/null || true
    if [ "$FORCE" -eq 0 ]; then
      if [ -e "$LAUNCH_CONFIRMED" ]; then
        echo "review.sh: $DATE triage already launched for this report (marker $LAUNCH_CONFIRMED)"
        echo "  open anyway: $(basename "$0") --force $DATE"
        exit 0
      fi
      if [ -d "$LAUNCH_MARKER" ]; then
        if [ "$(marker_age)" -ge "$CLAIM_GRACE" ]; then
          echo "review.sh: reclaiming abandoned claim $LAUNCH_MARKER"
          rmdir "$LAUNCH_MARKER" 2>/dev/null || true
        else
          echo "review.sh: $DATE triage launch already in progress by another invocation"
          exit 0
        fi
      fi
      if ! mkdir "$LAUNCH_MARKER" 2>/dev/null; then
        if [ -d "$LAUNCH_MARKER" ]; then
          echo "review.sh: $DATE triage launch already in progress by another invocation"
          exit 0
        fi
        echo "review.sh: cannot create claim $LAUNCH_MARKER" >&2
        exit 1
      fi
      CLAIMED_OWN=1
    fi
    SELF="$(cd "$(dirname "$_src")" && pwd)/$(basename "$_src")"
    TAB_TITLE="$DATE Autodream Triage"
    FORCE_ARG=""; [ "$FORCE" -eq 1 ] && FORCE_ARG=" --force"
    echo "review.sh: opening $DATE triage in a new cmux workspace (focus=$AUTODREAM_TRIAGE_FOCUS)"
    shq(){ printf '%q' "$1"; }
    INNER_CMD="env AUTODREAM_TRIAGE_SURFACE=inline CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 AUTODREAM_REVIEW_MODEL=$(shq "$AUTODREAM_REVIEW_MODEL") DREAMS_DIR=$(shq "$DREAMS_DIR") CLAUDE_BIN=$(shq "$CLAUDE_BIN") $(shq "$SELF") $(shq "$DATE")$FORCE_ARG"
    WS_OUT=$("$CMUX" workspace create \
      --name "$TAB_TITLE" \
      --cwd "$HOME" \
      --command "$INNER_CMD" \
      --focus "$AUTODREAM_TRIAGE_FOCUS" 2>&1)
    WS_RC=$?
    echo "$WS_OUT"
    if [ "$WS_RC" -ne 0 ]; then
      if [ "$CLAIMED_OWN" -eq 1 ]; then
        rmdir "$LAUNCH_MARKER" 2>/dev/null || true
      elif [ -d "$LAUNCH_MARKER" ]; then
        [ "$(marker_age)" -ge "$CLAIM_GRACE" ] && rmdir "$LAUNCH_MARKER" 2>/dev/null || true
      fi
      echo "review.sh: cmux workspace create failed (exit $WS_RC); triage not opened" >&2
      exit 1
    fi
    if ! touch "$LAUNCH_CONFIRMED"; then
      echo "review.sh: WARNING could not write confirmed token $LAUNCH_CONFIRMED" >&2
    fi
    WS_REF=$(printf '%s\n' "$WS_OUT" | sed -n 's/.*\(workspace:[0-9][0-9]*\).*/\1/p' | head -1)
    if [ -n "$WS_REF" ]; then
      ( for _ in 1 2 3; do
          sleep 3
          "$CMUX" tab-action --action rename --workspace "$WS_REF" --title "$TAB_TITLE" >/dev/null 2>&1
        done ) &
    fi
    exit 0
  fi
  if [ -t 0 ]; then
    echo "review.sh: cmux not found ($CMUX_BIN); falling back to inline triage" >&2
  else
    echo "review.sh: cmux not found ($CMUX_BIN) and stdin is not a TTY; aborting scheduled triage (no headless launch)" >&2
    exit 1
  fi
fi

REPORT_BYTES=$(wc -c < "$REPORT" | tr -d ' ')

QUESTIONS_CAP=12000
QUESTIONS_TMP=$(mktemp -t autodream-questions.XXXXXX) || { echo "review.sh: mktemp failed; not launching triage" >&2; exit 1; }
trap 'rm -f "$QUESTIONS_TMP"' EXIT
report_questions "$REPORT" > "$QUESTIONS_TMP" || { echo "review.sh: could not read the open questions from $REPORT; not launching triage" >&2; exit 1; }

TRUNCATED=0
QUESTIONS_BYTES=$(wc -c < "$QUESTIONS_TMP" | tr -d ' ')
if [ "${QUESTIONS_BYTES:-0}" -gt "$QUESTIONS_CAP" ]; then
  TRUNCATED=1
  : > "$QUESTIONS_TMP"
fi

SYSTEM_TMP=$(mktemp -t autodream-review.XXXXXX) || { echo "review.sh: mktemp failed; not launching triage" >&2; exit 1; }
trap 'rm -f "$QUESTIONS_TMP" "$SYSTEM_TMP"' EXIT
if [ "$TRUNCATED" -eq 1 ] && report_has_questions_block "$REPORT"; then
  QUESTIONS_INTRO="The open questions from the $DATE report are too long to quote here (${QUESTIONS_BYTES} bytes). Read them from $REPORT, between the $QUESTIONS_BEGIN and $QUESTIONS_END lines, before your first reply; nothing from that section is in this prompt."
elif [ "$TRUNCATED" -eq 1 ]; then
  QUESTIONS_INTRO="The open questions from the $DATE report are too long to quote here (${QUESTIONS_BYTES} bytes). Read them from $REPORT's \"## Open questions for the user\" section before your first reply; nothing from that section is in this prompt."
else
  QUESTIONS_INTRO="The open questions from the $DATE report ($REPORT, $REPORT_BYTES bytes) are quoted in full below. Work from these. Do not read the whole report into context and never dump it back to the user; the wider report is on disk at that path if a question needs one specific number from it."
fi
cat > "$SYSTEM_TMP" <<EOF
You are the morning autodream review partner. The user has opened this terminal session to triage open questions from last night's autodream run.

$QUESTIONS_INTRO

<open-questions date="$DATE" path="$REPORT" truncated="$TRUNCATED">
$(cat "$QUESTIONS_TMP")
</open-questions>

Workflow:

1. Restate ONE open question (in order), in full, before asking for any decision. The user has not read the report this morning, so a bare label ("now question 2", "next: the hook failure") is never enough. The restatement must carry (a) the question itself in plain words, (b) every motivation behind it: the findings, session counts, evidence quotes and report section numbers that make it a question, and (c) every potential fix the report or you can see, each with its trade-off. Ask for the decision with the AskUserQuestion tool, passing \`metadata: {"source": "autodream-triage"}\` (an ask-gate hook lets these through, since each triage decision is the user's), but only after (a), (b) and (c) are on screen.
2. Say what you checked or could not check since the report was written, if anything (a file that now exists, a count that moved).
3. Recommend one concrete action from (c). Be opinionated — the user trusts your judgment.
4. Wait for: approve / modify / skip / discuss.
5. If approved: execute (run shell commands, edit files — you have bypassPermissions). If modified: incorporate the change, confirm, then execute. If skipped or discussed: log the decision in a one-line follow-up comment at the bottom of $REPORT under a "## Triage decisions" section (create if absent).
6. Move to the next question. Don't batch multiple questions in one turn.

When all open questions are resolved, write a brief summary at the bottom of $REPORT under "## Triage decisions", thank the user, and exit.

Other rules:
- You may edit any file the autodream prompt allows you to edit (settings.json, .claude/* in the relevant project), plus you may now edit ~/.claude/CLAUDE.md, ~/.claude/rules/*, and ~/.claude/docs/guardrails/* if the user explicitly approves.
- Don't proceed on any CLAUDE.md / rules / guardrails edit without explicit per-edit approval — those are global.
- Be terse everywhere except the question restatement in step 1, which is always complete. One question, one decision, one action, then next.
EOF
SYSTEM=$(cat "$SYSTEM_TMP")
rm -f "$SYSTEM_TMP" "$QUESTIONS_TMP"
trap - EXIT

echo "─── autodream review: $DATE ($REPORT_BYTES bytes) ───"
echo "Starting triage. /quit to exit."
echo

cd "$HOME" || exit 1
exec "$CLAUDE_BIN" \
  --permission-mode bypassPermissions \
  --append-system-prompt "$SYSTEM" \
  "Start the triage: restate the first open question and recommend one action." \
  --model "$AUTODREAM_REVIEW_MODEL"
