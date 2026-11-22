#!/bin/bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
A="$REPO/adapters/claude/adapter.sh"

pass=0; fail=0
# shellcheck source=/dev/null
. "$HERE/lib-assert.sh"

[ -x "$A" ] || { printf '  FAIL - adapters/claude/adapter.sh missing or not executable\n'
                 printf '\npassed: 0   failed: 1\n'; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/adclaude.XXXXXX")

reap_delegate() {
  [ -n "${slim_pgid:-}" ] || return 0
  kill -TERM -"$slim_pgid" 2>/dev/null
  kill -KILL -"$slim_pgid" 2>/dev/null
  return 0
}

cleanup() {
  reap_delegate
  [ -n "${tmp:-}" ] && [ -d "${tmp:-}" ] && rm -rf "$tmp"
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

ps_usable() {
  [ -n "$(ps -o state= -p $$ 2>/dev/null | tr -d ' ')" ]
}

echo "# claude adapter: the ps probe notices a ps that cannot run"
psstub="$tmp/psstub"; mkdir -p "$psstub"
printf '#!/bin/sh\necho "ps: Operation not permitted" >&2\nexit 1\n' > "$psstub/ps"
chmod +x "$psstub/ps"
if PATH="$psstub:$PATH" ps_usable; then
  no "ps_usable reported a ps that fails to execute as usable"
else
  ok "ps_usable rejects a ps that fails to execute"
fi

proj="$tmp/proj a"          # a space, because NUL transport is supposed to allow it
mkdir -p "$proj"
projreal=$(cd "$proj" && pwd -P)

mkdir -p "$tmp/root/projects/-bucket"
S="$tmp/root/projects/-bucket/s1.jsonl"
printf '%s\n' \
  "{\"type\":\"user\",\"cwd\":\"$projreal\",\"message\":{\"content\":\"hello\"}}" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}' > "$S"

echo "# claude adapter: project returns the resolved cwd, not the bucket name"
assert_eq "$("$A" project "$S")" "$projreal" "resolved cwd from the transcript"
if "$A" project "$tmp/root/projects/-bucket/nope.jsonl" >/dev/null 2>&1; then
  no "a missing session exits nonzero"
else ok "a missing session exits nonzero"; fi

echo "# claude adapter: normalize is a verbatim copy for this harness"
out="$tmp/norm.jsonl"
if "$A" normalize "$S" "$out"; then ok "normalize exits 0"; else no "normalize exits 0"; fi
if cmp -s "$S" "$out"; then ok "normalize copied the file verbatim"; else no "normalize copied the file verbatim"; fi
set -- "$out".tmp*
if [ -e "$1" ]; then no "no temp left behind (found $(basename "$1"))"; else ok "no temp left behind"; fi

echo "# claude adapter: a failed normalize leaves no partial output"
if "$A" normalize "$tmp/missing.jsonl" "$tmp/partial.jsonl" 2>/dev/null; then
  no "missing input exits nonzero"
else ok "missing input exits nonzero"; fi
if [ -e "$tmp/partial.jsonl" ]; then no "no partial output on failure"; else ok "no partial output on failure"; fi

echo "# claude adapter: stats writes a sidecar with numeric transcript_bytes"
if "$A" stats "$S" "$tmp/s1.stats.json" 2>/dev/null; then ok "stats exits 0"; else no "stats exits 0"; fi
if jq -e '.transcript_bytes | numbers' "$tmp/s1.stats.json" >/dev/null 2>&1; then
  ok "the sidecar has a numeric transcript_bytes"
else no "the sidecar has a numeric transcript_bytes"; fi
set -- "$tmp"/s1.stats.json.tmp*
if [ -e "$1" ]; then no "stats left no temp (found $(basename "$1"))"; else ok "stats left no temp"; fi

echo "# claude adapter: slim writes a reduced copy"
if "$A" slim "$S" "$tmp/slim.jsonl" 2>/dev/null; then ok "slim exits 0"; else no "slim exits 0"; fi
if [ -s "$tmp/slim.jsonl" ]; then ok "slim wrote output"; else no "slim wrote output"; fi

echo "# claude adapter: a signalled slim dies promptly and writes no destination"
fifodir="$tmp/fifo"; mkdir -p "$fifodir"
mkfifo "$fifodir/src.jsonl" 2>/dev/null
if [ -p "$fifodir/src.jsonl" ]; then
  set -m
  "$A" slim "$fifodir/src.jsonl" "$fifodir/out.jsonl" >/dev/null 2>&1 &
  slim_pid=$!
  set +m
  slim_pgid=$slim_pid
  waited=0; saw_tmp=0
  while [ "$waited" -lt 100 ]; do
    set -- "$fifodir"/out.jsonl.tmp*
    if [ -e "$1" ]; then saw_tmp=1; break; fi
    sleep 0.05
    waited=$((waited + 1))
  done
  if [ "$saw_tmp" = "1" ]; then ok "the temp was observed before signalling"
  else no "the temp never appeared, so the interrupt assertions prove nothing"; fi
  kill -TERM "$slim_pid" 2>/dev/null
  died=0; waited=0; psok=0
  if ps_usable; then
    psok=1
    while [ "$waited" -lt 60 ]; do
      st=$(ps -o state= -p "$slim_pid" 2>/dev/null | tr -d ' ')
      case "$st" in ""|Z*) died=1; break ;; esac
      sleep 0.05
      waited=$((waited + 1))
    done
  fi
  if [ "$psok" = "0" ]; then
    no "ps is unavailable, so the SIGTERM assertion cannot be evaluated"
    kill -9 "$slim_pid" 2>/dev/null
  elif [ "$died" = "1" ]; then
    ok "a signalled slim terminates instead of ignoring SIGTERM"
  else
    no "a signalled slim did not terminate within 3s"
    kill -9 "$slim_pid" 2>/dev/null
  fi
  wait "$slim_pid" 2>/dev/null
  reap_delegate
  if [ -e "$fifodir/out.jsonl" ]; then
    no "a signalled slim wrote no destination file"
  else
    ok "a signalled slim wrote no destination file"
  fi
