#!/bin/bash

if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  if [ -n "${MOCK_AUTH_STATUS:-}" ]; then
    printf '%s\n' "$MOCK_AUTH_STATUS"
  else
    printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"test@example.com","subscriptionType":"max"}'
  fi
  exit 0
fi

input=$(cat)
mode="${MOCK_MODE:-good}"

out_format=""; req_model=""; prev=""
for a in "$@"; do
  case "$prev" in
    --output-format) out_format=$a ;;
    --model) req_model=$a ;;
  esac
  prev=$a
done
l1_reply() {
  if [ "$out_format" = json ]; then
    jq -cn --arg m "${MOCK_SERVED_MODEL:-$req_model}" \
      '{type: "result", subtype: "success", is_error: false, result: "done", modelUsage: {($m): {costUSD: 0.0125}}, total_cost_usd: 0.0125}'
  else
    echo "done"
  fi
}

tamper_worklist() {
  local h
  h=$(printf '%s' "$MOCK_FORGED_SESSION" | shasum -a 1 | cut -c1-12)
  printf '%s\n' "$MOCK_FORGED_SESSION" >> "$1/sessions.txt"
  printf '%s\tclaude\n' "$h" >> "$1/sessions-source.txt"
  printf '{"session_path":"%s","findings":[]}' "$MOCK_FORGED_SESSION" > "$1/$h.json"
}
line1=$(printf '%s\n' "$input" | sed -n '1p')
line2=$(printf '%s\n' "$input" | sed -n '2p')

