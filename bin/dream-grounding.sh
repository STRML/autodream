#!/bin/bash
set -uo pipefail

report="${1:-}"; out="${2:-}"; pins="${3:-}"
if [ -z "$report" ] || [ -z "$out" ]; then
  echo "usage: $0 <report.md> <out.json> [pin-projects.tsv]" >&2
  exit 2
fi
[ -s "$report" ] || { echo "dream-grounding: report not readable: $report" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "dream-grounding: jq not available" >&2; exit 2; }

MAX="${AUTODREAM_GROUNDING_MAX:-100}"
case "$MAX" in ''|*[!0-9]*) MAX=100 ;; esac
export GIT_OPTIONAL_LOCKS=0

skills=$(mktemp "${TMPDIR:-/tmp}/grounding-skills.XXXXXX") || exit 2
claims=$(mktemp "${TMPDIR:-/tmp}/grounding-claims.XXXXXX") || exit 2
trap 'rm -f "$skills" "$claims" "$out.tmp"' EXIT

skill_dirs="${AUTODREAM_SKILL_DIRS:-$HOME/.claude/skills:$HOME/.claude/plugins}"
IFS=: read -r -a _dirs <<< "$skill_dirs"
for d in ${_dirs[@]+"${_dirs[@]}"}; do
  [ -d "$d" ] || continue
  find -L "$d" -maxdepth 7 -name SKILL.md -path '*/skills/*' -print 2>/dev/null \
    | while IFS= read -r f; do basename "$(dirname "$f")"; done
done >> "$skills"
if [ -n "${AUTODREAM_SKILL_INVENTORY_FILE:-}" ] && [ -r "$AUTODREAM_SKILL_INVENTORY_FILE" ]; then
  cut -f1 "$AUTODREAM_SKILL_INVENTORY_FILE" >> "$skills"
fi
sort -u "$skills" -o "$skills"
skills_known=$(grep -c . "$skills" || true)

settings_files="${AUTODREAM_SETTINGS_FILES:-$HOME/.claude/settings.json:$HOME/.claude/settings.local.json}"
allow=""; allow_files=0
IFS=: read -r -a _sf <<< "$settings_files"
for f in ${_sf[@]+"${_sf[@]}"}; do
  [ -r "$f" ] || continue
  entries=$(jq -r '(.permissions.allow // [])[]? | strings' "$f" 2>/dev/null) || continue
  allow_files=$((allow_files + 1))
  allow="$allow"$'\n'"$entries"
done
allow_count=$(printf '%s\n' "$allow" | grep -c . || true)

repos=""
if [ -n "$pins" ] && [ -r "$pins" ]; then
  repos=$(awk -F'\t' 'NF >= 2 && $2 != "" { print $2 }' "$pins")
fi
if [ -n "${AUTODREAM_TRIAGE_REPOS:-}" ]; then
  repos="$repos"$'\n'"$(printf '%s' "$AUTODREAM_TRIAGE_REPOS" | tr ':' '\n')"
fi
git_repos=""
while IFS= read -r r; do
  [ -n "$r" ] && git -C "$r" rev-parse --git-dir >/dev/null 2>&1 || continue
  git_repos="$git_repos$r"$'\n'
done <<< "$(printf '%s\n' "$repos" | sort -u)"

