#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: comment-count.sh [--repo DIR] [FILE...]

Prints "<count><TAB><path>" for each code file: the number of real comment
lines in it. With no FILE, counts every tracked file under --repo (default: the
checkout this script lives in) whose language it knows.

A real comment is a full line that is only a comment. Not counted: a shebang,
shellcheck/noqa/type/pragma/@ts/oxlint directives, and any line inside a shell
heredoc. Languages: shell (*.sh, or a file whose first line names bash or sh),
Python (*.py, or a python shebang), JS/TS (*.js, *.ts, *.tsx, *.mjs).
EOF
}

COUNTER='
BEGIN { inhd = 0; c = 0; inblk = 0 }
{
  line = $0
  if (lang == "sh") {
    if (inhd) {
      t = line
      if (hd_dash) sub(/^\t+/, "", t)
      if (t == hd_word) inhd = 0
      next
    }
    if (NR == 1 && line ~ /^#!/) next
    if (line ~ /^[ \t]*#[ \t]*shellcheck[ \t]/) next
    if (line ~ /^[ \t]*#/) { c++; next }
    s = line
    while (match(s, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
      if (substr(s, RSTART + 2, 1) == "<") { s = substr(s, RSTART + 3); continue }
      tok = substr(s, RSTART, RLENGTH)
      hd_dash = (substr(tok, 3, 1) == "-")
      w = tok; sub(/^<<-?[ \t]*/, "", w); gsub(/["\047]/, "", w)
      hd_word = w; inhd = 1
      s = substr(s, RSTART + RLENGTH)
    }
    next
  }
  if (lang == "py") {
    if (NR == 1 && line ~ /^#!/) next
    if (line ~ /^[ \t]*#[ \t]*(noqa|type:|pragma)/) next
    if (line ~ /^[ \t]*#/) c++
    next
  }
  if (inblk) { c++; if (line ~ /\*\//) inblk = 0; next }
  if (line ~ /^[ \t]*\/\/[ \t]*(@ts-|oxlint|eslint)/) next
  if (line ~ /^[ \t]*\/\*/) { c++; if (line !~ /\*\//) inblk = 1; next }
  if (line ~ /^[ \t]*\/\//) c++
}
END { print c }
'

lang_of() {
  case "$1" in
    *.sh) echo sh; return ;;
    *.py) echo py; return ;;
    *.js|*.ts|*.tsx|*.mjs) echo js; return ;;
    *.md|*.json|*.yml|*.yaml|*.html|*.css|*.txt|*.tsv|*.jsonl|*.conf|*.plist|*.example|*.svg|*.png|*.gif|*.jq|*.d.ts) return ;;
  esac
  local first
  first=$(head -n 1 "$1" 2>/dev/null || true)
  case "$first" in
    '#!'*python*) echo py ;;
    '#!'*bash*|'#!'*/sh|'#!'*' sh') echo sh ;;
  esac
}

count_file() {
  local lang
  lang=$(lang_of "$1")
  [ -n "$lang" ] || return 0
  printf '%s\t%s\n' "$(awk -v lang="$lang" "$COUNTER" "$1")" "$1"
}

repo=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --repo) repo=$2; shift 2 ;;
esac

if [ $# -gt 0 ]; then
  for f in "$@"; do count_file "$f"; done
  exit 0
fi

cd "$repo"
git ls-files -z | while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  case "$f" in *.d.ts) continue ;; esac
  count_file "$f"
done | sort -t "$(printf '\t')" -k2,2
