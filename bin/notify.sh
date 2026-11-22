#!/bin/bash
set -u

FAILURE_MODE=0
BANNER_LABEL=FAILED
WARN_KEY=""
case "${1:-}" in
  --failure|--warning)
    FAILURE_MODE=1
    [ "$1" = "--warning" ] && BANNER_LABEL=WARNING
    DATE="${2:?Usage: notify.sh $1 <date> <reason>}"
    FAIL_REASON="${3:-the run stopped before it produced a report}"
    WARN_KEY="${4:-}"
    REPORT=""
    ;;
esac
if [ "$FAILURE_MODE" = "0" ]; then
  REPORT="${1:?Usage: notify.sh <report.md>  |  notify.sh --failure|--warning <date> <reason>}"
  DATE=$(basename "$REPORT" .md)
fi
_src="${BASH_SOURCE[0]}"; _lib="$(dirname "$_src")/lib-install-dir.sh"
[ -r "$_lib" ] || _lib="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/lib-install-dir.sh"
# shellcheck source=/dev/null
. "$_lib"
resolve_install_dir "$_src"
_rf="$(dirname "$_src")/report-format.sh"
[ -r "$_rf" ] || _rf="$(dirname "$(readlink "$_src" 2>/dev/null || echo "$_src")")/report-format.sh"
[ -r "$_rf" ] || { echo "notify: report-format.sh not found beside $_src or its link target" >&2; exit 1; }
# shellcheck source=/dev/null
. "$_rf"
INBOX_DIR="$AUTODREAM_DIR/inbox"
OPEN_CMD="${AUTODREAM_OPEN:-${SUBL:-open}}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MAKE_NOTIFIER="$SCRIPT_DIR/make-notifier.sh"
[ -x "$MAKE_NOTIFIER" ] || MAKE_NOTIFIER="$AUTODREAM_DIR/make-notifier.sh"
BRANDED="$AUTODREAM_DIR/cc-autodream.app/Contents/MacOS/terminal-notifier"
if [ ! -x "$BRANDED" ] && command -v terminal-notifier >/dev/null 2>&1 && [ -x "$MAKE_NOTIFIER" ]; then
  "$MAKE_NOTIFIER" >/dev/null 2>&1 || true
fi
NOTIFIER=""
[ -x "$BRANDED" ] && NOTIFIER="$BRANDED" || NOTIFIER="$(command -v terminal-notifier || true)"

mkdir -p "$INBOX_DIR"

if [ "$FAILURE_MODE" = "1" ]; then
  msg="Autodream $BANNER_LABEL for $DATE — $FAIL_REASON"
  label_lc=failure; group=fail
  [ "$BANNER_LABEL" = "WARNING" ] && { label_lc=warning; group=warn${WARN_KEY:+-$WARN_KEY}; }
  if [ "${AUTODREAM_NOTIFY_DRYRUN:-0}" = "1" ]; then
    echo "notify.sh: DRY RUN — would post a $label_lc banner for $DATE: $FAIL_REASON"
    exit 0
  fi
  posted=0
  if [ -n "$NOTIFIER" ]; then
    "$NOTIFIER" -title "Autodream — $DATE" -message "$BANNER_LABEL: $FAIL_REASON" \
      -group "autodream-$group-$DATE" >/dev/null 2>&1 \
      && { echo "notify.sh: posted $label_lc banner for $DATE"; posted=1; }
  fi
  if [ "$posted" = "0" ] && command -v osascript >/dev/null 2>&1; then
    osa_reason=$(printf '%s' "$FAIL_REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "display notification \"$BANNER_LABEL: $osa_reason\" with title \"Autodream — $DATE\"" \
      >/dev/null 2>&1 \
      && { echo "notify.sh: posted osascript $label_lc banner for $DATE"; posted=1; }
  fi
  [ "$posted" = "1" ] || echo "notify.sh: could not post a $label_lc banner for $DATE (continuing)"
  [ "$BANNER_LABEL" = "FAILED" ] || exit 0
  printf '%s\n' "$msg" > "$INBOX_DIR/$DATE-FAILED.txt" 2>/dev/null || true
  exit 0
fi

[ -f "$REPORT" ] || { echo "notify.sh: no such report: $REPORT" >&2; exit 1; }

QUESTIONS=$(report_questions "$REPORT")
QUESTIONS=$(printf "%s" "$QUESTIONS" | awk 'NF{p=1} p')
MARKER=$(report_marker_count "$REPORT")
count_matching(){ printf "%s\n" "$QUESTIONS" | grep -cE "$1" || true; }
if [ -n "$MARKER" ]; then
  COUNT="$MARKER"
elif [ -z "$QUESTIONS" ]; then
  COUNT=0
else
  first=$(printf '%s\n' "$QUESTIONS" | grep -v '^[[:space:]]*$' | head -1 | tr '[:upper:]' '[:lower:]')
  case "$first" in
    none*) COUNT=0 ;;
    *)
      COUNT=$(count_matching '^[[:space:]]*[0-9]+\.[[:space:]]')
      [ "$COUNT" -eq 0 ] && COUNT=$(count_matching '^\*\*.+\*\*')
      [ "$COUNT" -eq 0 ] && COUNT=$(count_matching '^[[:space:]]*[-*][[:space:]]')
      [ "$COUNT" -eq 0 ] && COUNT=1
      ;;
  esac
