#!/bin/bash
# Tests for the omp adapter beyond the shared contract (tests/adapter-contract.sh runs
# the contract against it too). What is pinned here is what only omp has: the linearizer
# and its rejection paths, nested-session provenance, and omp-shaped stats.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
A="$REPO/adapters/omp/adapter.sh"
LIN="$REPO/adapters/omp/linearize.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_eq(){ [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }
assert_rc(){ # $1=got $2=want $3=label
  [ "$1" = "$2" ] && ok "$3" || no "$3 (exit $1, want $2)"
}

[ -x "$A" ] && [ -x "$LIN" ] || { printf '  FAIL - adapters/omp adapter.sh or linearize.sh missing or not executable\n'
                                  printf '\npassed: 0   failed: 1\n'; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/adomp.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

HDR_TITLE='{"type":"title","title":"t","v":1}'
hdr_session(){ printf '{"type":"session","id":"01a00000-0000-7000-8000-0000000000%s","cwd":"%s","timestamp":"2026-01-02T12:00:00.000Z"}\n' "${1:-01}" "${2:-/tmp}"; }
umsg(){ # $1=id $2=parent|null $3=text
  local p; if [ "$2" = null ]; then p=null; else p="\"$2\""; fi
  printf '{"type":"message","id":"%s","parentId":%s,"timestamp":"2026-01-02T12:00:02.000Z","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' "$1" "$p" "$3"
}
amsg(){ # $1=id $2=parent $3=text
  printf '{"type":"message","id":"%s","parentId":"%s","timestamp":"2026-01-02T12:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1" "$2" "$3"
}

echo "# linearize: the live branch only"
# Two branches off u1. a2 was appended after a1, so a2 is the live leaf and a1/u2 are
# the abandoned branch. The abandoned work must not reach triage.
S1="$tmp/branched.jsonl"
{ echo "$HDR_TITLE"; hdr_session 01 /tmp
  umsg u1 null "first"
  amsg a1 u1 "abandoned-reply"
  umsg u2 a1 "abandoned-followup"
  amsg a2 u1 "live-reply"
} > "$S1"
"$LIN" "$S1" "$tmp/b.out" 2>/dev/null; assert_rc "$?" 0 "a branched tree linearizes"
assert_eq "$(jq -r 'select(.type=="message") | .id' "$tmp/b.out" | tr '\n' ' ')" "u1 a2 " "only the chain from the live leaf is kept, root first"
if grep -q 'abandoned' "$tmp/b.out"; then no "abandoned branch text must not appear"; else ok "abandoned branch text does not appear"; fi
assert_eq "$(jq -r 'select(.type=="autodream_meta") | "\(.entries) \(.on_path) \(.dropped) \(.source)"' "$tmp/b.out")" "4 2 2 omp" "meta counts entries, kept and dropped"
assert_eq "$(head -1 "$tmp/b.out" | jq -r .type)" "autodream_meta" "the meta record comes first"

echo "# linearize: fails closed, writes nothing"
reject(){ # $1=label $2=file $3=want-rc
  rm -f "$tmp/r.out"
  "$LIN" "$2" "$tmp/r.out" >/dev/null 2>&1; local rc=$?
  assert_rc "$rc" "$3" "$1 is refused"
  if [ -e "$tmp/r.out" ]; then no "$1 left an output file"; else ok "$1 left no output"; fi
  set -- "$tmp"/r.out.tmp*
  if [ -e "$1" ]; then no "a rejected input left a temp"; else ok "a rejected input left no temp"; fi
}
M="$tmp/malformed.jsonl"
{ echo "$HDR_TITLE"; hdr_session 02 /tmp; umsg u1 null a; printf '{"type":"message","id":"x1","parentId":"u1",BROKEN\n'; amsg a1 u1 b; } > "$M"
reject "a malformed JSON line" "$M" 4
D="$tmp/dangling.jsonl"
{ echo "$HDR_TITLE"; hdr_session 03 /tmp; umsg u1 null a; amsg a1 ghost b; } > "$D"
reject "a dangling parentId" "$D" 4
C="$tmp/cycle.jsonl"
{ echo "$HDR_TITLE"; hdr_session 04 /tmp; umsg u1 a1 a; amsg a1 u1 b; } > "$C"
reject "a parentId cycle" "$C" 4
C3="$tmp/cycle3.jsonl"
{ echo "$HDR_TITLE"; hdr_session 05 /tmp; umsg u1 null a; amsg a1 u1 b; umsg u2 a1 c; umsg a3 u2 d; amsg a2 a3 e; } > "$C3"
# u1 is a real root here; make a loop that does not include the root: a1 -> u2 -> a3 -> a1
{ echo "$HDR_TITLE"; hdr_session 05 /tmp; umsg u1 null a; amsg a1 a3 b; umsg u2 a1 c; amsg a3 u2 d; } > "$C3"
reject "a cycle that excludes the root" "$C3" 4
DUP="$tmp/dupid.jsonl"
{ echo "$HDR_TITLE"; hdr_session 15 /tmp; umsg u1 null a; amsg a1 u1 b; umsg u1 a1 c; } > "$DUP"
reject "a duplicated entry id" "$DUP" 4
NOID="$tmp/noid.jsonl"
{ echo "$HDR_TITLE"; hdr_session 06 /tmp; umsg u1 null a; printf '{"type":"message","parentId":"u1","message":{"role":"assistant","content":"x"}}\n'; } > "$NOID"
reject "an entry without an id" "$NOID" 4
NOTOMP="$tmp/claude.jsonl"
printf '{"type":"user","cwd":"/tmp","message":{"content":"hi"}}\n' > "$NOTOMP"
reject "a Claude transcript" "$NOTOMP" 2
EMPTYF="$tmp/empty.jsonl"; : > "$EMPTYF"
reject "an empty file" "$EMPTYF" 2
"$LIN" "$tmp/nope.jsonl" "$tmp/r2.out" >/dev/null 2>&1; assert_rc "$?" 1 "an unreadable input exits 1"
mkdir -p "$tmp/adir"
"$LIN" "$S1" "$tmp/adir" >/dev/null 2>&1; assert_rc "$?" 1 "a directory destination exits 1"
if [ -z "$(ls -A "$tmp/adir")" ]; then ok "nothing planted in a directory destination"; else no "something was planted in the directory destination"; fi
"$LIN" "$S1" >/dev/null 2>&1; assert_rc "$?" 1 "a missing destination argument exits 1"

echo "# linearize: edge shapes that must work"
ONLY="$tmp/onlyhdr.jsonl"
{ echo "$HDR_TITLE"; hdr_session 07 /tmp; } > "$ONLY"
"$LIN" "$ONLY" "$tmp/o.out" >/dev/null 2>&1; assert_rc "$?" 0 "a session with a header and no entries linearizes"
assert_eq "$(wc -l < "$tmp/o.out" | tr -d ' ')" "1" "and carries only the meta record"
LEGACY="$tmp/legacy.jsonl"
{ hdr_session 08 /tmp; umsg u1 null a; amsg a1 u1 b; } > "$LEGACY"
"$LIN" "$LEGACY" "$tmp/l.out" >/dev/null 2>&1; assert_rc "$?" 0 "a legacy file that starts at the header linearizes"
BLANK="$tmp/blank.jsonl"
{ echo "$HDR_TITLE"; hdr_session 09 /tmp; echo; umsg u1 null a; echo "   "; amsg a1 u1 b; } > "$BLANK"
"$LIN" "$BLANK" "$tmp/bl.out" >/dev/null 2>&1; assert_rc "$?" 0 "blank lines are ignored, not parsed"
SPACEPATH="$tmp/dir with space"; mkdir -p "$SPACEPATH"; cp "$S1" "$SPACEPATH/a b.jsonl"
"$LIN" "$SPACEPATH/a b.jsonl" "$tmp/sp.out" >/dev/null 2>&1; assert_rc "$?" 0 "a path with spaces linearizes"

echo "# nested sessions: provenance comes from the path"
NB="$tmp/store/-bucket"; mkdir -p "$NB/2026-01-02T12-00-00-000Z_01a0"
cp "$S1" "$NB/2026-01-02T12-00-00-000Z_01a0.jsonl"
cp "$S1" "$NB/2026-01-02T12-00-00-000Z_01a0/__advisor.jsonl"
cp "$S1" "$NB/2026-01-02T12-00-00-000Z_01a0/Rebase1.jsonl"
"$LIN" "$NB/2026-01-02T12-00-00-000Z_01a0/__advisor.jsonl" "$tmp/adv.out" >/dev/null 2>&1
assert_eq "$(jq -r 'select(.type=="autodream_meta") | "\(.nested) \(.is_advisor)"' "$tmp/adv.out")" "true true" "an advisor child is nested and flagged advisor"
"$LIN" "$NB/2026-01-02T12-00-00-000Z_01a0/Rebase1.jsonl" "$tmp/sub.out" >/dev/null 2>&1
assert_eq "$(jq -r 'select(.type=="autodream_meta") | "\(.nested) \(.is_advisor)"' "$tmp/sub.out")" "true false" "a task subagent child is nested and not an advisor"
"$LIN" "$NB/2026-01-02T12-00-00-000Z_01a0.jsonl" "$tmp/par.out" >/dev/null 2>&1
assert_eq "$(jq -r 'select(.type=="autodream_meta") | "\(.nested) \(.is_advisor)"' "$tmp/par.out")" "false false" "the parent session is neither"
assert_eq "$(jq -r 'select(.type=="autodream_meta") | .parent_session_file | if . == null then "null" else (split("/")|last) end' "$tmp/sub.out")" "2026-01-02T12-00-00-000Z_01a0.jsonl" "a child names its parent file"
# enumerate returns children too: they are sessions to triage.
touch -t 202601021200 "$NB"/*.jsonl "$NB"/*/*.jsonl
enum=$("$A" enumerate "$tmp/store" 2026-01-02 2026-01-03 2>/dev/null | tr '\0' '\n' | sort | wc -l | tr -d ' ')
assert_eq "$enum" "3" "enumerate returns the parent and both children"

echo "# project: the header cwd, resolved"
real=$(cd /tmp && pwd -P)
assert_eq "$("$A" project "$S1")" "$real" "project resolves the header cwd (/tmp is a symlink on macOS)"
"$A" normalize "$S1" "$tmp/np.out" >/dev/null 2>&1
assert_eq "$("$A" project "$tmp/np.out")" "$real" "a normalized copy answers the same"
"$A" project "$ONLY" >/dev/null 2>&1; assert_rc "$?" 0 "a header with a cwd and no entries still has a project"
NOCWD="$tmp/nocwd.jsonl"
{ echo "$HDR_TITLE"; printf '{"type":"session","id":"01a00000-0000-7000-8000-000000000010","timestamp":"2026-01-02T12:00:00.000Z"}\n'; umsg u1 null a; } > "$NOCWD"
"$A" project "$NOCWD" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "a header with no cwd has no project"; else no "a header with no cwd must not report a project"; fi
QCWD="$tmp/qcwd.jsonl"; mkdir -p "$tmp/we\"ird"
{ echo "$HDR_TITLE"; printf '{"type":"session","id":"01a00000-0000-7000-8000-000000000011","cwd":"%s","timestamp":"2026-01-02T12:00:00.000Z"}\n' "$tmp/we\\\"ird"; umsg u1 null a; } > "$QCWD"
assert_eq "$("$A" project "$QCWD")" "$(cd "$tmp/we\"ird" && pwd -P)" "a cwd containing a quote survives JSON escaping"

