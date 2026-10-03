#!/bin/bash
# Mock `claude` binary for cc-autodream integration tests.
#
# run.sh invokes the real claude CLI for both layers. Here we stand in for it:
# read the prompt on stdin, find the two literal-path lines run.sh inlined, and
# write (or deliberately don't write) the expected output file — no model, no
# network. Which layer we are is decided by line 1 of the prompt.
#
# Env knobs (all optional):
#   MOCK_MODE=good           write findings (L1) / report (L2). [default]
#   MOCK_MODE=l1_incomplete  L1 writes nothing (simulates a worker that exits
#                            without producing JSON); L2 still writes its report.
#   MOCK_MODE=l1_silent      L1 writes nothing and prints nothing, exit 0: the real
#                            2026-09-13 omp death. l1_incomplete still prints "done".
#   MOCK_MODE=l1_malformed   L1 writes a non-empty file that is not JSON.
#   MOCK_MODE=l1_wrongtype   L1 writes {"findings":"oops"}: present, but not an array.
#   MOCK_MODE=l1_noisy_fail  L1 writes nothing, says why on stdout, exits 7.
#   MOCK_MODE=l1_context_overflow  L1 writes nothing, prints a context-size refusal,
#                            and exits 7. This must count as size even though the
#                            diagnostic also starts with "provider error".
#   MOCK_MODE=l1_nested_error  L1 writes a SUCCESSFUL findings file with an "error" key nested
#                            inside a finding. Only a top-level error key marks a failed triage.
#   MOCK_MODE=l2_fail        L2 writes no report and exits 1 (simulates the
#                            aggregator dying to a mid-run sleep). L1 is unaffected.
#                            Pair with AUTODREAM_L2_ATTEMPTS=1 so the test doesn't
#                            sit through the retry loop.
#   MOCK_MODE=pins           L1 writes a real session_path (like l1_badproject); L2
#                            writes a complete report plus one pins.jsonl pin for proj-a.
#   MOCK_MODE=pins_partial   as pins, but the report is truncated (like l2_partial).
#   MOCK_MODE=pins_forged    L1 writes session_path=$MOCK_FORGED_SESSION, a session it was
#                            never given; L2 pins $MOCK_PIN_PROJECT (default proj-a).
#   MOCK_MODE=pins_tamper    as pins, and L2 also appends $MOCK_FORGED_SESSION to sessions.txt,
#                            sessions-source.txt and a findings JSON, as an injected L2 could.
#   MOCK_MODE=pins_tamper_l1 the same tampering, done by L1 instead of L2.
#   MOCK_CAPTURE_DIR=<dir>   dump each layer's stdin + argv to <dir>/l{1,2}-*.txt
#                            so tests can assert on the exact prompt framing.
#   MOCK_CALL_LOG=<file>     append the L1 output path for every invocation of
#                            this mock, one per line — lets a test prove the
#                            model was (or was not) invoked for a given session
#                            (e.g. a noise-gated session should never appear).

input=$(cat)
mode="${MOCK_MODE:-good}"

# $1=findings dir. Adds $MOCK_FORGED_SESSION to the runner's worklist files, the way a
# prompt-injected model with the Write tool could.
tamper_worklist() {
  local h
  h=$(printf '%s' "$MOCK_FORGED_SESSION" | shasum -a 1 | cut -c1-12)
  printf '%s\n' "$MOCK_FORGED_SESSION" >> "$1/sessions.txt"
  printf '%s\tclaude\n' "$h" >> "$1/sessions-source.txt"
  printf '{"session_path":"%s","findings":[]}' "$MOCK_FORGED_SESSION" > "$1/$h.json"
}
line1=$(printf '%s\n' "$input" | sed -n '1p')
line2=$(printf '%s\n' "$input" | sed -n '2p')

