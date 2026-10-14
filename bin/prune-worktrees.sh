#!/usr/bin/env bash
# prune-worktrees.sh - remove git worktrees and branches whose work has landed.
#
# Sessions leave worktrees under <repo>/.claude/worktrees/ and <repo>/.worktrees/, and
# branches on the remote, long after the PR merged. This runs in the nightly pipeline and
# clears the ones that are provably finished. It deletes branches on a remote, so the bar is
# proof, not a guess: when any check is unclear the item stays and the report says why. A
# wrong keep costs one more night. A wrong delete cannot be undone.
#
# WHAT COUNTS AS FINISHED
#
# A branch is finished when one of these holds, and none of the keep rules below applies:
#   * a PR for it is MERGED and the PR's head commit is the branch tip (so a squash merge
#     counts, and local commits made after the merge do not);
#   * a PR for it is CLOSED unmerged at least AUTODREAM_PRUNE_CLOSED_DAYS ago and the whole
#     branch is on the remote (GitHub keeps refs/pull/N/head, so nothing is lost);
#   * the repo has no origin at all and the tip is an ancestor of the default branch, and
#     is not the default branch's own tip.
#
# WHAT IS KEPT, WHATEVER ELSE IS TRUE
#
#   open-pr         a PR for the branch is open
#   dirty           uncommitted or untracked files in the worktree
#   recent          a file in the worktree or its gitdir changed inside the grace window
#                   (default 12 hours), which also covers a session still running there
#   locked          `git worktree lock`
#   protected       main, master, develop, dev, trunk, release*, and the default branch
#   unmanaged-path  a worktree outside .claude/worktrees and .worktrees
#   gh-unavailable  gh is missing, logged out, or failed, so there is no proof
#   cap             AUTODREAM_PRUNE_MAX removals already happened this run
#
# The remote branch is deleted only while it still points at the tip the proof was made
# for. If someone pushed more since, the local copy goes and the remote branch stays.
#
# The worktree directory goes to the Trash when `trash` exists (it may hold ignored files
# such as .env), otherwise `git worktree remove` deletes it.
#
# Usage:
#   prune-worktrees.sh [--dry-run] <out-dir>
#     writes <out-dir>/worktree-prune.tsv (action, repo, branch, path, reason) and
#     worktree-prune.md, and prints one summary line. Always exits 0 once it has an
#     out-dir, because a pruning problem must not cost the night's report.
#
# Config (env; run.sh sources ~/.claude/autodream/config with `set -a` first):
#   AUTODREAM_PRUNE_ROOTS        colon-separated directories to search for repos (depth 3).
#                                Unset or empty: do nothing. This is the opt-in.
#   AUTODREAM_PRUNE_GRACE_MIN    recent-edit window in minutes                  default 720
#   AUTODREAM_PRUNE_MAX          most removals in one run                       default 25
#   AUTODREAM_PRUNE_CLOSED_DAYS  how long a closed PR must have been closed     default 7
#   AUTODREAM_PRUNE_TRASH        0 to delete with git instead of trash          default 1
#   AUTODREAM_PRUNE_DRY_RUN      1 is the same as --dry-run
set -uo pipefail

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
# Installed copies are symlinks: a merge updates them before install.sh links a new helper.
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

DRY=${AUTODREAM_PRUNE_DRY_RUN:-0}
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
OUT=${1:-}
[ -n "$OUT" ] || { echo "usage: prune-worktrees.sh [--dry-run] <out-dir>" >&2; exit 2; }
mkdir -p "$OUT" || exit 0

ROOTS=${AUTODREAM_PRUNE_ROOTS:-}
GRACE=${AUTODREAM_PRUNE_GRACE_MIN:-720}
MAXN=${AUTODREAM_PRUNE_MAX:-25}
CLOSED_DAYS=${AUTODREAM_PRUNE_CLOSED_DAYS:-7}
_p_is_int "$GRACE" || GRACE=720
_p_is_int "$MAXN" || MAXN=25
_p_is_int "$CLOSED_DAYS" || CLOSED_DAYS=7

TSV="$OUT/worktree-prune.tsv"
MD="$OUT/worktree-prune.md"
: > "$TSV"
N_REMOVED=0; N_KEPT=0; N_SKIPPED=0
NOW=$(date +%s)
CUTOFF=$(TZ=UTC pdate_fmt_epoch $((NOW - CLOSED_DAYS * 86400)) +%Y-%m-%dT%H:%M:%SZ)

