#!/bin/bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${COMMENT_RATCHET_REPO:-$(cd "$HERE/.." && pwd)}
COUNT="${COMMENT_COUNT_BIN:-$HERE/../bin/comment-count.sh}"
BASELINE="$REPO/.comment-baseline"
TAB=$(printf '\t')
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
file would go up, unless --allow-increase is also given. Anything that cannot be
read, parsed, compared or written is a failure, never a pass.
EOF
}

complain() { printf '%s\n' "$*" >&2; }

rows_valid() {
  awk -F'\t' -v numcol="$2" '
    NF != 2 { bad = 1; next }
    $numcol !~ /^[0-9]+$/ { bad = 1; next }
    { key = (numcol == 1) ? $2 : $1; if (seen[key]++) bad = 1 }
    END { exit bad ? 1 : 0 }
  ' "$1"
}

baseline_problem() {
  [ -e "$BASELINE" ] || { echo "$BASELINE does not exist"; return 0; }
  [ -f "$BASELINE" ] || { echo "$BASELINE is not a file"; return 0; }
  [ -r "$BASELINE" ] || { echo "$BASELINE cannot be read"; return 0; }
  [ -s "$BASELINE" ] || { echo "$BASELINE is empty, so every increase would pass"; return 0; }
  rows_valid "$BASELINE" 2 || { echo "$BASELINE has a row that is not <path><TAB><count>, or a path twice"; return 0; }
  return 1
}

collect_counts() {
  local out=$1 rc
  bash "$COUNT" --repo "$REPO" > "$out"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    complain "comment-count failed (exit $rc)"
    return 1
  fi
  [ -s "$out" ] || { complain "comment-count listed no files"; return 1; }
  rows_valid "$out" 1 || { complain "comment-count printed a row that is not <count><TAB><path>"; return 1; }
}

over_baseline() {
  awk -F'\t' -v base="$1" '
    BEGIN {
      while ((rc = (getline line < base)) > 0) { split(line, f, "\t"); allow[f[1]] = f[2] + 0 }
      if (rc < 0) { err = 3; exit }
      close(base)
    }
    ($1 + 0) > (allow[$2] + 0) { print "    " $2 ": " $1 " comment lines, baseline allows " (allow[$2] + 0); found = 1 }
    END { if (err) exit err; exit found ? 1 : 0 }
  ' "$2"
}

below_baseline() {
  awk -F'\t' -v counts="$2" '
    BEGIN {
      while ((rc = (getline line < counts)) > 0) { split(line, f, "\t"); cur[f[2]] = f[1] + 0 }
      if (rc < 0) { err = 3; exit }
      close(counts)
    }
    ($2 + 0) > (cur[$1] + 0) { n++ }
    END { if (err) exit err; print n + 0 }
  ' "$1"
}

new_baseline_rows() {
  awk -F'\t' '($1 + 0) > 0 { print $2 "\t" $1 }' "$1" > "$2" || return 1
  LC_ALL=C sort -o "$2" "$2"
}

update_baseline() {
  local allow=$1 tmp counts rows rc
  counts=$(mktemp "${TMPDIR:-/tmp}/comment-counts.XXXXXX") || { complain "cannot make a scratch file"; return 1; }
  rows=$(mktemp "${TMPDIR:-/tmp}/comment-rows.XXXXXX") || { rm -f "$counts"; complain "cannot make a scratch file"; return 1; }
  tmp=$(mktemp "$REPO/.comment-baseline.XXXXXX") || { rm -f "$counts" "$rows"; complain "cannot make a temp file beside $BASELINE"; return 1; }
  rc=0
  update_into "$allow" "$counts" "$rows" "$tmp" || rc=$?
  rm -f "$counts" "$rows"
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return 1; }
}

