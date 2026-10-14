#!/bin/bash
# Tests for bin/prune-worktrees.sh - the nightly removal of finished worktrees and branches.
#
# Everything here is a real git repo in a temp dir. The remote is a local bare repo that a
# per-repo `url.insteadOf` makes answer to https://github.com/test/<name>.git, and `gh` is a
# shim earlier on PATH that serves PR state from files and performs ref deletions against the
# bare repo. No network, no GitHub.
#
# The script deletes branches on a remote, so most of these cases pin a KEEP: a dirty tree, an
# unpushed commit, an open PR, a fresh file, a lock, a protected name. A wrong delete cannot be
# undone and a wrong keep costs one more night.
#
# Usage:  tests/prune-worktrees.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp prune
BIN="$REPO_ROOT/bin/prune-worktrees.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_grep(){   grep -q "$2" "$1" 2>/dev/null && ok "$3" || no "$3 (no /$2/ in $1)"; }
assert_nogrep(){ grep -q "$2" "$1" 2>/dev/null && no "$3 (/$2/ unexpectedly in $1)" || ok "$3"; }

T=$SUITE_TMP
export FAKE_GH_DIR="$T/gh"
export FAKE_GH_ROOT="$T"
mkdir -p "$FAKE_GH_DIR" "$T/bin"

# ---- the gh shim ----------------------------------------------------------------------------
cat > "$T/bin/gh" <<'SH'
#!/bin/bash
[ -n "${FAKE_GH_FAIL:-}" ] && { echo "gh: simulated failure" >&2; exit 1; }
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr list")
    shift 2; repo=""; head=""
    while [ $# -gt 0 ]; do
      case "$1" in -R) repo=$2 ;; --head) head=$2 ;; esac
      shift
    done
    f="$FAKE_GH_DIR/pr-${repo#test/}-$head.json"
    [ -f "$f" ] && cat "$f" || echo '[]' ;;
  "api -X")
    # gh api -X DELETE repos/test/<name>/git/refs/heads/<branch>
    path=$4; rest=${path#repos/test/}; name=${rest%%/*}; ref=${rest#*/git/}
    echo "$name $ref" >> "$FAKE_GH_DIR/deletes.log"
    git --git-dir="$FAKE_GH_ROOT/remotes/$name.git" update-ref -d "$ref" ;;
  *) echo "fake gh: unhandled: $*" >&2; exit 2 ;;
esac
SH
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

# Every commit is from 2020, so a branch with no worktree clears the recent-commit gate.
export GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" GIT_COMMITTER_DATE="2020-01-01T00:00:00Z"

# trash shim: moves the path under $T/trashed and fails when TRASH_FAIL is set.
cat > "$T/bin/trash" <<'SH'
#!/bin/bash
[ -n "${TRASH_FAIL:-}" ] && exit 1
mkdir -p "$FAKE_GH_ROOT/trashed" && mv "$1" "$FAKE_GH_ROOT/trashed/$(basename "$1")-$RANDOM"
SH
chmod +x "$T/bin/trash"

g(){ git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }

# make_repo NAME [noremote] - seeds a repo with two commits on main and a tracked .gitignore.
make_repo(){
  NAME=$1
  BARE="$T/remotes/$NAME.git"
  R="$T/roots-$NAME/$NAME"
  mkdir -p "$T/roots-$NAME" "$T/seed-$NAME"
  g init -q "$T/seed-$NAME"
  echo one > "$T/seed-$NAME/a"; g -C "$T/seed-$NAME" add a; g -C "$T/seed-$NAME" commit -qm one
  FIRST=$(g -C "$T/seed-$NAME" rev-parse HEAD)
  printf 'ignored.out\n' > "$T/seed-$NAME/.gitignore"
  g -C "$T/seed-$NAME" add .gitignore; g -C "$T/seed-$NAME" commit -qm two
  if [ "${2:-}" = noremote ]; then
    g clone -q "$T/seed-$NAME" "$R"
    g -C "$R" remote remove origin
    return
  fi
  g init -q --bare "$BARE"
  g -C "$T/seed-$NAME" push -q "$BARE" main
  g -C "$BARE" symbolic-ref HEAD refs/heads/main
  g clone -q "$BARE" "$R"
  g -C "$R" config remote.origin.url "https://github.com/test/$NAME.git"
  g -C "$R" config "url.$BARE.insteadOf" "https://github.com/test/$NAME.git"
}