echo "# stats: omp shapes"
"$A" stats "$S1" "$tmp/st.json" >/dev/null 2>&1; assert_rc "$?" 0 "stats on a raw session"
assert_eq "$(jq -r '"\(.user_message_count) \(.is_advisor) \(.nested)"' "$tmp/st.json")" "2 false false" "a raw session counts both user turns and is not an advisor (raw keeps abandoned work)"
"$A" normalize "$S1" "$tmp/sn.out" >/dev/null 2>&1; "$A" stats "$tmp/sn.out" "$tmp/stn.json" >/dev/null 2>&1
assert_eq "$(jq -r '"\(.user_message_count) \(.turn_count)"' "$tmp/stn.json")" "1 2" "a linearized session counts only the live branch"
"$A" normalize "$NB/2026-01-02T12-00-00-000Z_01a0/__advisor.jsonl" "$tmp/an.out" >/dev/null 2>&1; "$A" stats "$tmp/an.out" "$tmp/stadv.json" >/dev/null 2>&1
assert_eq "$(jq -r '"\(.is_advisor) \(.nested)"' "$tmp/stadv.json")" "true true" "an advisor's flags survive the normalized copy, whose filename is a temp"
"$A" stats "$NB/2026-01-02T12-00-00-000Z_01a0/__advisor.jsonl" "$tmp/stadv2.json" >/dev/null 2>&1
assert_eq "$(jq -r .is_advisor "$tmp/stadv2.json")" "true" "a raw advisor is flagged from its own filename"
cp "$S1" "$tmp/__advisor-review.jsonl"; "$A" stats "$tmp/__advisor-review.jsonl" "$tmp/stadv3.json" >/dev/null 2>&1
assert_eq "$(jq -r .is_advisor "$tmp/stadv3.json")" "true" "__advisor-<name>.jsonl is flagged too"
# The path through normalize, which is the one the runner takes: the linearizer and stats
# are two files holding one rule, and a recorded false must not fall back to the temp name.
cp "$S1" "$NB/2026-01-02T12-00-00-000Z_01a0/__advisor-review.jsonl"
"$A" normalize "$NB/2026-01-02T12-00-00-000Z_01a0/__advisor-review.jsonl" "$tmp/advn.out" >/dev/null 2>&1
assert_eq "$(jq -r 'select(.type=="autodream_meta") | .is_advisor' "$tmp/advn.out")" "true" "the linearizer flags __advisor-<name>.jsonl"
"$A" stats "$tmp/advn.out" "$tmp/stadvn.json" >/dev/null 2>&1
assert_eq "$(jq -r .is_advisor "$tmp/stadvn.json")" "true" "and stats keeps it on the normalized copy"
cp "$S1" "$NB/2026-01-02T12-00-00-000Z_01a0/Plain.jsonl"
"$A" normalize "$NB/2026-01-02T12-00-00-000Z_01a0/Plain.jsonl" "$tmp/plainn.out" >/dev/null 2>&1
"$A" stats "$tmp/plainn.out" "$tmp/stplain.json" >/dev/null 2>&1
assert_eq "$(jq -r .is_advisor "$tmp/stplain.json")" "false" "a recorded false stays false even though the temp name is no advisor either"
cp "$S1" "$tmp/my__advisor.jsonl"; "$A" stats "$tmp/my__advisor.jsonl" "$tmp/stadv4.json" >/dev/null 2>&1
assert_eq "$(jq -r .is_advisor "$tmp/stadv4.json")" "false" "the stem is anchored: my__advisor.jsonl is a real session"
SK="$tmp/skills.jsonl"
{ echo "$HDR_TITLE"; hdr_session 12 /tmp; umsg u1 null a
  printf '{"type":"custom_message","id":"c1","parentId":"u1","customType":"skill-prompt","content":"[IMPORTANT: User invoked the \\"review\\" skill; follow it]"}\n'
  printf '{"type":"message","id":"a1","parentId":"c1","message":{"role":"assistant","content":[{"type":"toolCall","name":"manage_skill","arguments":{"name":"new-skill","action":"create"}}]}}\n'
} > "$SK"
"$A" stats "$SK" "$tmp/stsk.json" >/dev/null 2>&1
assert_eq "$(jq -r '"\(.skills_invoked|join(",")) \(.skills_authored|join(","))"' "$tmp/stsk.json")" "review new-skill" "skill invocation and authoring are counted separately"