else
  ok "mkfifo unavailable here; skipped the interrupt test"
fi

echo "# claude adapter: is-self defers to the one self-pollution predicate"
W="$tmp/root/projects/-bucket/worker.jsonl"
printf '%s\n' '{"type":"user","message":{"content":"Session transcript to analyze (literal absolute path): /x"}}' > "$W"
if "$A" is-self "$W"; then ok "an autodream worker transcript is ours"; else no "an autodream worker transcript is ours"; fi
if "$A" is-self "$S"; then no "a real session is not ours"; else ok "a real session is not ours"; fi

echo "# claude adapter: an unknown subcommand exits 2, never 0"
"$A" not-a-subcommand >/dev/null 2>&1; assert_eq "$?" "2" "unknown subcommand exits 2"

echo "# l2-argv: Glob and Read only, and no model unless one is named"
L2=$(CLAUDE_BIN=/opt/test/claude "$A" l2-argv | tr '\0' '\n')
assert_eq "$(printf '%s\n' "$L2" | sed -n '1p')" "/opt/test/claude" "the engine binary comes first"
assert_eq "$(printf '%s\n' "$L2" | sed -n '/^--tools$/{n;p;n;p;}' | tr '\n' ' ')" "Glob Read " "L2 holds Glob and Read"
case "$L2" in *--model*) no "no --model without a model" ;; *) ok "no --model without a model" ;; esac
assert_eq "$(CLAUDE_BIN=/opt/test/claude "$A" l2-argv opus | tr '\0' '\n' | sed -n '/^--model$/{n;p;}')" "opus" "a named model is passed through"
case "$L2" in *AUTODREAM_REPORT_END*AUTODREAM_PINS_BEGIN*) ok "the system prompt carries the sentinel grammar" ;; *) no "the system prompt carries the sentinel grammar" ;; esac

echo "# l1-argv reproduces the invocation run.sh hard-coded before the engine moved behind the adapter"
OLD_SYSPROMPT="Headless triage worker. Read the session transcript and write exactly one findings JSON object, via the Write tool, to the literal output path given on line 2 of the prompt. Those paths are literal strings, not shell variables — never \$-expand them. Print only the literal word done and exit."
OLD_SETTINGS="{\"disableAllHooks\":true}"
printf '%s\0' /opt/test/claude --print --output-format json --permission-mode bypassPermissions --model claude-haiku-5-5 --effort high \
  --no-session-persistence --tools Read Write --disable-slash-commands --strict-mcp-config \
  --settings "$OLD_SETTINGS" --system-prompt "$OLD_SYSPROMPT" > "$tmp/old-argv"
