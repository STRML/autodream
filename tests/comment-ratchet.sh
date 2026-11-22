#!/bin/bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
COUNT="${COMMENT_COUNT_BIN:-$REPO/bin/comment-count.sh}"
BASELINE="$REPO/.comment-baseline"
pass=0
fail=0
ok(){ pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
bad(){ fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got [$1] want [$2])"; fi; }

usage() {
  cat <<'EOF'
usage: tests/comment-ratchet.sh [--update [--allow-increase]]

Without flags: checks the counter against fixtures, then fails if any tracked
code file has more real comment lines than .comment-baseline allows (a file not
listed is allowed 0).
--update rewrites .comment-baseline from the current tree. It refuses when any
file would go up, unless --allow-increase is also given.
EOF
}

current_counts() {
  local out rc
  out=$(bash "$COUNT" --repo "$REPO")
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    printf 'comment-count.sh failed (exit %s, %s lines of output)\n' "$rc" "$(printf '%s' "$out" | grep -c .)" >&2
    return 1
  fi
  printf '%s\n' "$out" | awk -F'\t' '$1 > 0'
}

update_baseline() {
  local allow=$1 tmp counts
  counts=$(current_counts) || exit 1
  tmp=$(mktemp "$REPO/.comment-baseline.XXXXXX")
  printf '%s\n' "$counts" | awk -F'\t' 'NF == 2 {print $2 "\t" $1}' | sort > "$tmp"
  if [ "$allow" != 1 ] && [ -f "$BASELINE" ]; then
    local up
    up=$(awk -F'\t' 'NR==FNR { base[$1] = $2; next } ($2 + 0) > (base[$1] + 0) { print $1 ": " (base[$1] + 0) " -> " $2 }' "$BASELINE" "$tmp")
    if [ -n "$up" ]; then
      rm -f "$tmp"
      printf 'refusing to raise the baseline (pass --allow-increase):\n%s\n' "$up" >&2
      exit 1
    fi
  fi
  mv "$tmp" "$BASELINE"
  echo "wrote $BASELINE ($(awk -F'\t' '{s += $2} END {print s + 0}' "$BASELINE") comment lines across $(wc -l < "$BASELINE" | tr -d ' ') files)"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --update) update_baseline "$([ "${2:-}" = --allow-increase ] && echo 1 || echo 0)"; exit 0 ;;
esac

fixtures() {
  local d
  d=$(mktemp -d)
  printf '%s\n' '#!/bin/bash' '# a comment' '# shellcheck disable=SC2086' 'echo hi # trailing' \
    'cat <<EOF' '# inside a heredoc' 'EOF' "cat <<'X'" '# quoted heredoc' 'X' \
    'cat <<-T' "$(printf '\t# dash heredoc')" "$(printf '\tT')" '  # indented comment' 'n=$((1<<2))' > "$d/a.sh"
  eq "$(bash "$COUNT" "$d/a.sh" | cut -f1)" 2 "shell: shebang, shellcheck, heredoc bodies and trailing comments are not counted"
  printf '%s\n' '#!/usr/bin/env python3' '# one' 'x = 1  # trailing' '# noqa: E501' '    # two' > "$d/b.py"
  eq "$(bash "$COUNT" "$d/b.py" | cut -f1)" 2 "python: shebang and noqa are not counted"
  printf '%s\n' '// one' '/* two' ' three */' '// @ts-expect-error' 'const x = 1 // trailing' > "$d/c.ts"
  eq "$(bash "$COUNT" "$d/c.ts" | cut -f1)" 3 "ts: line and block comments count, a @ts directive does not"
  printf '%s\n' '#!/bin/bash' 'echo no comments' > "$d/noext"
  eq "$(bash "$COUNT" "$d/noext" | cut -f1)" 0 "a bash shebang without an extension is read as shell"
  printf '%s\n' '# not code' > "$d/notes.md"
  eq "$(bash "$COUNT" "$d/notes.md")" "" "markdown is not code"
  printf '%s\n' 'echo "see <<EOF in the docs"' "echo 'a <<WORD in single quotes'" 'echo x # see <<EOF' '# still counted' > "$d/q.sh"
  eq "$(bash "$COUNT" "$d/q.sh" | cut -f1)" 1 "a heredoc marker inside quotes or a trailing comment does not start a heredoc"
  printf '#!/bin/bash\nexit 3\n' > "$d/broken-counter"
  if COMMENT_COUNT_BIN="$d/broken-counter" COMMENT_RATCHET_INNER=1 bash "$HERE/comment-ratchet.sh" > "$d/out" 2>&1; then
    bad "a counter that fails makes the ratchet fail"
  else
    ok "a counter that fails makes the ratchet fail"
  fi
  printf '#!/bin/bash\nexit 0\n' > "$d/silent-counter"
  if COMMENT_COUNT_BIN="$d/silent-counter" COMMENT_RATCHET_INNER=1 bash "$HERE/comment-ratchet.sh" > "$d/out" 2>&1; then
    bad "a counter that prints nothing makes the ratchet fail"
  else
    ok "a counter that prints nothing makes the ratchet fail"
  fi
  rm -rf "$d"
}

ratchet() {
  [ -f "$BASELINE" ] || { bad ".comment-baseline exists (run tests/comment-ratchet.sh --update)"; return; }
  local counts over
  if ! counts=$(current_counts); then
    bad "the counter ran and listed the tracked files"
    return
  fi
  over=$(printf '%s\n' "$counts" | awk -F'\t' 'NR==FNR { base[$1] = $2; next } NF == 2 && ($1 + 0) > (base[$2] + 0) { print "    " $2 ": " $1 " comment lines, baseline allows " (base[$2] + 0) }' "$BASELINE" -)
  if [ -z "$over" ]; then
    ok "no file has more comment lines than .comment-baseline allows"
  else
    bad "comment lines went up (delete them, move a decision into docs/adr/, or run tests/comment-ratchet.sh --update --allow-increase):"
    printf '%s\n' "$over"
  fi
  local slack
  slack=$(printf '%s\n' "$counts" | awk -F'\t' 'NR==FNR { cur[$2] = $1; next } ($2 + 0) > (cur[$1] + 0) { n++ } END { print n + 0 }' - "$BASELINE")
  [ "$slack" -eq 0 ] || echo "  note - $slack file(s) are below their baseline; tighten it with tests/comment-ratchet.sh --update"
}

[ -n "${COMMENT_RATCHET_INNER:-}" ] || fixtures
ratchet
echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