spans=$(awk '
  { s = $0; sk = (tolower($0) ~ /skill/) ? 1 : 0
    while (match(s, /`[^`]+`/)) {
      tok = substr(s, RSTART + 1, RLENGTH - 2); gsub(/\t/, " ", tok)
      printf "%d\t%d\t%s\n", NR, sk, tok
      s = substr(s, RSTART + RLENGTH)
    } }' "$report")

emit() {
  jq -nc --arg k "$1" --arg c "$2" --arg s "$3" --arg e "$4" --argjson l "$5" \
    '{kind:$k, claim:$c, status:$s, evidence:$e, line:$l}' >> "$claims"
}

check_skill() {
  local name="$1" bare="${1##*:}"
  if [ "$skills_known" -eq 0 ]; then
    emit skill "$name" unknown "no installed skill could be listed (searched: $skill_dirs, and the adapters' inventories)" "$2"
  elif grep -qxF -e "$name" -e "$bare" "$skills"; then
    emit skill "$name" present "an installed skill named $bare exists" "$2"
  else
    emit skill "$name" absent "no installed skill is named $bare (searched $skills_known user and plugin skill names under: $skill_dirs, and the adapters' inventories; built-in and project-local skills are not searched)" "$2"
  fi
}

check_allow() {
  if [ "$allow_files" -eq 0 ]; then
    emit allowlist "$1" unknown "no readable settings file with a permissions block among: $settings_files" "$2"
  elif printf '%s\n' "$allow" | grep -qxF -- "$1"; then
    emit allowlist "$1" present "permissions.allow holds this exact string" "$2"
  else
    emit allowlist "$1" absent "permissions.allow ($allow_count entries in $allow_files user-level file(s)) does not hold this exact string; a broader rule or a project setting may still allow it" "$2"
  fi
}

check_sha() {
  local r subj
  if [ -z "$git_repos" ]; then
    emit sha "$1" unknown "no git repository to look in (set AUTODREAM_TRIAGE_REPOS)" "$2"
    return
  fi
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    git -C "$r" cat-file -e "$1^{commit}" 2>/dev/null || continue
    subj=$(git -C "$r" log -1 --format='%h %s' "$1" 2>/dev/null)
    emit sha "$1" present "in $r: $subj" "$2"
    return
  done <<< "$git_repos"
  emit sha "$1" absent "not resolved as a unique commit in any of: $(printf '%s' "$git_repos" | tr '\n' ' ')" "$2"
}

classify() {
  local tok="$3"
  case "$tok" in
    Bash\(*\)|Read\(*\)|Edit\(*\)|Write\(*\)|WebFetch\(*\)|mcp__*) check_allow "$tok" "$1"; return ;;
  esac
  if printf '%s' "$tok" | grep -qE '^[0-9a-f]{7,40}$'; then
    [ "${#tok}" -eq 12 ] && return 0
    printf '%s' "$tok" | grep -q '[0-9]' && printf '%s' "$tok" | grep -q '[a-f]' && check_sha "$tok" "$1"
    return 0
  fi
  [ "$2" = "1" ] || return 0
  printf '%s' "$tok" | grep -qE '^[A-Za-z0-9][A-Za-z0-9:_-]{1,62}$' || return 0
  case "$tok" in Read|Write|Edit|Bash|Glob|Grep|Skill|Task|Agent|WebFetch|WebSearch) return 0 ;; esac
  check_skill "$tok" "$1"
}

seen=$'\n'
n=0
truncated=false
while IFS=$'\t' read -r line sk tok; do
  [ -n "$tok" ] || continue
  case "$seen" in *$'\n'"$tok"$'\n'*) continue ;; esac
  seen="$seen$tok"$'\n'
  [ "$n" -lt "$MAX" ] || { truncated=true; break; }
  before=$(wc -l < "$claims" | tr -d ' ')
  classify "$line" "$sk" "$tok"
  [ "$(wc -l < "$claims" | tr -d ' ')" -gt "$before" ] && n=$((n + 1))
done <<< "$spans"

repo_json=$(printf '%s' "$git_repos" | jq -R . | jq -sc 'map(select(length > 0))')
jq -s --arg report "$report" --argjson sk "$skills_known" --argjson al "$allow_count" --argjson repos "$repo_json" --argjson trunc "$truncated" \
  '{report:$report, skills_known:$sk, allowlist_entries:$al, repos:$repos, truncated:$trunc, claims:.}' "$claims" > "$out.tmp" \
  && mv -f "$out.tmp" "$out" || { echo "dream-grounding: could not write $out" >&2; exit 2; }
exit 0