if [ "$line1" = "AUTODREAM_THREADS_LINKER" ]; then
  threads_mode="${MOCK_THREADS_MODE:-good}"
  threads_request=$(printf '%s\n' "$input" | sed -n '/^AUTODREAM_THREADS_REQUEST$/,$p' | sed '1d' | sed -n '1p')
  threads_call=1
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    mkdir -p "$MOCK_CAPTURE_DIR"
    if [ -f "$MOCK_CAPTURE_DIR/threads-calls.txt" ]; then
      threads_call=$(( $(wc -l < "$MOCK_CAPTURE_DIR/threads-calls.txt" | tr -d ' ') + 1 ))
    fi
    printf '%s\n' "$threads_call" >> "$MOCK_CAPTURE_DIR/threads-calls.txt"
    printf '%s' "$input" > "$MOCK_CAPTURE_DIR/threads-stdin-$threads_call.txt"
    printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/threads-args-$threads_call.txt"
  fi
  if [ -n "${MOCK_BACKFILL_OUTPUT_FILE:-}" ]; then
    if grep -q '^planned_calls:' "$MOCK_BACKFILL_OUTPUT_FILE" 2>/dev/null; then
      printf 'true\n' > "$MOCK_BACKFILL_PLAN_SEEN"
    else
      printf 'false\n' > "$MOCK_BACKFILL_PLAN_SEEN"
    fi
  fi
  threads_good(){
    printf '%s\n' "$threads_request" | jq -c '.candidates[] | {hash:.hash,thread:"new",title:.goal,finished:false}'
  }
  case "$threads_mode" in
    fail_refusal) echo "provider refused the linker request" >&2; exit 1 ;;
    fail_nonzero) threads_good; echo "linker failed after partial stdout" >&2; exit 7 ;;
    fail_timeout) sleep 5; exit 0 ;;
    fail_unusable) printf 'not a JSON assignment\n'; exit 0 ;;
    invalid_assignments) printf '{"hash":"unknown","thread":"new","finished":false}\n'; exit 0 ;;
    close_during_call)
      /bin/bash "$MOCK_THREADS_CLI" close "$MOCK_THREADS_CLOSE_ID" >/dev/null 2>&1
      printf '%s\n' "$?" > "$MOCK_CAPTURE_DIR/threads-close-exit.txt"
      jq -c --arg id "$MOCK_THREADS_CLOSE_ID" '.candidates[] | {hash:.hash,thread:$id,title:.goal,finished:true}' \
        <<< "$threads_request"
      exit 0
      ;;
    ideas_during_call)
      MOCK_THREADS_MODE=good MOCK_CAPTURE_DIR='' /bin/bash "$MOCK_THREADS_CLI" update \
        "$(jq -r '.date' <<< "$threads_request")" < "$MOCK_THREADS_SOURCE_ROWS" >/dev/null 2>&1 || exit 1
      threads_good
      exit 0
      ;;
    attach_existing)
      jq -c --arg id "$MOCK_THREADS_CLOSE_ID" '.candidates[] | {hash:.hash,thread:$id,title:.goal,finished:false}' \
        <<< "$threads_request"
      exit 0
      ;;
    attach_ideas)
      jq -c --arg id "$MOCK_THREADS_CLOSE_ID" '.candidates[] | {hash:.hash,thread:(if .kind == "idea" then $id else "new" end),title:.goal,finished:false}' \
        <<< "$threads_request"
      exit 0
      ;;
    finish_ideas)
      jq -c --arg id "$MOCK_THREADS_CLOSE_ID" '.candidates[] | {hash:.hash,thread:(if .kind == "idea" then $id else "new" end),title:.goal,finished:true}' <<< "$threads_request"
      exit 0
      ;;
    reject_idea)
      jq -c --arg reject_goal "$MOCK_THREADS_REJECT_GOAL" '.candidates[] | {hash:.hash,thread:(if .goal == $reject_goal then "t-ffffffff" else "new" end),title:.goal,finished:false}' \
        <<< "$threads_request"
      exit 0
      ;;
    finished)
      jq -c '.candidates[] | {hash:.hash,thread:"new",title:.goal,finished:true}' <<< "$threads_request"
      exit 0
      ;;
    finished_existing)
      jq -c --arg id "$MOCK_THREADS_CLOSE_ID" '.candidates[] | {hash:.hash,thread:$id,title:.goal,finished:true}' <<< "$threads_request"
      exit 0
      ;;
    omit_last)
      jq -c '.candidates[0] | {hash:.hash,thread:"new",title:.goal,finished:false}' <<< "$threads_request"
      exit 0
      ;;
    bad_assignments)
      first=$(jq -r '.candidates[0].hash // empty' <<< "$threads_request")
      second=$(jq -r '.candidates[1].hash // empty' <<< "$threads_request")
      threads_good | sed -n '1p'
      printf '{not-json}\n'
      printf '{"hash":"%s","thread":"t-ffffffff","finished":false}\n' "$second"
      printf '{"hash":"2099-12-31-ffffffffffff","thread":"new","finished":false}\n'
      exit 0
      ;;
    bad_finished)
      first=$(jq -r '.candidates[0].hash // empty' <<< "$threads_request")
      jq -cn --arg hash "$first" '{hash:$hash,thread:"new",finished:"yes"}'
      jq -c '.candidates[1:][] | {hash:.hash,thread:"new",title:.goal,finished:false}' <<< "$threads_request"
      exit 0
      ;;
    bad_duplicate)
      first=$(jq -c '.candidates[0] // empty' <<< "$threads_request")
      printf '%s\n' "$first" | jq -c '{hash:.hash,thread:"new",title:.goal,finished:false}'
      printf '%s\n' "$first" | jq -c '{hash:.hash,thread:"new",title:.goal,finished:false}'
      jq -c '.candidates[1:][] | {hash:.hash,thread:"new",title:.goal,finished:false}' <<< "$threads_request"
      exit 0
      ;;
    bad_conflict)
      first=$(jq -c '.candidates[0] // empty' <<< "$threads_request")
      printf '%s\n' "$first" | jq -c '{hash:.hash,thread:"new",title:.goal,finished:false}'
      printf '%s\n' "$first" | jq -c '{hash:.hash,thread:"t-ffffffff",title:.goal,finished:false}'
      jq -c '.candidates[1:][] | {hash:.hash,thread:"new",title:.goal,finished:false}' <<< "$threads_request"
      exit 0
      ;;
    try_write)
      if printf '%s\n' "$@" | grep -qx 'Write' && [ -n "${MOCK_THREADS_WRITE:-}" ]; then
        : > "$MOCK_THREADS_WRITE"
      fi
      threads_good
      exit 0
      ;;
    *) threads_good; exit 0 ;;
  esac
fi