if printf '%s' "$line1" | grep -q '^Session transcript'; then
  # ---- Layer 1: triage worker ----
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    printf '%s' "$input" > "$MOCK_CAPTURE_DIR/l1-stdin.txt"
    printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/l1-args.txt"
    # The engine environment the dispatcher gave this worker, one NAME=value per line, so a test
    # can tell an adapter-provided variable from one inherited by accident.
    env | grep -E '^(CLAUDE_CODE_DISABLE_CLAUDE_MDS|DISABLE_TELEMETRY|DISABLE_ERROR_REPORTING)=' | sort > "$MOCK_CAPTURE_DIR/l1-env.txt"
  fi
  out=$(printf '%s' "$line2" | sed 's/^Write your findings JSON to this literal absolute path: //')
  sess=$(printf '%s' "$line1" | sed 's/^Session transcript to analyze (literal absolute path): //')
  [ -n "${MOCK_CALL_LOG:-}" ] && printf '%s\n' "$out" >> "$MOCK_CALL_LOG"
  write_findings() { printf '{"session_path":"x","project":"proj-a","turn_count":2,"tool_call_count":0,"tools_used":[],"skills_invoked":[],"models_used":[],"notable_initiatives":[],"underlying_goal":null,"outcome":"fully_achieved","satisfaction_signals":{"happy":0,"satisfied":1,"dissatisfied":0,"frustrated":0},"instructions_given":["always run tests after edits"],"findings":[]}' > "$out"; }
  # Emit a real session_path but a deliberately WRONG project (what nondeterministic
  # haiku does), so run.sh's path-based normalization pass has something to correct.
  write_badproject() { printf '{"session_path":"%s","project":"WRONG-PROJECT","turn_count":2,"tool_call_count":0,"tools_used":[],"skills_invoked":[],"models_used":[],"notable_initiatives":[],"findings":[]}' "$sess" > "$out"; }
  case "$mode" in
    l1_incomplete) : ;;                 # never write — simulates a worker that exits empty
    l1_silent) exit 0 ;;                # never write AND print nothing: the 2026-09-13 omp
                                        # death (first-turn recall), exit 0 with empty stdout.
                                        # l1_incomplete still echoes "done" below, so it is not.
    l1_malformed)                       # non-empty output that is not a findings JSON.
      # The runner used to accept any non-empty file as success, delete both diagnostics,
      # and hand this to L2 on the final round.
      printf 'this is not json at all\n' > "$out"
      echo done
      exit 0 ;;
    l1_wrongtype)                       # .findings present but a STRING, not an array.
      # jq -e .findings is truthy for this, so it used to pass both the idempotency read
      # and the outbound validation and reach L2 as a successful result.
      printf '{"session_path":"x","findings":"oops"}' > "$out"
      echo done
      exit 0 ;;
    l1_noisy_fail)                      # writes nothing, but says WHY on stdout and exits
      # nonzero. This is the real shape: omp puts its diagnosis on stdout and only
      # "Working..." on stderr, and run.sh sent stdout to /dev/null, so every failure
      # arrived looking identical. Pins the exit-code and stdout capture.
      echo "provider error: 429 rate_limit_exceeded"
      exit 7 ;;
    l1_context_overflow)
      echo "provider error: 400 context_length_exceeded: prompt is too long"
      exit 7 ;;
    l1_rewrite_source)                  # a hostile worker: points every session at an engine that is not claude
      write_findings
      awk -F'\t' 'BEGIN{OFS="\t"} {print $1, "evil"}' "$(dirname "$out")/sessions-source.txt" > "$(dirname "$out")/sessions-source.txt.new" \
        && mv "$(dirname "$out")/sessions-source.txt.new" "$(dirname "$out")/sessions-source.txt" ;;
    l1_nested_error)                    # a real finding that happens to carry an error key
      printf '{"session_path":"x","project":"proj-a","findings":[{"category":"tool_loop","error":"ENOENT while reading a file","severity":"low"}]}' > "$out"
      echo done ;;
    l1_badproject|pins|pins_partial|pins_tamper) write_badproject ;;  # wrong project + real path — exercises normalization
    pins_tamper_l1) write_badproject; tamper_worklist "$(dirname "$out")" ;;
    pins_forged)                        # session_path names a session this worker was never given
      printf '{"session_path":"%s","project":"WRONG-PROJECT","findings":[]}' "$MOCK_FORGED_SESSION" > "$out" ;;
    l1_flaky)                           # fail the first dispatch per session, succeed on retry
      if [ -f "$out.attempt" ]; then write_findings; else : > "$out.attempt"; fi ;;
    *) write_findings ;;
  esac
  echo done
else
  # ---- Layer 2: aggregator ----
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    printf '%s' "$input" > "$MOCK_CAPTURE_DIR/l2-stdin.txt"
    printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/l2-args.txt"
  fi
  rep=$(printf '%s' "$line2" | sed 's/^Write the report to this literal absolute path: //')
  if [ "$mode" = "l2_fail" ]; then
    echo "mock: aggregator failed" >&2
    exit 1
  fi
  case "$mode" in
    pins|pins_partial|pins_forged|pins_tamper|pins_tamper_l1) writes_pins=1 ;;
    *) writes_pins=0 ;;
  esac
  if [ "$writes_pins" = 1 ]; then
    fdir=$(printf '%s' "$line1" | sed 's/^Findings directory to aggregate (literal absolute path): //')
    [ "$mode" = "pins_tamper" ] && tamper_worklist "$fdir"
    printf '{"project":"%s","title":"Mock lesson","body":"Mock evidence and rule.","kind":"correction"}\n' "${MOCK_PIN_PROJECT:-proj-a}" > "$fdir/pins.jsonl"
  fi
  # l2_partial: a NON-EMPTY report with no open-questions marker — what a mid-write kill
  # leaves behind. `-s` cannot tell this from a good report, which is why run.sh checks
  # for the marker instead.
  if [ "$mode" = "l2_partial" ] || [ "$mode" = "pins_partial" ]; then
    printf '# Autodream — mock\n\n## Top patterns\n\n1. truncated mid-w' > "$rep"
    echo "mock: partial write"
    exit 0
  fi
  # The open-questions marker is part of the real contract (PROMPT.md mandates it) and
  # run.sh now treats its absence as a truncated write, so the mock must emit it too.
  printf '# Autodream — mock\n\nmock aggregate report\n\n<!-- autodream:open-questions=0 -->\n' > "$rep"
  echo "report: $rep"
  echo "mock: 1 session reviewed, 0 findings, 0 edits"
fi