CLAUDE_BIN=/opt/test/claude "$A" l1-argv claude-haiku-5-5 > "$tmp/new-argv"
if cmp -s "$tmp/old-argv" "$tmp/new-argv"; then ok "the claude L1 argv is the old hard-coded one with --output-format json, --effort high and --system-prompt"
else no "the claude L1 argv is the old hard-coded one with --output-format json, --effort high and --system-prompt"; fi
echo "# l1 effort: env override, off, and an invalid level"
assert_eq "$(AUTODREAM_L1_EFFORT=low CLAUDE_BIN=/opt/test/claude "$A" l1-argv m | tr '\0' '\n' | sed -n '/^--effort$/{n;p;}')" "low" "AUTODREAM_L1_EFFORT sets the level"
assert_eq "$(AUTODREAM_L1_EFFORT=low AUTODREAM_L1_EFFORT_CLAUDE=max CLAUDE_BIN=/opt/test/claude "$A" l1-argv m | tr '\0' '\n' | sed -n '/^--effort$/{n;p;}')" "max" "the per-adapter variable wins"
assert_eq "$(AUTODREAM_L1_EFFORT=off CLAUDE_BIN=/opt/test/claude "$A" l1-argv m | tr '\0' '\n' | grep -c '^--effort$')" "0" "off omits the flag"
if AUTODREAM_L1_EFFORT=turbo CLAUDE_BIN=/opt/test/claude "$A" l1-argv m >/dev/null 2>&1; then no "an unknown level is refused"; else ok "an unknown level is refused"; fi

echo "# threads-argv: linker has no tools or ambient context"
threads_argv=()
threads_count=0
CLAUDE_BIN=/opt/test/claude "$A" threads-argv fixture-model > "$tmp/threads-argv" 2>/dev/null
rc=$?
while IFS= read -r -d '' arg; do threads_argv[$threads_count]="$arg"; threads_count=$((threads_count + 1)); done < "$tmp/threads-argv"
assert_eq "$rc" 0 "threads-argv exists"
requested_model=""
tool_count=-1
persists_session=true
no_sources=false
strict_mcp=false
slash_commands_off=false
hooks_off=false
i=0
while [ "$i" -lt "$threads_count" ]; do
  arg=${threads_argv[$i]}
  case "$arg" in
    --model) next=$((i + 1)); requested_model=${threads_argv[$next]} ;;
    --tools) next=$((i + 1)); [ -z "${threads_argv[$next]}" ] && tool_count=0 || tool_count=1 ;;
    --no-session-persistence) persists_session=false ;;
    --setting-sources) next=$((i + 1)); [ -z "${threads_argv[$next]}" ] && no_sources=true ;;
    --strict-mcp-config) strict_mcp=true ;;
    --disable-slash-commands) slash_commands_off=true ;;
    --settings) next=$((i + 1)); [ "${threads_argv[$next]}" = '{"disableAllHooks":true}' ] && hooks_off=true ;;
  esac
  i=$((i + 1))
done
assert_eq "$requested_model" "fixture-model" "model passed literally"
assert_eq "$tool_count" 0 "explicit empty tool list"
assert_eq "$persists_session" false "headless calls leave no session"
loads_context_or_extensions=true
if [ "$no_sources" = true ] && [ "$strict_mcp" = true ] && [ "$slash_commands_off" = true ] && [ "$hooks_off" = true ]; then
  loads_context_or_extensions=false
fi
assert_eq "$loads_context_or_extensions" false "no ambient tools"
"$A" threads-argv >/dev/null 2>&1; assert_eq "$?" 2 "threads-argv requires a model"

assert_eq "$(CLAUDE_BIN=/opt/test/claude "$A" engine-bin)" "/opt/test/claude" "engine-bin honors CLAUDE_BIN"
assert_eq "$(env -u CLAUDE_BIN HOME=/h "$A" engine-bin)" "/h/.local/bin/claude" "engine-bin defaults to the installer's location"
assert_eq "$("$A" l1-env | tr '\n' ' ')" "CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 " "l1-env is the lean-query environment"

echo "# warmup-argv: the worker's flags with a one-word system prompt"
WA=$(CLAUDE_BIN=/opt/test/claude "$A" warmup-argv claude-haiku-5-5 | tr '\0' '\n')
assert_eq "$(printf '%s\n' "$WA" | tail -1)" "Reply with the single word ok and exit." "the system prompt asks for one word"
LA=$(CLAUDE_BIN=/opt/test/claude "$A" l1-argv claude-haiku-5-5 | tr '\0' '\n')
assert_eq "$(printf '%s\n' "$WA" | sed -n '1,/^--tools$/p' | sed '$d')" "$(printf '%s\n' "$LA" | sed '/^--output-format$/{N;d;}' | sed -n '1,/^--tools$/p' | sed '$d')" "the flags before --tools match the worker's"