update_into() {
  local allow=$1 counts=$2 rows=$3 tmp=$4 problem up rc total files
  collect_counts "$counts" || return 1
  new_baseline_rows "$counts" "$rows" || { complain "could not build the new baseline rows"; return 1; }
  [ -s "$rows" ] || { complain "no file has a comment left, so there is nothing to ratchet; delete the ratchet on purpose, not through --update"; return 1; }
  cp "$rows" "$tmp" || { complain "could not write $tmp"; return 1; }
  if [ "$allow" != 1 ]; then
    if problem=$(baseline_problem); then
      complain "cannot compare against the old baseline: $problem (pass --allow-increase to replace it)"
      return 1
    fi
    up=$(awk -F'\t' -v base="$BASELINE" '
      BEGIN {
        while ((rc = (getline line < base)) > 0) { split(line, f, "\t"); old[f[1]] = f[2] + 0 }
        if (rc < 0) { err = 3; exit }
        close(base)
      }
      ($2 + 0) > (old[$1] + 0) { print $1 ": " (old[$1] + 0) " -> " $2; found = 1 }
      END { if (err) exit err; exit found ? 1 : 0 }
    ' "$rows")
    rc=$?
    if [ "$rc" -eq 1 ]; then
      printf 'refusing to raise the baseline (pass --allow-increase):\n%s\n' "$up" >&2
      return 1
    fi
    [ "$rc" -eq 0 ] || { complain "comparing against the old baseline failed (exit $rc)"; return 1; }
  fi
  total=$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "$tmp") || { complain "could not total the new baseline"; return 1; }
  files=$(wc -l < "$tmp" | tr -d ' ') || { complain "could not count the new baseline"; return 1; }
  [ -n "$total" ] && [ -n "$files" ] || { complain "the new baseline totals came back empty"; return 1; }
  [ ! -d "$BASELINE" ] || { complain "$BASELINE is a directory, so nothing can be written there"; return 1; }
  mv "$tmp" "$BASELINE" || { complain "could not replace $BASELINE"; return 1; }
  cmp -s "$rows" "$BASELINE" || { complain "$BASELINE does not hold the new baseline after the move"; return 1; }
  echo "wrote $BASELINE ($total comment lines across $files files)"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --update) update_baseline "$([ "${2:-}" = --allow-increase ] && echo 1 || echo 0)"; exit $? ;;
esac

gitq() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"; }

mkrepo() {
  local fx
  fx=$(mktemp -d) || return 1
  gitq init -q "$fx" || return 1
  printf '%s' "$fx"
}

track() { gitq -C "$1" add -A; }

stray_temps() { find "$1" -maxdepth 1 -name '.comment-baseline.*' | wc -l | tr -d ' '; }

ratchet_in() {
  local fx=$1
  shift
  COMMENT_RATCHET_REPO="$fx" COMMENT_RATCHET_INNER=1 bash "$HERE/comment-ratchet.sh" "$@"
}

num() { bash "$COUNT" "$1" | cut -f1; }

not_root() { [ "$(id -u)" -ne 0 ]; }

fail_naming() {
  local err rc
  err=$(bash "$COUNT" "$1" 2>&1 >/dev/null)
  rc=$?
  printf '%s %s' "$rc" "$(printf '%s' "$err" | grep -c "$(basename "$1")")"
}

same_as() { [ "$(cksum < "$1")" = "$2" ]; }