echo "# is-self: omp's own worker transcripts"
SELF="$tmp/self.jsonl"
{ echo "$HDR_TITLE"; hdr_session 13 /tmp; umsg u1 null "Session transcript to analyze (literal absolute path): /x"; } > "$SELF"
"$A" is-self "$SELF" >/dev/null 2>&1; assert_rc "$?" 0 "a session whose first turn is autodream's prompt is ours"
"$A" is-self "$S1" >/dev/null 2>&1; assert_rc "$?" 1 "an ordinary omp session is not"
DISC="$tmp/discuss.jsonl"
{ echo "$HDR_TITLE"; hdr_session 14 /tmp; umsg u1 null "hello"; umsg u2 u1 "Session transcript to analyze (literal absolute path): /x"; } > "$DISC"
"$A" is-self "$DISC" >/dev/null 2>&1; assert_rc "$?" 1 "a session that only mentions the prompt later is not (anchored to the first turn)"

echo "# slim: reuses the shared slimmer on a linearized copy"
"$A" slim "$tmp/sn.out" "$tmp/slim.out" >/dev/null 2>&1; assert_rc "$?" 0 "slim accepts a linearized transcript"
if [ -s "$tmp/slim.out" ]; then ok "slim wrote output"; else no "slim wrote output"; fi