fi

if [ -z "$QUESTIONS" ] || [ "$COUNT" -eq 0 ]; then
  echo "notify.sh: $DATE has 0 open questions; nothing to pop"
  exit 0
fi

if [ "${AUTODREAM_NOTIFY_DRYRUN:-0}" = "1" ]; then
  echo "notify.sh: [dry run] $DATE has $COUNT open question$([ "$COUNT" -eq 1 ] || echo s); nothing written or posted"
  exit 0
fi

OUT="$INBOX_DIR/$DATE-open-questions.md"
cat > "$OUT" <<EOF
# Autodream — $DATE

**$COUNT open question$([ "$COUNT" -eq 1 ] || echo s)**

- Full report: \`$REPORT\`
- Triage interactively: \`$AUTODREAM_DIR/review.sh $DATE\`

---

$QUESTIONS
EOF

plural=$([ "$COUNT" -eq 1 ] || echo s)
OSA_BACKUP="${AUTODREAM_NOTIFY_OSA_BACKUP:-1}"
posted=0

if [ -n "$NOTIFIER" ]; then
  "$NOTIFIER" \
    -title "Autodream — $DATE" \
    -message "$COUNT open question$plural — click to open" \
    -execute "$OPEN_CMD '$OUT'" \
    -group "autodream-$DATE" \
    -sound Glass >/dev/null 2>&1 \
    && { echo "notify.sh: posted clickable notification for $DATE ($COUNT open question$plural)"; posted=1; } \
    || echo "notify.sh: terminal-notifier post failed (continuing)"
fi

if command -v osascript >/dev/null 2>&1 && { [ -z "$NOTIFIER" ] || [ "$OSA_BACKUP" != "0" ]; }; then
  if [ -n "$NOTIFIER" ]; then osa_sound=""; osa_role="backup"; else osa_sound=' sound name "Glass"'; osa_role="primary"; fi
  osascript -e "display notification \"$COUNT open question$plural — see inbox\" with title \"Autodream — $DATE\"$osa_sound" >/dev/null 2>&1 \
    && { echo "notify.sh: posted osascript $osa_role banner for $DATE"; posted=1; } \
    || echo "notify.sh: osascript notification post failed (continuing)"
fi

[ "$posted" -eq 1 ] || echo "notify.sh: WARNING no banner posted for $DATE (inbox written to $OUT)"

if sh -c "$OPEN_CMD \"\$1\"" _ "$OUT" 2>/dev/null; then
  echo "notify.sh: opened $OUT with: $OPEN_CMD"
else
  echo "notify.sh: '$OPEN_CMD' failed to open $OUT (file still written)"
fi