if [ "$line1" = "ping" ]; then
  printf 'Working...\n' >&2
  case "$mode" in
    l1_incomplete|l1_silent|l1_noisy_fail|l1_context_overflow|l1_hang|l1_exit124|l1_exit137) : ;;
    warmup_diag) echo "error: model deepseek/deepseek-flash is not available" ;;
    *) echo ok ;;
  esac
  exit 0
fi

if printf '%s' "$line1" | grep -q '^Session transcript'; then
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    printf '%s' "$input" > "$MOCK_CAPTURE_DIR/l1-stdin.txt"
    printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/l1-args.txt"
    env | grep -E '^(CLAUDE_CODE_DISABLE_CLAUDE_MDS|DISABLE_TELEMETRY|DISABLE_ERROR_REPORTING)=' | sort > "$MOCK_CAPTURE_DIR/l1-env.txt"
    printf '%s\n' "${HOME:-}" > "$MOCK_CAPTURE_DIR/l1-home.txt"
  fi
  out=$(printf '%s' "$line2" | sed 's/^Write your findings JSON to this literal absolute path: //')
  sess=$(printf '%s' "$line1" | sed 's/^Session transcript to analyze (literal absolute path): //')
  fdir_l1="${FINDINGS_DIR:-$(dirname "$out")}"
  [ -n "${MOCK_CALL_LOG:-}" ] && printf '%s\n' "$out" >> "$MOCK_CALL_LOG"
  [ -n "${MOCK_CAPTURE_DIR:-}" ] && [ -r "$sess" ] && cp "$sess" "$MOCK_CAPTURE_DIR/l1-read-$(basename "$out" .json).txt"
  [ -n "${MOCK_CAPTURE_DIR:-}" ] && printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/l1-args-$(basename "$out" .json).txt"
  [ -n "${MOCK_CAPTURE_DIR:-}" ] && printf '%s' "$input" > "$MOCK_CAPTURE_DIR/l1-stdin-$(basename "$out" .json).txt"
  [ -n "${MOCK_TRANSCRIPT_LOG:-}" ] && printf '%s\t%s\n' "$sess" "$(wc -c < "$sess" 2>/dev/null | tr -d ' ')" >> "$MOCK_TRANSCRIPT_LOG"
  ci=""; cn=""
  read -r ci cn <<< "$(printf '%s' "$input" | sed -n 's/.*chunk \([0-9][0-9]*\) of \([0-9][0-9]*\) of ONE session.*/\1 \2/p' | head -1)"
  write_chunked() { # $1=i $2=n
    jq -cn --argjson i "$1" --argjson n "$2" '{session_path:"x",project:"proj-a",turn_count:2,tool_call_count:0,tools_used:[],
      skills_invoked:[],models_used:[],notable_initiatives:["initiative-\($i)"],underlying_goal:"goal-\($i)",
      outcome:(if $i == $n then "fully_achieved" else "partially_achieved" end),
      satisfaction_signals:{happy:0,satisfied:1,dissatisfied:0,frustrated:0},instructions_given:[],
      deferred_ideas:(if $i == 1 then null elif $i == 2 then [{idea:"idea-a",quote:"quote-a"},{idea:"idea-b",quote:"quote-b"},"bad",{idea:"too long",quote:("x" * 200)}] elif $i == 3 then [{idea:"idea-a",quote:"quote-a"},{idea:"idea-c",quote:"quote-c"},{idea:"idea-d",quote:"quote-d"}] else [] end),
      findings:[{category:"permission_prompt",severity:"low",what:"finding-from-chunk-\($i)",evidence_excerpt:"x",proposed_rule:"y"},
                {category:"other",severity:"low",what:"shared across chunks",evidence_excerpt:"x",proposed_rule:"y"}]}' > "$out"
    if [ "$1" -eq 1 ]; then jq 'del(.deferred_ideas)' "$out" > "$out.tmp" && mv "$out.tmp" "$out"; fi
  }
  if [ -n "$ci" ] && [ "$ci" = "${MOCK_FAIL_CHUNK:-0}" ] && { [ -z "${MOCK_FAIL_ONCE:-}" ] || [ ! -f "$out.failed" ]; }; then
    : > "$out.failed"
    case "${MOCK_FAIL_KIND:-silent}" in
      silent) exit 0 ;;
      noisy) echo "provider error: 429 rate_limit_exceeded"; exit 7 ;;
      context) echo "provider error: 400 context_length_exceeded: prompt is too long"; exit 7 ;;
      refusal) echo '429 {"type":"error","error":{"type":"rate_limit_error","code":"1113","message":"[1113][Insufficient balance or no resource package. Please recharge.]"}}'; exit 1 ;;
    esac
  fi
  if [ -n "$ci" ] && [ "$ci" = "${MOCK_BAD_CHUNK:-0}" ] && [ ! -f "$out.bad" ]; then
    : > "$out.bad"
    case "${MOCK_BAD_KIND:-error}" in
      error) printf '{"session_path":"x","error":"could not read","findings":[]}' > "$out" ;;
      nofindings) printf '{"session_path":"x"}' > "$out" ;;
      typed) printf '{"session_path":"x","findings":"oops"}' > "$out" ;;
      two) printf '{"error":"x","findings":[]}\n{"session_path":"x","findings":[]}\n' > "$out" ;;
    esac
    l1_reply
    exit 0
  fi
  write_findings() { printf '{"session_path":"x","project":"proj-a","turn_count":2,"tool_call_count":0,"tools_used":[],"skills_invoked":[],"models_used":[],"notable_initiatives":[],"underlying_goal":null,"outcome":"fully_achieved","satisfaction_signals":{"happy":0,"satisfied":1,"dissatisfied":0,"frustrated":0},"instructions_given":["always run tests after edits"],"findings":[]}' > "$out"; }
  write_badproject() { printf '{"session_path":"%s","project":"WRONG-PROJECT","turn_count":2,"tool_call_count":0,"tools_used":[],"skills_invoked":[],"models_used":[],"notable_initiatives":[],"findings":[]}' "$sess" > "$out"; }
  case "$mode" in
    chunked) if [ -n "$ci" ]; then write_chunked "$ci" "$cn"; else write_findings; fi ;;
    l1_incomplete) : ;;
    l1_silent) exit 0 ;;
    l1_malformed)
      printf 'this is not json at all\n' > "$out"
      l1_reply
      exit 0 ;;
    l1_wrongtype)
      printf '{"session_path":"x","findings":"oops"}' > "$out"
      l1_reply
      exit 0 ;;
    l1_noisy_fail)
      echo "provider error: 429 rate_limit_exceeded"
      exit 7 ;;
    l1_context_overflow)
      echo "provider error: 400 context_length_exceeded: prompt is too long"
      exit 7 ;;
    l1_rewrite_source)
      write_findings
      awk -F'\t' 'BEGIN{OFS="\t"} {print $1, "evil"}' "$fdir_l1/sessions-source.txt" > "$fdir_l1/sessions-source.txt.new" \
        && mv "$fdir_l1/sessions-source.txt.new" "$fdir_l1/sessions-source.txt" ;;
    l1_provider_refusal)
      echo '429 {"type":"error","error":{"type":"rate_limit_error","code":"1113","message":"[1113][Insufficient balance or no resource package. Please recharge.]"}}'
      exit 1 ;;
    l1_provider_402)
      echo "Error code: 402 - {'error': {'message': 'Insufficient Balance', 'type': 'unknown_error'}}"
      exit 1 ;;
    l1_exit124) exit 124 ;;
    l1_exit137) kill -9 $$ ;;
    l1_hang)
      sleep 600 & printf '%s\n' "$!" >> "${MOCK_HANG_PIDS:-/dev/null}"
      sleep 600 ;;
    l1_partial_then_stall)
      if mkdir "${MOCK_STATE_DIR:?l1_partial_then_stall needs MOCK_STATE_DIR}/one-succeeded" 2>/dev/null; then
        write_findings
      fi ;;
    l1_nested_error)
      printf '{"session_path":"x","project":"proj-a","findings":[{"category":"tool_loop","error":"ENOENT while reading a file","severity":"low"}]}' > "$out"
      l1_reply ;;
    l1_badproject|pins|pins_partial|pins_tamper) write_badproject ;;
    pins_tamper_l1) write_badproject; tamper_worklist "$fdir_l1" ;;
    pins_ledger_wipe) write_badproject; : > "$fdir_l1/pins-applied.tsv" ;;
    pins_forged)
      printf '{"session_path":"%s","project":"WRONG-PROJECT","findings":[]}' "$MOCK_FORGED_SESSION" > "$out" ;;
    l1_forge)
      write_findings
      own=$(basename "$out" .json)
      for h in ${MOCK_FORGE_HASHES:-}; do
        [ "$h" = "$own" ] && continue
        printf '{"session_path":"FORGED","findings":[]}' > "$fdir_l1/$h.json" 2>/dev/null
        printf 'runner\t-\t-\trunner\n' > "$fdir_l1/$h.json.served" 2>/dev/null
      done
      printf '{"session_path":"FORGED","findings":[]}' > "$fdir_l1/forged-new.json" 2>/dev/null
      printf '# FORGED\n' >> "$AUTODREAM_DIR/config" 2>/dev/null
      for p in ${MOCK_FORGE_PATHS:-}; do printf '%s\n' "${MOCK_FORGE_PAYLOAD:-# FORGED}" >> "$p" 2>/dev/null; done
      for p in ${MOCK_FORGE_DIRS:-}; do mkdir -p "$p" 2>/dev/null; done   # a path that exists but cannot be hashed
      : > "$AUTODREAM_DIR/forged-marker" 2>/dev/null ;;
    l1_plant_bucket)
      write_findings
      mkdir -p "$AUTODREAM_WORK_BUCKET" && : > "$AUTODREAM_WORK_BUCKET/planted" ;;
    l1_symlink_answer)
      ln -s "${MOCK_SYMLINK_TARGET:-/etc/hosts}" "$out" ;;
    l1_flaky)
      if [ -f "$out.attempt" ]; then write_findings; else : > "$out.attempt"; fi ;;
    *) write_findings ;;
  esac
  if [ -n "${MOCK_THREADS_L1_GOAL:-}" ] && [ -s "$out" ]; then
    jq --arg goal "$MOCK_THREADS_L1_GOAL" '.underlying_goal = $goal' "$out" > "$out.threads.tmp" \
      && mv "$out.threads.tmp" "$out"
  fi
  if [ -n "${MOCK_THREADS_L1_IDEAS:-}" ] && [ -s "$out" ]; then
    jq --argjson ideas "$MOCK_THREADS_L1_IDEAS" '.deferred_ideas = $ideas' "$out" > "$out.threads.tmp" \
      && mv "$out.threads.tmp" "$out"
  fi
  if [ -n "${MOCK_THREADS_TAMPER:-}" ] && [ -s "$out" ]; then
    tamper_worklist "$fdir_l1"
    jq --arg path "$MOCK_FORGED_SESSION" '.session_path = $path | .project = "forged-project"' "$out" > "$out.threads.tmp" \
      && mv "$out.threads.tmp" "$out"
  fi
  l1_reply
