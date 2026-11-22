#!/bin/bash
set -u

if [ $# -ne 2 ] || [ ! -d "${1:-}" ]; then
  echo "usage: apply-pins.sh <findings-dir> <target-date>" >&2
  exit 2
fi

FINDINGS_DIR=$1
TARGET_DATE=$2
PINS="$FINDINGS_DIR/pins.jsonl"
PROJECTS="$FINDINGS_DIR/pin-projects.tsv"
LEDGER="$FINDINGS_DIR/pins-applied.tsv"
RESULT="$FINDINGS_DIR/pins-result.txt"
SM="${SHARED_MEMORY_BIN:-shared-memory}"

if ! rm -f "$RESULT" 2>/dev/null || [ -e "$RESULT" ]; then
  echo "apply-pins: could not clear $RESULT; storing nothing so the old counters cannot pass for this run's" >&2
  exit 3
fi

VALID='select(type == "object")
  | select((.project | type) == "string" and (.project | length) > 0
           and (.project | test("[\\t\\n\\r]") | not))
  | select((.title | type) == "string" and (.title | test("\\S"))
           and (.title | length) <= 150 and (.title | test("[\\n\\r]") | not))
  | select((.body | type) == "string" and (.body | test("\\S"))
           and (.body | length) <= 4000)
  | select(.kind as $k | ["correction", "preference", "fact", "decision"] | any(. == $k))
  | select((has("harness") | not) or (.harness as $h | ["claude", "omp", "codex"] | any(. == $h)))
  | {project, title, body, kind} + (if has("harness") then {harness} else {} end)'

RESULT_FAILED=0
total=0 applied=0 duplicate=0 invalid=0 rejected_project=0 no_cwd=0 failed=0 unledgered=0 cli_missing=0 unreadable=0 unsupported_harness=0

write_result() {
  {
    printf 'pins_total: %s\n' "$total"
    printf 'pins_applied: %s\n' "$applied"
    printf 'pins_duplicate: %s\n' "$duplicate"
    printf 'pins_invalid: %s\n' "$invalid"
    printf 'pins_rejected_project: %s\n' "$rejected_project"
    printf 'pins_no_cwd: %s\n' "$no_cwd"
    printf 'pins_failed: %s\n' "$failed"
    printf 'pins_unledgered: %s\n' "$unledgered"
    printf 'pins_cli_missing: %s\n' "$cli_missing"
    printf 'pins_unreadable: %s\n' "$unreadable"
    printf 'pins_unsupported_harness: %s\n' "$unsupported_harness"
  } > "$RESULT.tmp" && mv "$RESULT.tmp" "$RESULT" || RESULT_FAILED=1
  echo "apply-pins: total=$total applied=$applied duplicate=$duplicate invalid=$invalid rejected_project=$rejected_project no_cwd=$no_cwd failed=$failed unledgered=$unledgered cli_missing=$cli_missing unreadable=$unreadable"
}

project_cwd() {
  local row
  row=$(P="$1" awk -F'\t' '$1 == ENVIRON["P"] { print "y\t" $2; exit }' "$PROJECTS" 2>/dev/null)
  [ -n "$row" ] || return 1
  printf '%s' "${row#y$'\t'}"
}

apply_line() {
  local canon project cwd hash ctx bank payload out rc id
  canon=$(jq -cS -s "if length == 1 then .[0] | $VALID else empty end" <<<"$1" 2>/dev/null)
  [ -n "$canon" ] || { echo invalid; return; }
  if [ "$GATE_OK" != 1 ] && [ "$(jq -r 'has("harness")' <<<"$canon")" = true ]; then echo unsupported_harness; return; fi
  project=$(jq -r .project <<<"$canon")
  cwd=$(project_cwd "$project") || { echo rejected_project; return; }
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then echo no_cwd; return; fi
  ctx=$("$SM" context --cwd "$cwd" </dev/null 2>/dev/null) || { echo failed; return; }
  bank=$(jq -er '.retainBank | strings | select(length > 0)' <<<"$ctx" 2>/dev/null) || { echo failed; return; }
  hash=$(printf '%s\n%s' "$bank" "$canon" | shasum -a 1 | cut -d' ' -f1)
  [[ $hash =~ ^[0-9a-f]{40}$ ]] || { echo failed; return; }
  if [ -e "$LEDGER" ] && [ ! -r "$LEDGER" ]; then echo failed; return; fi
  if [ -f "$LEDGER" ] && cut -f1 "$LEDGER" | grep -qxF "$hash"; then echo duplicate; return; fi
  payload=$(jq -cn --argjson pin "$canon" --arg date "$TARGET_DATE" --arg bank "$bank" '{
    bank: $bank,
    content: ($pin.title + "\n\n" + $pin.body),
    source: "cc-autodream",
    importance: 0.7,
    metadata: ({kind: $pin.kind, project: $pin.project, autodream_date: $date, origin: "cc-autodream"} + (if $pin.harness then {harness: $pin.harness} else {} end))
  }')
  out=$("$SM" call mnemopi_remember "$payload" --cwd "$cwd" </dev/null)
  rc=$?
  id=$(jq -er --argjson rc "$rc" '
    select((.status == "stored" and $rc == 0) or .status == "mutation_committed_journal_incomplete")
    | .memory_id | strings | select(length > 0)' <<<"$out" 2>/dev/null) || { echo failed; return; }
  if [ "$(jq -r .status <<<"$out" 2>/dev/null)" = "mutation_committed_journal_incomplete" ]; then
    echo "apply-pins: stored $id, but shared-memory reported mutation_committed_journal_incomplete" >&2
  fi
  if ! printf '%s\t%s\n' "$hash" "$id" >> "$LEDGER" 2>/dev/null; then
    echo "apply-pins: stored $id but could not write $LEDGER; a rerun will store this pin again" >&2
    echo unledgered
    return
  fi
  echo applied
}

if [ ! -e "$PINS" ]; then
  write_result
  exit $((RESULT_FAILED * 3))
fi

if ! CONTENT=$(cat -- "$PINS" 2>/dev/null); then
  unreadable=1
  write_result
  echo "apply-pins: could not read $PINS; pins stay there" >&2
  exit $((RESULT_FAILED * 3))
fi

if ! command -v "$SM" >/dev/null 2>&1; then
  cli_missing=1
  total=$(grep -c '[^[:space:]]' <<<"$CONTENT" || true)
  write_result
  echo "apply-pins: $SM not found; pins stay in $PINS" >&2
  exit $((RESULT_FAILED * 3))
fi

GATE_OK=0
case $("$SM" startup --host </dev/null 2>/dev/null) in
  *"--host needs a harness name"*) GATE_OK=1 ;;
esac

while IFS= read -r line <&3 || [ -n "$line" ]; do
  case $line in *[![:space:]]*) ;; *) continue ;; esac
  total=$((total + 1))
  case $(apply_line "$line") in
    applied)          applied=$((applied + 1)) ;;
    duplicate)        duplicate=$((duplicate + 1)) ;;
    invalid)          invalid=$((invalid + 1)) ;;
    rejected_project) rejected_project=$((rejected_project + 1)) ;;
    no_cwd)           no_cwd=$((no_cwd + 1)) ;;
    unledgered)       unledgered=$((unledgered + 1)) ;;
    unsupported_harness) unsupported_harness=$((unsupported_harness + 1)) ;;
    *)              failed=$((failed + 1)) ;;
  esac
done 3<<<"$CONTENT"

write_result
exit $((RESULT_FAILED * 3))