counter_fixtures() {
  local d rc
  d=$(mktemp -d)
  printf '%s\n' '#!/bin/bash' '# a comment' '# shellcheck disable=SC2086' 'echo hi # trailing' \
    'cat <<EOF' '# inside a heredoc' 'EOF' "cat <<'X'" '# quoted heredoc' 'X' \
    'cat <<-T' "$(printf '\t# dash heredoc')" "$(printf '\tT')" '  # indented comment' 'n=$((1<<2))' > "$d/a.sh"
  eq "$(num "$d/a.sh")" 2 "shell: shebang, shellcheck, heredoc bodies and trailing comments are not counted"
  printf '%s\n' '#!/usr/bin/env python3' '# one' 'x = 1  # trailing' '# noqa: E501' '    # two' > "$d/b.py"
  eq "$(num "$d/b.py")" 2 "python: shebang and noqa are not counted"
  printf '%s\n' '// one' '/* two' ' * three */' '// @ts-expect-error' 'const x = 1 // trailing' > "$d/c.ts"
  eq "$(num "$d/c.ts")" 3 "ts: line and block comments count, a @ts directive does not"
  printf '%s\n' '#!/bin/bash' 'echo no comments' > "$d/noext"
  eq "$(num "$d/noext")" 0 "a bash shebang without an extension is read as shell"
  printf '%s\n' '# not code' > "$d/notes.md"
  eq "$(bash "$COUNT" "$d/notes.md")" "" "markdown is not code"
  printf '%s\n' 'echo "see <<EOF in the docs"' "echo 'a <<WORD in single quotes'" 'echo x # see <<EOF' '# still counted' > "$d/q.sh"
  eq "$(num "$d/q.sh")" 1 "a heredoc marker inside quotes or a trailing comment does not start a heredoc"

  printf '%s\n' '#' '# x' '  #' 'echo a' > "$d/bare.sh"
  eq "$(num "$d/bare.sh")" 3 "shell: a bare # line is a comment line"
  printf '%s\n' '((x=1<<bits))' '# real comment' 'echo done' > "$d/shift.sh"
  eq "$(num "$d/shift.sh")" 1 "a shift inside (( )) is not a heredoc, so the comment after it counts"
  printf '%s\n' 'cat <<EOF-END' '# body' 'EOF-END' '# real comment' > "$d/dashword.sh"
  eq "$(num "$d/dashword.sh")" 1 "a heredoc delimiter with a dash ends at the whole word"
  printf '%s\n' 'cat <<A <<B' '# a body' 'A' '# b body' 'B' '# real comment' > "$d/two.sh"
  eq "$(num "$d/two.sh")" 1 "two heredocs on one command are both skipped"
  printf '%s\n' "x='" '# data' "'" '# real comment' > "$d/mlstr.sh"
  eq "$(num "$d/mlstr.sh")" 1 "a comment-looking line inside a multiline shell string is data"
  printf '%s\n' 's = """' '# data' '"""' '# real comment' > "$d/doc.py"
  eq "$(num "$d/doc.py")" 1 "a comment-looking line inside a python triple-quoted string is data"
  printf '%s\n' 'const t = `' '// inside a template' '`;' '// real comment' > "$d/tmpl.ts"
  eq "$(num "$d/tmpl.ts")" 1 "a template literal line that starts with // is data, not a comment"
  printf '%s\n' 'const t = `' '/* data' '`;' '' > "$d/phantom-a.ts"
  printf '%s\n' 'const t = `' '/* data' '`;' '// real comment' > "$d/phantom-b.ts"
  eq "$(num "$d/phantom-a.ts") $(num "$d/phantom-b.ts")" "0 1" "a /* inside a template is data: it counts nothing and a real comment added after it counts one"
  printf '%s\n' '/**' ' * doc' ' */' 'const a = b' '  * c;' '// real comment' > "$d/block.ts"
  eq "$(num "$d/block.ts")" 4 "a line that starts with * outside a block is code, not a comment"
  printf '%s\n' '/*' '*/' > "$d/block-a.ts"
  printf '%s\n' '/*' 'new comment' '*/' > "$d/block-b.ts"
  printf '%s\n' '/*' '' '*/' > "$d/block-c.ts"
  eq "$(num "$d/block-a.ts") $(num "$d/block-b.ts") $(num "$d/block-c.ts")" "2 3 2" "a line added inside a closed block raises the count, starred or not, and a blank one does not"
  printf '%s\n' '/* a */ const x = 1;' 'const y = 2; /* b' ' * c' ' */' > "$d/block-after-code.ts"
  eq "$(num "$d/block-after-code.ts")" 3 "a block that opens after code is not counted on its opening line, its starred lines are"
  printf '%s\n' 'const el = (' '  <div>' '    {/* explain the layout' '        across two lines */}' '    {// one line' '    }' '  </div>' ');' > "$d/jsx.tsx"
  eq "$(num "$d/jsx.tsx")" 3 "a JSX comment that starts a line with {/* or {// is a comment line"
  printf '%s\n' 'export const gitignore = `' 'node_modules/' '/*.log' '`;' 'export function a() {}' 'export function b() {}' '/**' ' * Writes the files.' ' */' > "$d/glob-base.ts"
  printf '%s\n' 'export const gitignore = `' 'node_modules/' '/*.log' '`;' 'export function a() {}' '/* new real comment */' 'export function b() {}' '/**' ' * Writes the files.' ' */' > "$d/glob-added.ts"
  eq "$(num "$d/glob-base.ts") $(num "$d/glob-added.ts")" "3 4" "a /*-glob line opens no block, so a real comment added after it raises the count"
  printf '/*tight*/ const x = 1;\n' > "$d/tight.ts"
  eq "$(num "$d/tight.ts")" 1 "a comment closed on its own line counts without a space after the opener"
  printf '\xef\xbb\xbf// first-line comment\n' > "$d/bom.ts"
  eq "$(num "$d/bom.ts")" 1 "a byte order mark does not hide a comment on the first line"
  printf '%s\n' 'const r = /[/*]/.test(v);' 'const o = {a: 1} / 2;' "const s = '// not a comment';" '// real comment' > "$d/midline.ts"
  eq "$(num "$d/midline.ts")" 1 "a slash, regex or string in the middle of a line never matters, only line starts are read"
  printf '%s\n' '#!/usr/bin/env node' '// real comment' > "$d/shebang.ts"
  eq "$(num "$d/shebang.ts")" 1 "a hashbang line is not a comment"
  printf '// one\r\n/* two\r\n * three\r\n */\r\n' > "$d/crlf.ts"
  eq "$(num "$d/crlf.ts")" 4 "CRLF line endings read the same"
  printf '%s\n' '/* never closed' ' still comment' > "$d/open.ts"
  eq "$(fail_naming "$d/open.ts")" "1 1" "an unclosed block is a syntax error: the counter fails and names the file"

  printf '%s\n' '# pragmatism matters' '# shellcheck sourced from here' '# shellcheck disable=SC2086' '# shellcheck source=/dev/null' '# shellcheck shell=bash' > "$d/dir.sh"
  eq "$(num "$d/dir.sh")" 2 "shell: only the exact shellcheck disable=, source= and shell= forms are exempt"
  printf '%s\n' '# pragmatism matters' '# noqa' '# noqa: E501' '# pragma: no cover' '# type: ignore[attr-defined]' '# noqanother' > "$d/dir.py"
  eq "$(num "$d/dir.py")" 2 "python: only the exact noqa, pragma: and type: ignore forms are exempt"
  printf '%s\n' '// oxlinting keeps us honest' '// oxlint-disable-next-line no-x' '// oxlint-disable' '// @ts-ignore' '// @ts-expect-error: why' '// @ts-nocheckish' > "$d/dir.ts"
  eq "$(num "$d/dir.ts")" 2 "ts: only the exact @ts-expect-error, @ts-ignore and oxlint-disable forms are exempt"

  printf '%s\n' '// one' > "$d/types.d.ts"
  eq "$(num "$d/types.d.ts")" 1 "a declaration file is counted like any other"

  printf '%s\n' 'const x = 1; /* opens after code' 'an unstarred body line' '*/' > "$d/after-a.ts"
  printf '%s\n' 'const x = 1; /* opens after code' 'an unstarred body line' 'a new body line' '*/' > "$d/after-b.ts"
  eq "$(num "$d/after-a.ts") $(num "$d/after-b.ts")" "2 3" "a block that opens after code counts its unstarred body lines, so one added inside it is seen"
  printf '%s\n' '/*Copyright 2026' 'one body line' '*/' > "$d/tight-a.ts"
  printf '%s\n' '/*Copyright 2026' 'one body line' 'two body lines' '*/' > "$d/tight-b.ts"
  printf '%s\n' '/*eslint-env node' 'one body line' '*/' > "$d/tight-c.ts"
  eq "$(num "$d/tight-a.ts") $(num "$d/tight-b.ts") $(num "$d/tight-c.ts")" "3 4 3" "a block opened with no space after /*, closed on a later line, counts every line, so a body line added inside it is seen"
  printf '%s\n' 'const t = `' '/* data' 'more data' '*/' '`;' > "$d/data-a.ts"
  printf '%s\n' 'const t = `' '/* data' '`;' > "$d/data-b.ts"
  eq "$(num "$d/data-a.ts") $(num "$d/data-b.ts")" "0 0" "template literal data that looks like a block counts nothing, so deleting a data line leaves no slack for a real comment"
  printf '%s\n' '<p>// shown as text</p>;' > "$d/jsx-text.tsx"
  printf '%s\n' 'const el = (' '  <p>' '    // shown as text' '  </p>' ');' > "$d/jsx-text-b.tsx"
  eq "$(num "$d/jsx-text.tsx") $(num "$d/jsx-text-b.tsx")" "0 0" "JSX text that starts with // is text, not a comment"
  printf '%s\n' 'const x = ;' > "$d/syntax.ts"
  eq "$(fail_naming "$d/syntax.ts")" "1 1" "a JS or TS file that will not parse fails and names the file"
  printf '%s\n' 'const el = (' '  <div>' '    { /* spaced */ }' '    {  // spaced line' '    }' '  </div>' ');' > "$d/jsx-space.tsx"
  eq "$(num "$d/jsx-space.tsx")" 2 "a JSX comment with whitespace after the brace is a comment line"
  printf 'const a = 1;\xe2\x80\xa8// first\xe2\x80\xa8// second\xe2\x80\xa8' > "$d/sep.ts"
  printf 'const a = 1;\xe2\x80\xa9// first\xe2\x80\xa9' > "$d/sep2.ts"
  eq "$(num "$d/sep.ts") $(num "$d/sep2.ts")" "2 1" "U+2028 and U+2029 end a line like a newline"
  printf '%s\n' 'const a: number = 1;' > "$d/typed.js"
  printf '%s\n' 'const a: number = 1;' > "$d/typed.ts"
  eq "$(fail_naming "$d/typed.js") $(num "$d/typed.ts")" "1 1 0" "a .js file with TypeScript syntax fails, the same text in .ts counts"
  printf '%s\n' 'import { a } from "./a.js";' '// real comment' 'export const b = a;' > "$d/esm.js"
  eq "$(num "$d/esm.js")" 1 "a .js file written as an ES module is read"
  printf '%s\n' 'const s = "\xff";' > "$d/bad-utf8.ts"
  printf 'const s = "\xff";\n' > "$d/bad-utf8.ts"
  eq "$(fail_naming "$d/bad-utf8.ts")" "1 1" "a file that is not valid UTF-8 fails and names the file"
  printf '%s\n' 'const a: number = 1;' > "$d/typed.jsx"
  eq "$(fail_naming "$d/typed.jsx")" "1 1" "a .jsx file with TypeScript syntax fails like a .js one"
  printf '%s\n' '<!-- legacy' 'let x = 1;' '--> also legacy' > "$d/legacy.js"
  eq "$(num "$d/legacy.js")" 2 "a script with HTML-like comments is read and the comment lines count"
  printf '%s\n' 'function f() {' '  { /* trailing */ let x = 1; }' '}' > "$d/block.js"
  eq "$(num "$d/block.js")" 0 "a comment after code inside a plain block brace is not a JSX comment line"
  COMMENT_COUNT_NODE="$d/no-such-node" bash "$COUNT" "$d/types.d.ts" > "$d/out" 2> "$d/err"
  rc=$?
  eq "$rc $(grep -c node "$d/err") $(wc -c < "$d/out" | tr -d ' ')" "1 1 0" "a missing node fails with a message and counts nothing"
  mkdir -p "$d/bare/bin"
  cp "$REPO/bin/comment-count.sh" "$REPO/bin/comment-count.py" "$REPO/bin/comment-count-js.mjs" "$d/bare/bin/"
  bash "$d/bare/bin/comment-count.sh" "$d/types.d.ts" > "$d/out" 2> "$d/err"
  rc=$?
  eq "$rc $(grep -c 'npm ci' "$d/err") $(wc -c < "$d/out" | tr -d ' ')" "1 1 0" "a missing typescript module fails with a message that says npm ci and counts nothing"

  eq "$(bash "$COUNT" "$d/missing.sh" >/dev/null 2>&1; echo $?)" 1 "a file that does not exist is an error, not a zero"
  if not_root; then
    printf '%s\n' '# one' > "$d/locked.sh"
    chmod 000 "$d/locked.sh"
    eq "$(bash "$COUNT" "$d/locked.sh" >/dev/null 2>&1; echo $?)" 1 "a file that cannot be read is an error, not a zero"
    chmod 600 "$d/locked.sh"
  fi
  printf '%s\n' 'def broken(:' > "$d/broken.py"
  eq "$(fail_naming "$d/broken.py")" "1 1" "a python file that will not tokenize fails and names the file"
  printf '%s\n' 'if then fi done' '(' > "$d/broken.sh"
  eq "$(fail_naming "$d/broken.sh")" "1 1" "a shell file that will not parse fails and names the file"
  printf '%s\n' '# one' > "$d/needs-shfmt.sh"
  COMMENT_COUNT_SHFMT="$d/no-such-shfmt" bash "$COUNT" "$d/needs-shfmt.sh" > "$d/out" 2> "$d/err"
  rc=$?
  eq "$rc $(grep -c shfmt "$d/err") $(wc -c < "$d/out" | tr -d ' ')" "1 1 0" "a missing shfmt fails with a message and counts nothing"
  rm -rf "$d"
}