echo "# served: the models that answered one L1 call, from its result object"
printf '%s\n' '{"type":"result","is_error":false,"result":"done","modelUsage":{"claude-sonnet-5-5":{}},"total_cost_usd":0.25}' > "$tmp/r1"
assert_eq "$("$A" served "$tmp/r1" claude-sonnet-5-5)" "claude-sonnet-5-5	0.25	match" "one model, the cost estimate, and a match for the model asked for"
printf '%s\n' '{"type":"result","modelUsage":{"m-b":{},"m-a":{}},"total_cost_usd":1}' > "$tmp/r2"
assert_eq "$("$A" served "$tmp/r2" m-a)" "m-a,m-b	1	mismatch" "every model that answered, sorted, and a second model is a mismatch"
printf '%s\n' '{"type":"system","subtype":"init"}' '{"type":"result","modelUsage":{"m":{}}}' > "$tmp/r3"
assert_eq "$("$A" served "$tmp/r3" m)" "m		match" "a stream is read for its result line, and a missing cost is empty"
printf 'done\n' > "$tmp/r4"
"$A" served "$tmp/r4" >/dev/null 2>&1; assert_eq "$?" "1" "plain text carries no record"
printf '%s\n' '{"type":"result","is_error":true,"result":"Not logged in","modelUsage":{}}' > "$tmp/r5"
"$A" served "$tmp/r5" >/dev/null 2>&1; assert_eq "$?" "1" "a result no model answered carries no record"
"$A" served "$tmp/nonesuch" >/dev/null 2>&1; assert_eq "$?" "1" "a missing file carries no record"
echo "# served: the verdict reads the CLI's naming, so an alias matches the canonical id it answers as"
printf '%s\n' '{"type":"result","modelUsage":{"claude-haiku-5-5":{}},"total_cost_usd":0.01}' > "$tmp/r6"
assert_eq "$("$A" served "$tmp/r6" haiku | cut -f3)" "match" "the haiku alias matches claude-haiku-5-5"
assert_eq "$("$A" served "$tmp/r6" claude-haiku-5-5 | cut -f3)" "match" "the full id matches itself"
assert_eq "$("$A" served "$tmp/r6" sonnet | cut -f3)" "mismatch" "another family's alias does not"
assert_eq "$("$A" served "$tmp/r6" claude-haiku-5 | cut -f3)" "mismatch" "nor does a full id that is only a prefix"
assert_eq "$("$A" served "$tmp/r6" default | cut -f3)" "mismatch" "an alias the family rule cannot read is not vouched for"
assert_eq "$("$A" served "$tmp/r6" | cut -f3)" "mismatch" "and nor is a call with no requested model"
printf '%s\n' '{"type":"result","modelUsage":{"claude-opus-5-5[1m]":{}}}' > "$tmp/r7"
assert_eq "$("$A" served "$tmp/r7" 'opus[1m]' | cut -f3)" "match" "a context suffix is ignored on both sides"
assert_eq "$("$A" served "$tmp/r7" claude-opus-5-5 | cut -f3)" "match" "including on the answering side alone"

echo "# whoami: who the engine's calls run as, read from claude auth status"
printf '%s\n' '#!/bin/sh' '[ "$1 $2 $3" = "auth status --json" ] || exit 9' \
  "printf '%s\n' '{\"loggedIn\":true,\"authMethod\":\"claude.ai\",\"apiProvider\":\"firstParty\",\"email\":\"a@example.com\",\"subscriptionType\":\"max\",\"loginExpiresAt\":\"2026-11-15T05:26:13.425Z\",\"orgId\":\"x\"}'" > "$tmp/fake-claude"
chmod +x "$tmp/fake-claude"
assert_eq "$(CLAUDE_BIN="$tmp/fake-claude" "$A" whoami)" '{"provider":"firstParty","auth":"claude.ai","plan":"max","account":"a@example.com","expires":"2026-11-15T05:26:13.425Z"}' "provider, sign-in, plan, account and when the sign-in ends, nothing else"
printf '%s\n' '#!/bin/sh' "printf '%s\n' '{\"loggedIn\":false,\"authMethod\":\"none\",\"apiProvider\":\"firstParty\",\"subscriptionType\":null}'; exit 1" > "$tmp/fake-claude-out"
chmod +x "$tmp/fake-claude-out"
assert_eq "$(CLAUDE_BIN="$tmp/fake-claude-out" "$A" whoami)" '{"provider":"unknown","auth":"unknown","plan":"unknown","account":"unknown","expires":"unknown"}' "a failing status call reports unknown, not what it half-printed"
assert_eq "$(CLAUDE_BIN=/usr/bin/false "$A" whoami)" '{"provider":"unknown","auth":"unknown","plan":"unknown","account":"unknown","expires":"unknown"}' "no status at all reports unknown"

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
