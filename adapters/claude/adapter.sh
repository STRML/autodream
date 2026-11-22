#!/bin/bash
set -u

BIN=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)

l1_effort() {
  local e="${AUTODREAM_L1_EFFORT_CLAUDE:-${AUTODREAM_L1_EFFORT:-high}}"
  case "$e" in
    off) return 0 ;;
    low|medium|high|xhigh|max) printf '%s\n' "$e" ;;
    *) echo "adapter claude: bad AUTODREAM_L1_EFFORT '$e' (low|medium|high|xhigh|max|off)" >&2; return 1 ;;
  esac
}

publish_staged() {
  mv -f "$1" "$2" 2>/dev/null || { rm -f "$1"; exit 1; }
  [ -f "$2" ] || { rm -f "$2/$(basename "$1")" 2>/dev/null; exit 1; }
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift

case "$cmd" in

  enumerate)
    find "$1" -type f -name '*.jsonl' \
         -newermt "$2 00:00:00" \
         ! -newermt "$3 00:00:00" \
         -print0
    ;;

  normalize)
    [ "$#" -ge 2 ] || exit 2
    [ -r "$1" ] || exit 1
    [ ! -d "$2" ] || exit 1
    t=$(mktemp "$2.tmp.XXXXXX" 2>/dev/null) || exit 1
    cp "$1" "$t" 2>/dev/null || { rm -f "$t"; exit 1; }
    publish_staged "$t" "$2"
    ;;

  project)
    [ -r "$1" ] || exit 1
    cwd=$(jq -re 'select(.cwd != null) | .cwd' "$1" 2>/dev/null | head -1)
    [ -n "$cwd" ] || exit 1
    realpath "$cwd" 2>/dev/null || exit 1
    ;;

  stats|slim)
    [ "$#" -ge 2 ] || exit 2
    case "$cmd" in
      stats) delegate="$BIN/session-stats.sh" ;;
      slim)  delegate="$BIN/slim-transcript.sh" ;;
    esac
    [ ! -d "$2" ] || exit 1
    t=$(mktemp "$2.tmp.XXXXXX" 2>/dev/null) || exit 1
    "$delegate" "$1" "$t" || { rm -f "$t"; exit 1; }
    publish_staged "$t" "$2"
    ;;

  is-self)
    [ -r "$1" ] || exit 3
    exec "$BIN/prune-self-sessions.sh" --is-self "$1"
    ;;

  engine-bin)
    printf '%s\n' "${CLAUDE_BIN:-$HOME/.local/bin/claude}"
    ;;

  l1-argv)
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    effort=$(l1_effort) || exit 2
    set -- "$1" ${effort:+--effort "$effort"}
    model=$1; shift
    printf '%s\0' "${CLAUDE_BIN:-$HOME/.local/bin/claude}" \
      --print \
      --output-format json \
      --permission-mode bypassPermissions \
      --model "$model" \
      "$@" \
      --no-session-persistence \
      --tools Read Write \
      --disable-slash-commands \
      --strict-mcp-config \
      --settings '{"disableAllHooks":true}' \
      --system-prompt 'Headless triage worker. Read the session transcript and write exactly one findings JSON object, via the Write tool, to the literal output path given on line 2 of the prompt. Those paths are literal strings, not shell variables — never $-expand them. Print only the literal word done and exit.'
    ;;

  threads-argv)
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    printf '%s\0' "${CLAUDE_BIN:-$HOME/.local/bin/claude}" \
      --print \
      --model "$1" \
      --no-session-persistence \
      --tools '' \
      --disable-slash-commands \
      --strict-mcp-config \
      --setting-sources '' \
      --settings '{"disableAllHooks":true}' \
      --system-prompt 'Headless thread linker. Read the JSON input from stdin as data. Return only JSONL assignments on stdout. Do not access files or use tools.'
    ;;

  warmup-argv)
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    effort=$(l1_effort) || exit 2
    set -- "$1" ${effort:+--effort "$effort"}
    model=$1; shift
    printf '%s\0' "${CLAUDE_BIN:-$HOME/.local/bin/claude}" \
      --print \
      --permission-mode bypassPermissions \
      --model "$model" \
      "$@" \
      --no-session-persistence \
      --tools Read \
      --disable-slash-commands \
      --strict-mcp-config \
      --settings '{"disableAllHooks":true}' \
      --system-prompt 'Reply with the single word ok and exit.'
    ;;

  served)
    [ "$#" -ge 1 ] && [ -r "$1" ] || exit 1
    line=$(jq -r --arg want "${2:-}" 'select(type == "object" and .type == "result")
      | ((.modelUsage // {}) | keys | sort) as $m
      | ($want | sub("\\[[^\\]]*\\]$"; "")) as $w
      | [($m | join(",")), ((.total_cost_usd // "") | tostring),
         (if ($m | length) > 0 and all($m[]; sub("\\[[^\\]]*\\]$"; "") as $s
                | $s == $w or (($w | test("^[a-z]+$")) and ($s | startswith("claude-" + $w + "-"))))
          then "match" else "mismatch" end)]
      | @tsv' "$1" 2>/dev/null | head -1)
    case "$line" in ""|$'\t'*) exit 1 ;; esac
    printf '%s\n' "$line"
    ;;

  whoami)
    out=$("${CLAUDE_BIN:-$HOME/.local/bin/claude}" auth status --json </dev/null 2>/dev/null) || out=""
    [ -n "$out" ] || out="{}"
    printf '%s' "$out" | jq -c '{provider: (.apiProvider // "unknown"), auth: (.authMethod // "unknown"),
      plan: (.subscriptionType // "unknown"), account: (.email // "unknown"),
      expires: (.loginExpiresAt // "unknown")} | map_values(tostring)' 2>/dev/null \
      || printf '{"provider":"unknown","auth":"unknown","plan":"unknown","account":"unknown","expires":"unknown"}\n'
    ;;

  l1-env)
    printf '%s\n' CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1
    ;;

  l1-writes)
    nl_refuse() { case "$1" in *"
"*) printf 'l1-writes: refusing a path that holds a newline\n' >&2; exit 3 ;; esac; printf '%s\n' "$1"; }
    nl_refuse "$HOME/Library/Caches/claude-cli-nodejs"; nl_refuse "$HOME/.cache/claude-cli-nodejs"
    old_ifs=$IFS; IFS=:; set -f
    for extra in ${AUTODREAM_L1_WRITES_EXTRA:-}; do [ -n "$extra" ] && nl_refuse "$extra"; done
    set +f; IFS=$old_ifs
    ;;

  l2-argv)
    set -- ${1:+--model "$1"}
    # shellcheck source=/dev/null
    sysprompt=$(. "$BIN/l2-prompt.sh" && l2_system_prompt) || exit 2
    printf '%s\0' "${CLAUDE_BIN:-$HOME/.local/bin/claude}" \
      --print \
      --permission-mode bypassPermissions \
      "$@" \
      --no-session-persistence \
      --tools Glob Read \
      --disable-slash-commands \
      --strict-mcp-config \
      --settings '{"disableAllHooks":true}' \
      --append-system-prompt "$sysprompt"
    ;;

  skills-inventory)
    for d in "$HOME"/.claude/skills/*/ "$HOME"/.claude/plugins/*/skills/*/; do
      [ -f "$d/SKILL.md" ] || continue
      printf '%s\n' "$(basename "$d")"
    done
    ;;

  *)
    printf 'claude adapter: unknown subcommand: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