enumeration_fixtures() {
  local fx rc
  fx=$(mkrepo) || { bad "make a fixture repo"; return; }
  mkdir "$fx/types"
  printf '%s\n' '// one' > "$fx/types/index.d.ts"
  printf '%s\n' '# one' > "$fx/a.sh"
  track "$fx"
  eq "$(bash "$COUNT" --repo "$fx" | tr '\t' ' ' | tr '\n' ';')" "1 a.sh;1 types/index.d.ts;" "enumeration lists a tracked declaration file"
  printf '%s\n' '# one' > "$fx/tab$TAB.sh"
  track "$fx"
  bash "$COUNT" --repo "$fx" > "$fx/out" 2> "$fx/err"
  rc=$?
  eq "$rc $(grep -c 'tab' "$fx/err")" "1 1" "a tab in a tracked path fails and names it instead of breaking the row format"
  rm -rf "$fx"

  fx=$(mkrepo) || { bad "make a fixture repo"; return; }
  printf '%s\n' '# one' > "$fx/notes.txt"
  ln -s notes.txt "$fx/script.sh"
  printf '%s\n' '# two' > "$fx/top.sh"
  track "$fx"
  bash "$COUNT" --repo "$fx" > "$fx/out" 2> "$fx/err"
  rc=$?
  eq "$rc $(tr '\t\n' ' ;' < "$fx/out")" "0 1 script.sh;1 top.sh;" "a tracked symlink to a file is counted"
  rm -rf "$fx"

  fx=$(mkrepo) || { bad "make a fixture repo"; return; }
  printf '%s\n' '# two' > "$fx/top.sh"
  ln -s nowhere "$fx/dead"
  track "$fx"
  bash "$COUNT" --repo "$fx" > "$fx/out" 2> "$fx/err"
  rc=$?
  eq "$rc $(grep -c 'dead' "$fx/err") $(wc -c < "$fx/out" | tr -d ' ')" "1 1 0" "a tracked symlink that points at nothing fails and names it, whatever its name"
  rm -rf "$fx"

  if not_root; then
    fx=$(mkrepo) || { bad "make a fixture repo"; return; }
    mkdir "$fx/sub"
    printf '%s\n' '# one' > "$fx/sub/a.sh"
    printf '%s\n' '# two' > "$fx/top.sh"
    track "$fx"
    chmod 000 "$fx/sub"
    bash "$COUNT" --repo "$fx" > "$fx/out" 2> "$fx/err"
    rc=$?
    chmod 755 "$fx/sub"
    eq "$rc $(grep -c 'sub/a.sh' "$fx/err") $(wc -c < "$fx/out" | tr -d ' ')" "1 1 0" "a tracked file whose directory cannot be searched fails and names it instead of being skipped"
    rm -rf "$fx"
  fi
}