echo "# skills-inventory"
HOME_FAKE="$tmp/home"; mkdir -p "$HOME_FAKE/.agents/skills/alpha" "$HOME_FAKE/.agents/skills/off"
printf -- '---\nname: alpha\ndescription: does alpha things\n---\nbody\n' > "$HOME_FAKE/.agents/skills/alpha/SKILL.md"
printf -- '---\nname: off\ndescription: disabled one\nenabled: false\n---\nbody\n' > "$HOME_FAKE/.agents/skills/off/SKILL.md"
inv=$(HOME="$HOME_FAKE" "$A" skills-inventory 2>/dev/null); rc=$?
assert_rc "$rc" 0 "skills-inventory exits 0"
assert_eq "$(printf '%s\n' "$inv" | cut -f1 | tr '\n' ' ')" "alpha " "an enabled skill is listed and a disabled one is not"
assert_eq "$(printf '%s\n' "$inv" | cut -f2)" "does alpha things" "the description follows a TAB"
emptyinv=$(HOME="$tmp/nohome" "$A" skills-inventory 2>/dev/null); rc=$?
assert_rc "$rc" 0 "an empty skill surface is a valid empty inventory"
assert_eq "$emptyinv" "" "and prints nothing"

echo "# unknown subcommand and arity"
"$A" bogus >/dev/null 2>&1; assert_rc "$?" 2 "an unknown subcommand exits 2"
"$A" normalize "$S1" >/dev/null 2>&1; assert_rc "$?" 2 "normalize with one argument is a usage error, not a skip"
"$A" stats "$S1" >/dev/null 2>&1; assert_rc "$?" 2 "stats with one argument is a usage error"