# worktree NAME - branch NAME at origin/main, checked out under <repo>/.claude/worktrees/NAME.
worktree(){ g -C "$R" worktree add -q -b "$1" "$R/.claude/worktrees/$1" origin/main; }
wt(){ echo "$R/.claude/worktrees/$1"; }
commit_in(){ echo "$RANDOM$1" > "$(wt "$1")/f-$1"; g -C "$(wt "$1")" add -A; g -C "$(wt "$1")" commit -qm "work $1"; }
tip(){ g -C "$R" rev-parse "refs/heads/$1"; }
push(){ g -C "$R" push -q origin "$1"; }
# pr NAME STATE HEAD [CLOSED_AT] - what the shim answers for `gh pr list --head NAME`.
pr(){
  printf '[{"number":%s,"state":"%s","mergedAt":null,"closedAt":"%s","headRefOid":"%s","url":"https://github.com/test/%s/pull/%s"}]\n' \
    "$RANDOM" "$2" "${4:-2020-01-01T00:00:00Z}" "$3" "$NAME" "$RANDOM" > "$FAKE_GH_DIR/pr-$NAME-$1.json"
}
# age PATH - push every mtime under a worktree (and its gitdir) far into the past.
age(){
  find "$1" -path '*/.git' -prune -o -type f -exec touch -t 202001010000 {} + 2>/dev/null
  find "$R/.git/worktrees" -type f -exec touch -t 202001010000 {} + 2>/dev/null
}
has_wt(){ [ -d "$(wt "$1")" ]; }
has_local(){ g -C "$R" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
has_remote(){ g --git-dir="$BARE" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
expect_removed(){ # NAME LABEL
  if ! has_wt "$1" && ! has_local "$1" && ! has_remote "$1"; then ok "$2: worktree, local and remote branch removed"
  else no "$2: expected full removal (wt=$(has_wt "$1" && echo y || echo n) local=$(has_local "$1" && echo y || echo n) remote=$(has_remote "$1" && echo y || echo n))"; fi
}
expect_kept(){ # NAME LABEL
  if has_wt "$1" && has_local "$1" && has_remote "$1"; then ok "$2: kept untouched"
  else no "$2: expected to keep everything (wt=$(has_wt "$1" && echo y || echo n) local=$(has_local "$1" && echo y || echo n) remote=$(has_remote "$1" && echo y || echo n))"; fi
}

run_prune(){ AUTODREAM_PRUNE_ROOTS="$T/roots-$NAME" AUTODREAM_PRUNE_GRACE_MIN=60 "$BIN" "$@" "$OUT" >"$OUT.stdout" 2>&1; }

echo "== script exists"
[ -x "$BIN" ] && ok "bin/prune-worktrees.sh is executable" || { no "bin/prune-worktrees.sh is missing or not executable"; echo; echo "$pass passed, $fail failed"; exit 1; }

# ==== pass 1: one repo, every state =============================================================
make_repo main1
OUT="$T/out1"; mkdir -p "$OUT"

worktree sq;       commit_in sq;       push sq;       pr sq MERGED "$(tip sq)"
echo junk > "$(wt sq)/ignored.out"
worktree dirty;    commit_in dirty;    push dirty;    pr dirty MERGED "$(tip dirty)"; echo x > "$(wt dirty)/untracked"
worktree unpushed; commit_in unpushed
worktree openpr;   commit_in openpr;   push openpr;   pr openpr OPEN "$(tip openpr)"
worktree newer;    commit_in newer;    push newer;    pr newer MERGED "$(tip newer)"; echo y > "$(wt newer)/more"; g -C "$(wt newer)" add -A; g -C "$(wt newer)" commit -qm more
worktree fresh;    commit_in fresh;    push fresh;    pr fresh MERGED "$(tip fresh)"
worktree moved;    commit_in moved;    push moved;    pr moved MERGED "$(tip moved)"
worktree closedold; commit_in closedold; push closedold; pr closedold CLOSED "$(tip closedold)" 2020-01-01T00:00:00Z
worktree closednew; commit_in closednew; push closednew; pr closednew CLOSED "$(tip closednew)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
worktree develop;  commit_in develop;  push develop;  pr develop MERGED "$(tip develop)"
worktree locked;   commit_in locked;   push locked;   pr locked MERGED "$(tip locked)"; g -C "$R" worktree lock "$(wt locked)"
worktree stale;    commit_in stale;    push stale;    pr stale MERGED "$(tip stale)"; g -C "$R" worktree remove "$(wt stale)"
g -C "$R" worktree add -q --detach "$(wt detached)" "$FIRST"
worktree gone;     commit_in gone;     push gone;     pr gone MERGED "$(tip gone)"
mkdir -p "$T/elsewhere"; g -C "$R" worktree add -q -b outside "$T/elsewhere/outside" origin/main
echo o > "$T/elsewhere/outside/f"; g -C "$T/elsewhere/outside" add -A; g -C "$T/elsewhere/outside" commit -qm o
push outside; pr outside MERGED "$(g -C "$R" rev-parse refs/heads/outside)"

# A second clone advances the remote branch after the PR merged at the old tip.
g clone -q "$BARE" "$T/other-moved"; g -C "$T/other-moved" checkout -q moved; echo z > "$T/other-moved/z"
g -C "$T/other-moved" add -A; g -C "$T/other-moved" commit -qm later; g -C "$T/other-moved" push -q origin moved

# Everything gets old except `fresh`, which a session touched a minute ago.
for n in sq dirty unpushed openpr newer moved closedold closednew develop locked gone; do age "$(wt "$n")"; done
age "$T/elsewhere/outside"; age "$(wt detached)"
rm -rf "$(wt gone)"

run_prune
echo "== pass 1: every state"
expect_removed sq "squash-merged PR at the branch tip (with an ignored build file)"
expect_kept dirty "untracked file in the worktree"
has_wt unpushed && has_local unpushed && ok "unpushed commit with no PR: kept" || no "unpushed commit with no PR: kept"
expect_kept openpr "open PR"
expect_kept newer "local commits after the merged PR head"
expect_kept fresh "file modified inside the grace window"
{ ! has_wt moved && ! has_local moved && has_remote moved; } && ok "remote branch moved after merge: local removed, remote branch kept" || no "remote branch moved after merge: local removed, remote branch kept"
expect_removed closedold "PR closed unmerged long ago"
expect_kept closednew "PR closed unmerged today"
expect_kept develop "protected branch name"
expect_kept locked "locked worktree"
{ ! has_local stale && ! has_remote stale; } && ok "merged branch with no worktree: local and remote deleted" || no "merged branch with no worktree: local and remote deleted"
[ ! -d "$(wt detached)" ] && ok "detached worktree at an old ancestor of main: removed" || no "detached worktree at an old ancestor of main: removed"
g -C "$R" worktree list --porcelain | grep -q "worktrees/gone" && no "manually deleted worktree: record pruned" || ok "manually deleted worktree: record pruned"
{ [ -d "$T/elsewhere/outside" ] && has_local outside && has_remote outside; } && ok "worktree outside .claude/worktrees: not touched" || no "worktree outside .claude/worktrees: not touched"
has_local main && ok "default branch survives" || no "default branch survives"
ls "$T/trashed" 2>/dev/null | grep -q '^sq-' && ok "removed worktree went to the Trash, not deleted" || no "removed worktree went to the Trash, not deleted"
assert_grep "$OUT/worktree-prune.tsv" "^kept.*dirty" "report names the dirty tree"
assert_grep "$OUT/worktree-prune.tsv" "^kept.*open-pr" "report names the open PR"
assert_grep "$OUT/worktree-prune.tsv" "^kept.*recent" "report names the recent edit"
assert_grep "$OUT/worktree-prune.tsv" "^removed.*moved.*remote kept" "report says the remote branch was kept"
assert_grep "$OUT/worktree-prune.md" "removed" "markdown summary written"
{ ! has_local gone && ! has_remote gone; } && ok "worktree deleted by hand: its merged branch goes with it" || no "worktree deleted by hand: its merged branch goes with it"
[ "$(wc -l < "$FAKE_GH_DIR/deletes.log")" -eq 4 ] && ok "exactly four remote refs deleted (sq, closedold, stale, gone)" || no "exactly four remote refs deleted (got $(wc -l < "$FAKE_GH_DIR/deletes.log"))"

# ==== pass 2: dry run changes nothing ===========================================================
make_repo dry; OUT="$T/out2"; mkdir -p "$OUT"
worktree d1; commit_in d1; push d1; pr d1 MERGED "$(tip d1)"; age "$(wt d1)"
run_prune --dry-run
echo "== pass 2: dry run"
expect_kept d1 "dry run"
assert_grep "$OUT/worktree-prune.tsv" "^would-remove" "dry run lists what it would remove"

# ==== pass 3: gh down means no proof, so nothing goes ===========================================
make_repo ghdown; OUT="$T/out3"; mkdir -p "$OUT"
worktree g1; commit_in g1; push g1; pr g1 MERGED "$(tip g1)"; age "$(wt g1)"
FAKE_GH_FAIL=1 run_prune
echo "== pass 3: gh unavailable"
expect_kept g1 "gh failing"
assert_grep "$OUT/worktree-prune.tsv" "gh-unavailable" "report names the gh failure"

# ==== pass 4: the per-run cap bounds the blast radius ===========================================
make_repo cap; OUT="$T/out4"; mkdir -p "$OUT"
for n in c1 c2 c3; do worktree $n; commit_in $n; push $n; pr $n MERGED "$(tip $n)"; age "$(wt $n)"; done
AUTODREAM_PRUNE_MAX=2 run_prune
echo "== pass 4: cap"
removed=0; for n in c1 c2 c3; do has_local $n || removed=$((removed + 1)); done
[ "$removed" -eq 2 ] && ok "cap of 2 removes exactly two of three" || no "cap of 2 removes exactly two of three (removed $removed)"
assert_grep "$OUT/worktree-prune.tsv" "cap" "report names the cap"

# ==== pass 5: a repo with no remote uses local ancestry =========================================
make_repo local1 noremote; OUT="$T/out5"; mkdir -p "$OUT"
g -C "$R" worktree add -q -b done1 "$(wt done1)"; commit_in done1
g -C "$R" merge -q --no-ff -m merge done1
g -C "$R" worktree add -q -b todo1 "$(wt todo1)"; commit_in todo1
age "$(wt done1)"; age "$(wt todo1)"
AUTODREAM_PRUNE_TRASH=0 run_prune
echo "== pass 5: no remote"
{ ! has_wt done1 && ! has_local done1; } && ok "no remote: branch merged into main is removed" || no "no remote: branch merged into main is removed"
{ has_wt todo1 && has_local todo1; } && ok "no remote: unmerged branch kept" || no "no remote: unmerged branch kept"

# ==== pass 6: the nightly entry point never fails the caller ====================================
OUT="$T/out6"; mkdir -p "$OUT"
AUTODREAM_PRUNE_ROOTS="$T/does-not-exist" "$BIN" "$OUT" >/dev/null 2>&1; rc=$?
echo "== pass 6: bad root"
[ "$rc" -eq 0 ] && ok "missing root exits 0" || no "missing root exits 0 (rc=$rc)"
AUTODREAM_PRUNE_ROOTS="" "$BIN" "$OUT" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "unset roots exits 0 and does nothing" || no "unset roots exits 0 (rc=$rc)"

# ==== pass 7: a trash that fails falls back to git, and one that works leaves the dir gone ======
make_repo trashfail; OUT="$T/out7"; mkdir -p "$OUT"
worktree t1; commit_in t1; push t1; pr t1 MERGED "$(tip t1)"; age "$(wt t1)"
TRASH_FAIL=1 run_prune
echo "== pass 7: trash fails"
expect_removed t1 "trash failing falls back to git worktree remove"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