baseline_fixture() {
  local fx
  fx=$(mkrepo) || return 1
  printf '%s\n' '# one' '# two' > "$fx/a.sh"
  printf '%s\n' '# one' > "$fx/b.sh"
  track "$fx"
  printf '%s\t%s\n' a.sh 2 b.sh 1 > "$fx/.comment-baseline"
  printf '%s' "$fx"
}

ratchet_fixtures() {
  local fx before out rc
  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  out=$(ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc" 0 "a tree at its baseline passes"
  printf '%s\n' '# three' >> "$fx/a.sh"
  out=$(ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc $(printf '%s' "$out" | grep -c 'a.sh: 3 comment lines, baseline allows 2')" "1 1" "a file over its baseline fails and says which"
  printf '%s\n' '# new' > "$fx/new.sh"
  track "$fx"
  out=$(ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc" 1 "a new file with a comment fails (an unlisted file is allowed none)"
  rm -rf "$fx"

  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  : > "$fx/.comment-baseline"
  printf '%s\n' '# new' > "$fx/new.sh"
  track "$fx"
  out=$(ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc" 1 "an empty baseline fails, so an increase cannot ride on it"
  out=$(ratchet_in "$fx" --update 2>&1); rc=$?
  eq "$rc $(wc -c < "$fx/.comment-baseline" | tr -d ' ')" "1 0" "--update refuses to compare against an empty baseline and leaves it alone"
  rm -rf "$fx"

  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  printf '%s\n' 'not a baseline row' > "$fx/.comment-baseline"
  out=$(ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc" 1 "a baseline row that is not <path><TAB><count> fails"
  rm -rf "$fx"

  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  rm -f "$fx/.comment-baseline"
  mkdir "$fx/.comment-baseline"
  out=$(ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc" 1 "a baseline that is a directory fails"
  rm -rf "$fx"

  if not_root; then
    fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
    chmod 000 "$fx/.comment-baseline"
    out=$(ratchet_in "$fx" 2>&1); rc=$?
    eq "$rc" 1 "an unreadable baseline fails the check"
    out=$(ratchet_in "$fx" --update 2>&1); rc=$?
    eq "$rc" 1 "an unreadable baseline stops --update from passing the increase check"
    chmod 600 "$fx/.comment-baseline"
    rm -rf "$fx"
  fi

  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  printf '%s\n' '# three' >> "$fx/a.sh"
  before=$(cksum < "$fx/.comment-baseline")
  out=$(ratchet_in "$fx" --update 2>&1); rc=$?
  eq "$rc $(same_as "$fx/.comment-baseline" "$before" && echo same)" "1 same" "--update refuses an increase and leaves the baseline as it was"
  out=$(ratchet_in "$fx" --update --allow-increase 2>&1); rc=$?
  eq "$rc $(grep -c 'a.sh' "$fx/.comment-baseline")" "0 1" "--update --allow-increase accepts it"
  eq "$(awk -F'\t' '$1 == "a.sh" { print $2 }' "$fx/.comment-baseline")" 3 "and records the new count"
  rm -rf "$fx"
}

failing_tool_fixtures() {
  local fx shim tool before out rc
  for tool in sort mv awk mktemp; do
    fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
    shim=$(mktemp -d)
    printf '#!/bin/bash\nexit 1\n' > "$shim/$tool"
    chmod +x "$shim/$tool"
    printf '%s\n' '# three' > "$fx/c.sh"
    track "$fx"
    before=$(cksum < "$fx/.comment-baseline")
    out=$(PATH="$shim:$PATH" ratchet_in "$fx" --update --allow-increase 2>&1); rc=$?
    eq "$rc $(printf '%s' "$out" | grep -c '^wrote') $(same_as "$fx/.comment-baseline" "$before" && echo same) $(stray_temps "$fx")" "1 0 same 0" "--update fails, says nothing was written and leaves no partial file when $tool fails"
    rm -rf "$fx" "$shim"
  done
  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  shim=$(mktemp -d)
  printf '#!/bin/bash\nexit 1\n' > "$shim/awk"
  chmod +x "$shim/awk"
  out=$(PATH="$shim:$PATH" ratchet_in "$fx" 2>&1); rc=$?
  eq "$rc" 1 "the check fails when the awk comparison itself fails"
  rm -rf "$fx" "$shim"
  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  shim=$(mktemp -d)
  real_awk=$(command -v awk)
  printf '#!/bin/bash\nfor a; do last=$a; done\ncase "$last" in *.comment-baseline.*) exit 1 ;; esac\nexec %s "$@"\n' "$real_awk" > "$shim/awk"
  chmod +x "$shim/awk"
  printf '%s\n' '# three' > "$fx/c.sh"
  track "$fx"
  before=$(cksum < "$fx/.comment-baseline")
  out=$(PATH="$shim:$PATH" ratchet_in "$fx" --update --allow-increase 2>&1); rc=$?
  eq "$rc $(printf '%s' "$out" | grep -c '^wrote') $(same_as "$fx/.comment-baseline" "$before" && echo same)" "1 0 same" "--update fails before publishing when the final totalling awk fails"
  rm -rf "$fx" "$shim"

  fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
  rm -f "$fx/.comment-baseline"
  mkdir "$fx/.comment-baseline"
  out=$(ratchet_in "$fx" --update --allow-increase 2>&1); rc=$?
  eq "$rc $(printf '%s' "$out" | grep -c '^wrote') $([ -d "$fx/.comment-baseline" ] && ls -A "$fx/.comment-baseline" | wc -l | tr -d ' ')" "1 0 0" "--update --allow-increase onto a directory fails and moves nothing into it"
  rm -rf "$fx"

  if not_root; then
    fx=$(baseline_fixture) || { bad "make a fixture repo"; return; }
    printf '%s\n' '# three' > "$fx/c.sh"
    track "$fx"
    before=$(cksum < "$fx/.comment-baseline")
    chmod 555 "$fx"
    out=$(ratchet_in "$fx" --update --allow-increase 2>&1); rc=$?
    chmod 755 "$fx"
    eq "$rc $(printf '%s' "$out" | grep -c '^wrote') $(same_as "$fx/.comment-baseline" "$before" && echo same)" "1 0 same" "--update fails when the directory will not take a temp file"
    rm -rf "$fx"
  fi
}

lint_coverage_fixture() {
  local dirs dir f covered missing=""
  dirs=$(node -e 'const s = require(process.argv[1]).scripts.lint.split(/\s+/); process.stdout.write(s.filter((w) => !w.startsWith("-") && w !== "oxlint" && w !== "npm").join("\n"))' "$REPO/package.json" 2>/dev/null) || { bad "read the lint script from package.json"; return; }
  while IFS= read -r f; do
    case "$f" in node_modules/*) continue ;; esac
    covered=0
    for dir in $dirs; do
      case "$f" in "$dir"/*|"$dir") covered=1 ;; esac
    done
    [ "$covered" -eq 1 ] || missing="$missing $f"
  done <<EOF
$(git -C "$REPO" ls-files '*.js' '*.mjs' '*.cjs' '*.jsx' '*.ts' '*.mts' '*.cts' '*.tsx')
EOF
  eq "$missing" "" "every tracked JS and TS file is under a path the lint script covers"
}

counter_exit_fixtures() {
  local d
  d=$(mktemp -d)
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
  local problem counts over rc slack
  if problem=$(baseline_problem); then
    bad "$problem (run tests/comment-ratchet.sh --update --allow-increase)"
    return
  fi
  counts=$(mktemp "${TMPDIR:-/tmp}/comment-counts.XXXXXX") || { bad "make a scratch file"; return; }
  if ! collect_counts "$counts"; then
    bad "the counter ran and listed the tracked files"
    rm -f "$counts"
    return
  fi
  over=$(over_baseline "$BASELINE" "$counts")
  rc=$?
  case "$rc" in
    0) ok "no file has more comment lines than .comment-baseline allows" ;;
    1)
      bad "comment lines went up (delete them, move a decision into docs/adr/, or run tests/comment-ratchet.sh --update --allow-increase):"
      printf '%s\n' "$over"
      ;;
    *) bad "comparing the counts with .comment-baseline failed (exit $rc)" ;;
  esac
  if slack=$(below_baseline "$BASELINE" "$counts"); then
    [ "$slack" -eq 0 ] || echo "  note - $slack file(s) are below their baseline; tighten it with tests/comment-ratchet.sh --update"
  else
    bad "counting the files below their baseline failed"
  fi
  rm -f "$counts"
}

if [ -z "${COMMENT_RATCHET_INNER:-}" ]; then
  counter_fixtures
  lint_coverage_fixture
  enumeration_fixtures
  ratchet_fixtures
  failing_tool_fixtures
  counter_exit_fixtures
fi
ratchet
echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