echo "# l1-argv reproduces omp-autodream's worker invocation"
OLD_SYS="Headless triage worker. Read the session transcript and write exactly one findings JSON object, via the Write tool, to the literal output path given on line 2 of the prompt. Those paths are literal strings, not shell variables — never \$-expand them. Print only the literal word done and exit."
printf '%s\0' /opt/test/omp --allow-home -p --approval-mode yolo --no-session --config /opt/test/overlay.yml \
  --model deepseek/deepseek-flash --tools=Read,Write --append-system-prompt "$OLD_SYS" > "$tmp/old-argv"
OMP_BIN=/opt/test/omp NO_ADVISOR_CFG=/opt/test/overlay.yml "$A" l1-argv deepseek/deepseek-flash > "$tmp/new-argv"
if cmp -s "$tmp/old-argv" "$tmp/new-argv"; then ok "the omp L1 argv is byte for byte omp-autodream's"
else no "the omp L1 argv is byte for byte omp-autodream's"; fi
# The overlay defaults to the one beside the adapter, and it is the file that turns recall off.
ov=$(OMP_BIN=/opt/test/omp "$A" l1-argv m | tr '\0' '\n' | sed -n '/^--config$/{n;p;}')
assert_eq "$(basename "$ov")" "l1-no-advisor.yml" "the overlay defaults to the adapter's own"
if grep -q 'autoRecall: false' "$ov" && grep -q 'enabled: false' "$ov"; then ok "the overlay turns off recall and the advisor"
else no "the overlay turns off recall and the advisor"; fi
assert_eq "$(OMP_BIN=/opt/pinned/omp "$A" engine-bin)" "/opt/pinned/omp" "an explicit OMP_BIN wins"
mkdir -p "$tmp/fakehome/.bun/bin"; printf '#!/bin/sh\n' > "$tmp/fakehome/.bun/bin/omp"; chmod +x "$tmp/fakehome/.bun/bin/omp"
assert_eq "$(env -u OMP_BIN HOME="$tmp/fakehome" PATH=/usr/bin:/bin "$A" engine-bin)" "$tmp/fakehome/.bun/bin/omp" "with no PATH omp, a known install location is found"
# The absolute candidates are real paths on a developer machine, so the bare-name fallback is
# only observable on a host that has none of them. Asserting it unconditionally made the suite
# depend on where omp happens to be installed.
if [ ! -x /opt/homebrew/bin/omp ] && [ ! -x /usr/local/bin/omp ]; then
  assert_eq "$(env -u OMP_BIN HOME="$tmp/nohome" PATH=/usr/bin:/bin "$A" engine-bin)" "omp" "with nothing found it falls back to the bare name"
else
  ok "the bare-name fallback is not observable here: omp is installed at a candidate path"
fi
assert_eq "$("$A" l1-env | wc -c | tr -d ' ')" "0" "omp needs no environment for its L1 worker"

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
