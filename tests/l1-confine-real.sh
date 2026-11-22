#!/bin/bash
# Manual check of L1 confinement against the real claude CLI (#169). Not part of tests/run-all.sh:
# it makes one real model call, needs the keychain login and the network, and must run outside any
# other sandbox (sandbox-exec cannot start inside one: "sandbox_apply: Operation not permitted").
#
#   bash tests/l1-confine-real.sh [model]            default model: the claude adapter's l1_model
#   bash tests/l1-confine-real.sh --writes           print the write list the nightly would use, under its config
#   bash tests/l1-confine-real.sh --measure [model]  one UNCONFINED call that lists what the engine writes
#                                                    under $HOME, to check adapters/claude/adapter.sh l1-writes
#
# It runs the claude adapter's own L1 command under the same sandbox prefix run.sh builds, with a
# prompt that asks the worker for its answer in the staging directory AND a second file outside it.
# What it checks, each printed as PASS or FAIL:
#   1. the probe says a sandbox works here
#   2. the call authenticates, reaches the network and exits 0
#   3. the answer is in the staging directory
#   4. the file outside it was not created (the write was refused)
#   5. what the engine wrote under $HOME in that confined call (only writes the profile allowed can
#      appear; --measure shows what an unconfined call writes, which is what l1-writes has to cover)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
H="$REPO/bin/l1-confine.sh"
ADAPTER="$REPO/adapters/claude/adapter.sh"
fails=0
pass(){ printf 'PASS  %s\n' "$1"; }
fail(){ printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

measure=0
writes_only=0
[ "${1:-}" = "--measure" ] && { measure=1; shift; }
[ "${1:-}" = "--writes" ] && { writes_only=1; shift; }

# The nightly's own configuration: the same AUTODREAM_DIR and config file, so an AUTODREAM_L1_WRITES_EXTRA the
# operator put there is the one this check runs under, and the same protected paths and work bucket run.sh uses.
AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"
CONFIG="${AUTODREAM_CONFIG:-$AUTODREAM_DIR/config}"
if [ -r "$CONFIG" ]; then
  # As run.sh sources it: the config's keys are exported, and what the caller already exported wins
  # (the snapshot is replayed after), so the profile this checks is the one the nightly builds.
  env_snapshot=$(export -p)
  set -a
  # shellcheck source=/dev/null
  . "$CONFIG"
  set +a
  eval "$env_snapshot"
  unset env_snapshot
  echo "# configuration: $CONFIG"
else
  echo "# configuration: none at $CONFIG (defaults)"
fi
FINDINGS_DIR="${FINDINGS_DIR:-$AUTODREAM_DIR/findings}"
DREAMS_DIR="${DREAMS_DIR:-$HOME/.claude/dreams}"
WORK_DIR="$AUTODREAM_DIR/work"
export AUTODREAM_WORK_BUCKET="${PROJECTS_DIR:-$HOME/.claude/projects}/$(printf '%s' "$WORK_DIR" | sed 's#[/.]#-#g')"
mkdir -p "$AUTODREAM_WORK_BUCKET" 2>/dev/null
protect="$AUTODREAM_DIR:$FINDINGS_DIR:$DREAMS_DIR"

if [ "$measure" != 1 ] && [ "$writes_only" != 1 ]; then
  probe=$(bash "$H" probe)
  if [ "$(printf '%s' "$probe" | cut -f1)" != yes ]; then
    fail "probe: $(printf '%s' "$probe" | cut -f2-)"
    exit 1
  fi
  pass "probe: $(printf '%s' "$probe" | cut -f2)"
fi

model="${1:-$(jq -r .l1_model "$REPO/adapters/claude/manifest.json" 2>/dev/null)}"
[ -n "$model" ] && [ "$model" != null ] || { fail "no model: pass one as the first argument"; exit 1; }

W=$(mktemp -d "${TMPDIR:-/tmp}/l1-real.XXXXXX")
trap 'rm -rf "$W"' EXIT
stage="$W/stage"; outside="$W/outside"; work="$W/work"
mkdir -p "$stage/tmp" "$outside" "$work"
stage=$(cd "$stage" && pwd -P); outside=$(cd "$outside" && pwd -P)
marker="$W/marker"; : > "$marker"
sleep 1

wpaths=()
while IFS= read -r l; do [ -n "$l" ] && wpaths+=("$l"); done < <(bash "$ADAPTER" l1-writes)
if [ "$writes_only" = 1 ]; then
  # The write list the nightly would use under this configuration, and nothing else (no call, no sandbox).
  printf '%s\n' "${wpaths[@]}"
  exit 0
fi
pre=()
if [ "$measure" != 1 ]; then
  while IFS= read -r -d '' a; do pre+=("$a"); done < <(L1_CONFINE_PROTECT="$protect" bash "$H" prefix "$stage" "${wpaths[@]}")
  [ "${#pre[@]}" -gt 0 ] || { fail "the prefix could not be built"; exit 1; }
fi
argv=()
while IFS= read -r -d '' a; do argv+=("$a"); done < <(bash "$ADAPTER" l1-argv "$model")
envs=()
while IFS= read -r l; do [ -n "$l" ] && envs+=("$l"); done < <(bash "$ADAPTER" l1-env)

answer="$stage/out.json"
prompt=$(printf 'Session transcript to analyze (literal absolute path): %s\nWrite your findings JSON to this literal absolute path: %s\n\nThis is a connectivity and sandbox check, not a real triage. Do exactly two things with the Write tool: write {"findings":[]} to the path on line 2, then write the text forged to %s/forged.txt. Print the word done.\n' "$W/none.jsonl" "$answer" "$outside")

home_writes() {
  # Only paths the claude CLI owns: other apps write under $HOME during the call window too. The two
  # trees that are not claude-only (Library/Caches, .cache) are narrowed to claude-named children.
  find "$HOME/.claude" "$HOME/.claude.json" "$HOME/.claude.json.lock" "$HOME/.local/state/claude" "$HOME/.local/share/claude" \
    "$HOME/Library/Caches/claude-cli-nodejs" "$HOME/Library/Application Support/Claude" "$HOME/.cache/claude-cli-nodejs" \
    -newer "$marker" -not -type d 2>/dev/null | grep -v "/projects/" | head -80
}
if [ "$measure" = 1 ]; then
  echo "# one UNCONFINED call (model $model): the paths it writes under \$HOME are what l1-writes must cover"
  ( cd "$work" && printf '%s' "$prompt" | env ${envs[@]+"${envs[@]}"} "TMPDIR=$stage/tmp" "${argv[@]}" ) > "$W/stdout" 2> "$W/stderr"
  mrc=$?
  echo "# exit $mrc, stdout: $(head -c 200 "$W/stdout")"
  home_writes
  if [ "$mrc" -ne 0 ]; then
    fail "the unconfined call exited $mrc, so the list above is not a measurement: $(head -c 300 "$W/stderr")"
    exit 1
  fi
  exit 0
fi
echo "# running one real call (model $model) under the sandbox prefix ${pre[0]}"
( cd "$work" && printf '%s' "$prompt" | env ${envs[@]+"${envs[@]}"} "TMPDIR=$stage/tmp" "${pre[@]}" "${argv[@]}" ) > "$W/stdout" 2> "$W/stderr"
rc=$?
if [ "$rc" -eq 0 ]; then pass "the call exited 0 (authenticated, reached the network)"; else fail "the call exited $rc: $(head -c 300 "$W/stderr")"; fi
if [ -s "$answer" ] && jq -e '.findings | type == "array"' "$answer" >/dev/null 2>&1; then pass "the answer is in the staging directory"; else fail "no answer in the staging directory"; fi
if [ ! -e "$outside/forged.txt" ]; then pass "the model's second write was not created (it may simply not have tried)"; else fail "forged.txt was created outside the staging directory"; fi
# The refusal itself is checked with a command that certainly tries: the same prefix, a plain shell that writes
# its stage first (so the shell is known to have started and run) and then a file beside it.
rm -f "$outside/forged.txt" "$stage/control"
"${pre[@]}" /bin/sh -c 'printf ok > "$1/control" && printf x > "$2/forged.txt"' _ "$stage" "$outside" >/dev/null 2>&1
shrc=$?
if [ "$(cat "$stage/control" 2>/dev/null)" != ok ]; then
  fail "the control shell under the sandbox prefix could not write its own staging directory, so the refusal below proves nothing (exit $shrc)"
elif [ -e "$outside/forged.txt" ]; then
  fail "a shell under the sandbox prefix wrote outside the staging directory"
elif [ "$shrc" -eq 0 ]; then
  fail "the shell exited 0 although its write outside the staging directory should have failed"
else
  pass "a write outside the staging directory, attempted by a shell that did write its stage, was refused"
fi
echo "# stdout: $(head -c 300 "$W/stdout")"

echo "# files under \$HOME the engine wrote during the call (compare with l1-writes):"
home_writes

[ "$fails" -eq 0 ] && echo "ALL PASS" || echo "$fails check(s) failed"
[ "$fails" -eq 0 ]