GH_OK=0
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then GH_OK=1; fi

row() { # action repo branch path reason
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$TSV"
  case "$1" in
    removed|would-remove) N_REMOVED=$((N_REMOVED + 1)) ;;
    kept) N_KEPT=$((N_KEPT + 1)) ;;
    *) N_SKIPPED=$((N_SKIPPED + 1)) ;;
  esac
}

# ---- per-repo facts ------------------------------------------------------------------------

repo_slug() { # owner/repo from a github.com origin URL, empty otherwise
  local url
  url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || return 0
  case "$url" in
    *github.com[:/]*) url=${url#*github.com[:/]}; url=${url%.git}; printf '%s' "$url" ;;
  esac
}

default_facts() { # sets DEF_NAME DEF_REF DEF_TIP for repo $1
  local repo=$1 b
  DEF_NAME=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || DEF_NAME=""
  DEF_NAME=${DEF_NAME#origin/}
  if [ -z "$DEF_NAME" ]; then
    for b in main master; do
      if git -C "$repo" show-ref --verify -q "refs/heads/$b"; then DEF_NAME=$b; break; fi
    done
  fi
  [ -n "$DEF_NAME" ] || DEF_NAME=$(git -C "$repo" symbolic-ref -q --short HEAD 2>/dev/null) || DEF_NAME=main
  if git -C "$repo" show-ref --verify -q "refs/remotes/origin/$DEF_NAME"; then DEF_REF="refs/remotes/origin/$DEF_NAME"
  else DEF_REF="refs/heads/$DEF_NAME"; fi
  DEF_TIP=$(git -C "$repo" rev-parse -q --verify "$DEF_REF" 2>/dev/null) || DEF_TIP=""
}

is_protected() {
  case "$1" in
    main|master|develop|dev|trunk|release|release-*|release/*|"$DEF_NAME") return 0 ;;
  esac
  return 1
}

# ---- the proof -------------------------------------------------------------------------------

# judge REPO SLUG BRANCH TIP -> VERDICT=finished|keep, WHY
judge() {
  local repo=$1 slug=$2 br=$3 tip=$4 json rsha closed
  VERDICT=keep; WHY="no proof the work landed"
  if [ -z "$slug" ]; then
    if [ -n "$DEF_TIP" ] && [ "$tip" != "$DEF_TIP" ] && git -C "$repo" merge-base --is-ancestor "$tip" "$DEF_REF" 2>/dev/null; then
      VERDICT=finished; WHY="merged into $DEF_NAME (no GitHub remote)"
    fi
    return 0
  fi
  [ "$GH_OK" = 1 ] || { WHY="gh-unavailable"; return 0; }
  json=$(gh pr list -R "$slug" --head "$br" --state all --limit 20 --json number,state,closedAt,headRefOid,url 2>/dev/null) \
    && printf '%s' "$json" | jq -e . >/dev/null 2>&1 || { WHY="gh-unavailable: PR lookup failed"; return 0; }
  if [ "$(printf '%s' "$json" | jq 'any(.[]; .state == "OPEN")')" = true ]; then WHY="open-pr"; return 0; fi
  if [ "$(printf '%s' "$json" | jq --arg t "$tip" 'any(.[]; .state == "MERGED" and .headRefOid == $t)')" = true ]; then
    VERDICT=finished; WHY="PR merged at this tip"; return 0
  fi
  rsha=$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$br" 2>/dev/null) || rsha=""
  closed=$(printf '%s' "$json" | jq -r '[.[] | select(.state == "CLOSED") | .closedAt] | max // empty')
  if [ -n "$closed" ] && [ "$rsha" = "$tip" ] && [[ "$closed" < "$CUTOFF" ]]; then
    VERDICT=finished; WHY="PR closed unmerged on $closed, branch fully on the remote"; return 0
  fi
  return 0
}

# ---- removal ---------------------------------------------------------------------------------

delete_remote() { # repo slug branch tip -> REMOTE_NOTE
  local repo=$1 slug=$2 br=$3 tip=$4 rsha
  REMOTE_NOTE=""
  rsha=$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$br" 2>/dev/null) || rsha=""
  { [ -n "$slug" ] && [ -n "$rsha" ]; } || return 0
  if [ "$rsha" != "$tip" ]; then REMOTE_NOTE="; remote kept: moved since the proof"; return 0; fi
  if gh api -X DELETE "repos/$slug/git/refs/heads/$br" >/dev/null 2>&1; then
    REMOTE_NOTE="; remote deleted"
    git -C "$repo" update-ref -d "refs/remotes/origin/$br" 2>/dev/null
  else
    REMOTE_NOTE="; remote delete failed"
  fi
}

drop_worktree() { # repo path -> 0 when the directory is gone and git forgot it
  local repo=$1 path=$2 err
  if [ "${AUTODREAM_PRUNE_TRASH:-1}" = 1 ] && command -v trash >/dev/null 2>&1; then
    if trash "$path" >/dev/null 2>&1 && [ ! -e "$path" ]; then git -C "$repo" worktree prune; return 0; fi
  fi
  if err=$(git -C "$repo" worktree remove "$path" 2>&1); then return 0; fi
  DROP_ERR=${err%%$'\n'*}
  return 1
}

# remove_item REPO SLUG BRANCH TIP PATH WHY - PATH or BRANCH may be empty.
remove_item() {
  local repo=$1 slug=$2 br=$3 tip=$4 path=$5 why=$6 note=""
  if [ "$N_REMOVED" -ge "$MAXN" ]; then row kept "$repo" "$br" "$path" "cap: $MAXN removals per run reached"; return 0; fi
  if [ "$DRY" = 1 ]; then row would-remove "$repo" "$br" "$path" "$why"; return 0; fi
  if [ -n "$path" ] && ! drop_worktree "$repo" "$path"; then
    row kept "$repo" "$br" "$path" "remove-failed: ${DROP_ERR:-unknown}"; return 0
  fi
  if [ -n "$br" ]; then
    git -C "$repo" branch -D "$br" >/dev/null 2>&1 || note="; local branch delete failed"
    delete_remote "$repo" "$slug" "$br" "$tip"
    note="$note$REMOTE_NOTE"
  fi
  row removed "$repo" "$br" "$path" "$why$note"
}

# ---- the sweep -------------------------------------------------------------------------------

recent_edit() { # worktree path -> 0 when anything in it or its gitdir changed inside the window
  local path=$1 gd hit
  hit=$(find "$path" \( -name .git -o -name node_modules -o -name target \) -prune -o -type f -mmin "-$GRACE" -print -quit 2>/dev/null)
  [ -n "$hit" ] && return 0
  gd=$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  hit=$(find "$gd" -type f -mmin "-$GRACE" -print -quit 2>/dev/null)
  [ -n "$hit" ]
}

sweep_worktree() { # repo slug path head branch flags
  local repo=$1 slug=$2 path=$3 head=$4 br=${5#refs/heads/} flags=$6 st
  case "$path" in
    "$repo"/.claude/worktrees/*|"$repo"/.worktrees/*) ;;
    *) row skipped "$repo" "$br" "$path" "unmanaged-path"; return 0 ;;
  esac
  case "$flags" in *locked*) row kept "$repo" "$br" "$path" "locked"; return 0 ;; esac
  if [ -n "$br" ] && is_protected "$br"; then row kept "$repo" "$br" "$path" "protected"; return 0; fi
  if recent_edit "$path"; then row kept "$repo" "$br" "$path" "recent: edited within ${GRACE} minutes"; return 0; fi
  st=$(git -C "$path" status --porcelain 2>&1) || { row kept "$repo" "$br" "$path" "status-failed"; return 0; }
  [ -z "$st" ] || { row kept "$repo" "$br" "$path" "dirty: uncommitted or untracked files"; return 0; }
  if [ -z "$br" ]; then # detached HEAD
    if [ -n "$DEF_TIP" ] && [ "$head" != "$DEF_TIP" ] && git -C "$repo" merge-base --is-ancestor "$head" "$DEF_REF" 2>/dev/null; then
      remove_item "$repo" "$slug" "" "$head" "$path" "detached at a commit already in $DEF_NAME"
    else
      row kept "$repo" "(detached)" "$path" "no proof the work landed"
    fi
    return 0
  fi
  judge "$repo" "$slug" "$br" "$head"
  if [ "$VERDICT" = finished ]; then remove_item "$repo" "$slug" "$br" "$head" "$path" "$WHY"
  else row kept "$repo" "$br" "$path" "$WHY"; fi
}

sweep_branches() { # repo slug checked-out-branches
  local repo=$1 slug=$2 checked=$3 br tip ct list
  list=$(mktemp "${TMPDIR:-/tmp}/prune-br.XXXXXX") || return 0
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads > "$list"
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    printf '%s\n' "$checked" | grep -qxF -- "$br" && continue
    is_protected "$br" && continue
    tip=$(git -C "$repo" rev-parse -q --verify "refs/heads/$br" 2>/dev/null) || continue
    ct=$(git -C "$repo" log -1 --format=%ct "$tip" 2>/dev/null) || continue
    [ $((NOW - ct)) -ge $((GRACE * 60)) ] || continue
    judge "$repo" "$slug" "$br" "$tip"
    [ "$VERDICT" = finished ] && remove_item "$repo" "$slug" "$br" "$tip" "" "$WHY (no worktree)"
  done < "$list"
  rm -f "$list"
}

sweep_repo() { # repo
  local repo=$1 slug list path head br flags checked="" first=1
  slug=$(repo_slug "$repo")
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo" fetch -q --prune origin >/dev/null 2>&1 || { row skipped "$repo" "" "" "fetch-failed"; return 0; }
  fi
  default_facts "$repo"
  [ "$DRY" = 1 ] || git -C "$repo" worktree prune 2>/dev/null
  list=$(mktemp "${TMPDIR:-/tmp}/prune-wt.XXXXXX") || return 0
  git -C "$repo" worktree list --porcelain | awk -v RS= -F'\n' '{
    path=""; head=""; br=""; fl=""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^worktree /) path = substr($i, 10)
      else if ($i ~ /^HEAD /) head = substr($i, 6)
      else if ($i ~ /^branch /) br = substr($i, 8)
      else if ($i ~ /^locked/) fl = fl "locked,"
      else if ($i ~ /^prunable/) fl = fl "prunable,"
    }
    print path "\037" head "\037" br "\037" fl
  }' > "$list"
  while IFS=$'\037' read -r path head br flags; do
    [ -n "$path" ] || continue
    checked="$checked
${br#refs/heads/}"
    if [ "$first" = 1 ]; then first=0; continue; fi # the main checkout
    sweep_worktree "$repo" "$slug" "$path" "$head" "$br" "$flags"
  done < "$list"
  rm -f "$list"
  sweep_branches "$repo" "$slug" "$checked"
}

if [ -n "$ROOTS" ]; then
  repos=$(mktemp "${TMPDIR:-/tmp}/prune-repos.XXXXXX") || exit 0
  IFS=: read -r -a _roots <<< "$ROOTS"
  for root in "${_roots[@]}"; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 3 -name .git -type d 2>/dev/null
  done | while IFS= read -r g; do dirname "$g"; done | sort -u > "$repos"
  while IFS= read -r repo; do
    # git prints physical worktree paths, so the repo path must be physical too or the
    # managed-path check below rejects every worktree under a symlinked parent (/tmp, iCloud).
    [ -n "$repo" ] && repo=$(cd -P "$repo" 2>/dev/null && pwd -P) && sweep_repo "$repo"
  done < "$repos"
  rm -f "$repos"
fi

{
  printf '# Worktree prune %s%s\n\n' "$(date +%F)" "$([ "$DRY" = 1 ] && echo ' (dry run)')"
  printf 'removed: %s, kept: %s, skipped: %s\n' "$N_REMOVED" "$N_KEPT" "$N_SKIPPED"
  for a in removed would-remove kept skipped; do
    grep -q "^$a	" "$TSV" || continue
    printf '\n## %s\n\n' "$a"
    awk -F'\t' -v a="$a" '$1 == a { printf "- %s `%s`: %s\n", ($4 != "" ? $4 : $2), $3, $5 }' "$TSV"
  done
} > "$MD"

printf 'prune: removed=%s kept=%s skipped=%s%s\n' "$N_REMOVED" "$N_KEPT" "$N_SKIPPED" "$([ "$DRY" = 1 ] && echo ' (dry run)')"
exit 0
