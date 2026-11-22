#!/bin/bash
set -u

usage() {
  cat <<'EOF'
usage: slim-transcript.sh <src.jsonl> <dst>

Slims an oversized session transcript so the L1 worker can read it: strips bulky tool
payloads, cuts every line to a max width, keeps head and tail and elides the middle, and
hard-caps the total bytes. run.sh calls it only for sessions over AUTODREAM_SLIM_BYTES.

Tunables (env): AUTODREAM_SLIM_MAXLINE (400 chars), _HEAD (400 lines), _TAIL (200 lines),
                _CAP (262144 bytes), _TOOLRESULT (600 chars), _THINKING (800 chars).
Modes (env, both off unless set to 1):
  AUTODREAM_SLIM_RESHAPE=1  drop Claude Code bookkeeping records by a type denylist and rebuild
                            each kept Claude record with type and timestamp first and the
                            message reduced to role and content. OMP records and unknown
                            schemas pass through untouched by this step.
  AUTODREAM_SLIM_FULL=1     keep every surviving line: no head/tail elision, no byte cap, no
                            footer. For the chunker, which sizes the pieces itself.
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

umask 077

src="${1:?usage: slim-transcript.sh <src> <dst>}"
dst="${2:?usage: slim-transcript.sh <src> <dst>}"
maxline="${AUTODREAM_SLIM_MAXLINE:-400}"
headn="${AUTODREAM_SLIM_HEAD:-400}"
tailn="${AUTODREAM_SLIM_TAIL:-200}"
cap="${AUTODREAM_SLIM_CAP:-262144}"
trmax="${AUTODREAM_SLIM_TOOLRESULT:-600}"
tkmax="${AUTODREAM_SLIM_THINKING:-800}"
reshape="${AUTODREAM_SLIM_RESHAPE:-0}"
full="${AUTODREAM_SLIM_FULL:-0}"

[ -r "$src" ] || { echo "slim-transcript: cannot read $src" >&2; exit 1; }

rm -f "$dst.pre.jsonl"
if ! { : > "$dst" && chmod 600 "$dst"; }; then
  echo "slim-transcript: cannot write $dst" >&2
  exit 1
fi

lines=$(wc -l < "$src" | tr -d ' ')
bytes=$(wc -c < "$src" | tr -d ' ')

reshape_defs=""
reshape_pipe=""
if [ "$reshape" = "1" ]; then
  reshape_defs='
    def noise_attachment: (.attachment.type | IN("hook_success", "total_tokens_reminder",
        "deferred_tools_record", "deferred_tools_delta", "silent_turn_reminder",
        "prompt_snapshot", "environment", "date", "model", "instructions", "session_context",
        "credential_org", "advisor_tool", "sandbox_instructions", "mcp_instructions_delta",
        "agent_listing_delta", "remote_session_change", "command_permissions"));
    def noise:
      (.type | IN("bridge-session", "last-prompt", "permission-mode", "mode", "atis-latch",
                  "ai-title", "queue-operation", "file-history-snapshot",
                  "file-history-delta", "dev-mods"))
      or (.type == "attachment" and noise_attachment)
      or (.type == "system" and (.subtype | IN("stop_hook_summary", "turn_duration")));
    def claude_type: .type | IN("user", "assistant", "attachment", "system");
    def reshape:
      if claude_type then
        ({type: .type}
         + (if has("timestamp") then {timestamp: .timestamp} else {} end)
         + with_entries(select(.key | IN("isSidechain", "isMeta", "isCompactSummary",
                                         "subtype", "level", "content", "message", "attachment"))))
        | (if (.message | type) == "object"
             then .message |= with_entries(select(.key | IN("role", "content")))
             else . end)
        | (if (.message | type) == "object" and (.message.content | type) == "array"
             then .message.content |= map(if type == "object" and .type == "thinking" then del(.signature) else . end)
             else . end)
      else . end;
  '
  reshape_pipe='select(noise | not) | reshape |'
fi
pre_src="$src"
pre_tmp=""
if command -v jq >/dev/null 2>&1; then
  pre_tmp="$dst.pre.jsonl"
  if jq -c --argjson tr "$trmax" --argjson tk "$tkmax" "$reshape_defs"'
    def payload: . != null and (type != "object" or length > 0);

    def trunc($n):
      if . == null then null
      elif type == "string" then
        (if length > $n then .[0:$n] + "…[autodream: truncated]" else . end)
      else
        (tostring as $s
         | if ($s | length) > $n then $s[0:$n] + "…[autodream: truncated]" else . end)
      end;

    def trunc_at($k; $n): if has($k) then .[$k] |= trunc($n) else . end;
    def strip($k; $marker): if (.[$k] | payload) then .[$k] = $marker else . end;
    '"$reshape_pipe"'
    if (.message | type) == "object" then
      .message |= (
        del(.providerPayload)
        | (if .role == "toolResult" then
             strip("details"; "[autodream: details stripped]") | trunc_at("content"; $tr)
           else . end)
        | (if (.content | type) == "array" then
             .content |= map(
               if .type == "tool_result" then
                 strip("content"; "[autodream: tool_result payload stripped]")
               elif .type == "thinking" then
                 trunc_at("thinking"; $tk)
               elif .type == "toolCall" then
                 del(.partialArgs) | trunc_at("arguments"; $tr)
               elif .type == "image" then
                 strip("source"; "[autodream: image stripped]")
                 | (if (.data | payload) then
                      .data = (if (.data | type) == "string" and (.data | startswith("data:"))
                                 then "[autodream: image stripped]"
                                 else (.data | trunc($tr)) end)
                    else . end)
               elif .type == "image_url" then
                 strip("image_url"; "[autodream: image stripped]")
               else . end)
           else . end)
      )
    else . end
  ' "$src" > "$pre_tmp" 2>/dev/null && [ -s "$pre_tmp" ]; then
    pre_src="$pre_tmp"
    lines=$(wc -l < "$pre_src" | tr -d ' ')
  else
    rm -f "$pre_tmp"; pre_tmp=""
  fi
fi

{
  if [ "$full" = "1" ] || [ "$lines" -le $((headn + tailn)) ]; then
    cut -c1-"$maxline" "$pre_src"
  else
    head -n "$headn" "$pre_src" | cut -c1-"$maxline"
    printf '...[%d of %d lines elided by autodream for size]...\n' $((lines - headn - tailn)) "$lines"
    tail -n "$tailn" "$pre_src" | cut -c1-"$maxline"
  fi
} | { if [ "$full" = "1" ]; then cat; else head -c "$cap"; fi; } > "$dst"

[ -n "$pre_tmp" ] && rm -f "$pre_tmp"

[ "$full" = "1" ] || printf '\n...[autodream slimmed this transcript: original %s bytes / %s lines; lines truncated to %s chars]...\n' \
  "$bytes" "$lines" "$maxline" >> "$dst"