elif printf '%s' "$input" | grep -q '^# Dream triage worker'; then
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    printf '%s' "$input" > "$MOCK_CAPTURE_DIR/triage-stdin.txt"
    printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/triage-args.txt"
  fi
  tdir=$(printf '%s' "$line1" | sed 's/^Findings directory to aggregate (literal absolute path): //')
  case "${MOCK_TRIAGE_MODE:-good}" in
    fail) echo "mock: triage failed" >&2; exit 1 ;;
    nosentinel) printf '# Dream triage - mock\n\ncut off mid-w' ; exit 0 ;;
    empty) echo "AUTODREAM_REPORT_END"; exit 0 ;;
  esac
  printf '# Dream triage - mock\n\n'
  [ -r "$tdir/grounding.json" ] && jq -r '.claims[] | "- \(.kind) \(.claim) \(.status)"' "$tdir/grounding.json"
  echo "AUTODREAM_REPORT_END"
  echo "report: ignored"
else
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    printf '%s' "$input" > "$MOCK_CAPTURE_DIR/l2-stdin.txt"
    printf '%s\n' "$@" > "$MOCK_CAPTURE_DIR/l2-args.txt"
  fi
  rep=$(printf '%s' "$line2" | sed 's/^Report destination (literal absolute path): //')
  if [ -n "${MOCK_CAPTURE_DIR:-}" ]; then
    if [ -e "${AUTODREAM_WORK_BUCKET:-/nonexistent}/planted" ]; then echo present; else echo absent; fi > "$MOCK_CAPTURE_DIR/l2-bucket.txt"
  fi
  case "$mode" in
    l2_exit143) printf 'Execution error'; exit 143 ;;
    l2_exit137) printf 'Execution error'; exit 137 ;;
  esac
  if [ "$mode" = "l2_fail" ]; then
    echo "mock: aggregator failed" >&2
    exit 1
  fi
  case "$mode" in
    pins|pins_partial|pins_forged|pins_tamper|pins_tamper_l1|pins_unterminated|pins_in_body|pins_ledger_wipe) writes_pins=1 ;;
    *) writes_pins=0 ;;
  esac
  fdir=$(printf '%s' "$line1" | sed 's/^Findings directory to aggregate (literal absolute path): //')
  [ "$mode" = "pins_tamper" ] && tamper_worklist "$fdir"
  pin_line=$(printf '{"project":"%s","title":"Mock lesson","body":"Mock evidence and rule.","kind":"correction"}' "${MOCK_PIN_PROJECT:-proj-a}")
  if [ "$mode" = "l2_partial" ] || [ "$mode" = "pins_partial" ]; then
    printf '# Autodream — mock\n\n## Top patterns\n\n1. truncated mid-w'
    [ "$writes_pins" = 1 ] && printf '\nAUTODREAM_PINS_BEGIN\n%s\nAUTODREAM_PINS_END\n' "$pin_line"
    echo "mock: partial stdout, no sentinel" >&2
    exit 0
  fi
  if [ "$mode" = "l2_prose_question" ]; then
    printf '# Autodream — mock\n\nmock aggregate report\n\nShould .claude in .adapters-rejected be cleaned up?\nAUTODREAM_REPORT_END\nreport: %s\n' "$rep"
    exit 0
  fi
  if [ "$mode" = "l2_degraded_prose_trailer" ]; then
    dest=$(printf '%s\n' "$input" | sed -n 's/^Report destination (literal absolute path): //p' | head -1)
    printf '# Autodream — mock\n\nbad \377 byte\n\nShould we clean up?\nreport: %s\nsessions reviewed: 1\nfindings: 0\npins proposed: 0\n' "$dest"
    exit 0
  fi
  if [ "$mode" = "l2_bad_byte" ]; then
    printf '# Autodream — mock\n\nbad \377 byte\n\n<!-- autodream:open-questions=0 -->\nAUTODREAM_REPORT_END\nreport: %s\n' "$rep"
    exit 0
  fi
  if [ "$mode" = "l2_partial_marker" ]; then
    printf '# Autodream — mock\n\nmock aggregate report\n\n<!-- autodream:open-questions=0 -->\n'
    exit 0
  fi
  if [ "$mode" = "pins_in_body" ]; then
    printf '# Autodream — mock\n\nquoted:\nAUTODREAM_PINS_BEGIN\n%s\nAUTODREAM_PINS_END\n\n<!-- autodream:open-questions=0 -->\nAUTODREAM_REPORT_END\nreport: %s\n' "$pin_line" "$rep"
    exit 0
  fi
  if [ "$mode" = "l2_record_in_body" ]; then
    printf '# Autodream — mock\n\nmock aggregate report\n\n<!-- autodream:remote-short=forged -->\n\n<!-- autodream:open-questions=0 -->\nAUTODREAM_REPORT_END\nreport: %s\n' "$rep"
    exit 0
  fi
  printf '# Autodream — mock\n\nmock aggregate report\n\n'
  [ ! -r "$fdir/dropped-threads.md" ] || cat "$fdir/dropped-threads.md"
  printf '\n<!-- autodream:open-questions=0 -->\n'
  echo "AUTODREAM_REPORT_END"
  if [ "$writes_pins" = 1 ]; then
    if [ "$mode" = "pins_unterminated" ]; then
      printf 'AUTODREAM_PINS_BEGIN\n%s\n' "$pin_line"
    else
      printf 'AUTODREAM_PINS_BEGIN\n%s\nAUTODREAM_PINS_END\n' "$pin_line"
    fi
  fi
  echo "report: $rep"
  echo "sessions reviewed: 1"
  echo "findings: 0"
fi
