#!/bin/bash

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
SCOPE="$REPO/.github/ci-scope.sh"

pass=0; fail=0
# shellcheck source=/dev/null
. "$HERE/lib-assert.sh"
scope(){ printf '%s\n' "$@" | bash "$SCOPE" 2>/dev/null; }

if [ ! -f "$SCOPE" ]; then
  no ".github/ci-scope.sh exists"
  printf '\npassed: %s   failed: %s\n' "$pass" "$fail"; exit 1
fi

echo "# web-only changes run only the web suite"
assert_eq "$(scope web/app.js web/app.css)" web "the dashboard's own assets"
assert_eq "$(scope bin/autodream_web_data.py tests/autodream-web-data.py)" web "its data layer and tests"
assert_eq "$(scope bin/autodream-web.py tests/autodream-web.py tests/autodream-web-browser.py)" web "its server and browser tests"
assert_eq "$(scope docs/demo/build.py docs/demo/demo-fetch.js)" web "the Pages demo"
assert_eq "$(scope docs/screenshots/fixture.py docs/screenshots/lately.png README.md)" web "the screenshot fixture, with a README edit beside it"
assert_eq "$(scope web/index.html CLAUDE.md docs/plans/x.md codemaps/web.md)" web "web plus prose markdown"

echo "# anything else runs the whole suite"
assert_eq "$(scope web/threads.js)" full "web/threads.js: threads-render.py inlines it into a page run-all asserts on"
assert_eq "$(scope web/threads.css)" full "web/threads.css, for the same reason"
assert_eq "$(scope web/app.js bin/run.sh)" full "one non-web file makes the whole PR full"
assert_eq "$(scope bin/autodream-web)" full "the shell launcher, which install.sh links"
assert_eq "$(scope web/app.js prompts/PROMPT.md)" full "prompts are markdown the suite asserts on"
assert_eq "$(scope web/app.js adapters/omp/triage.md)" full "and so are adapters' markdown files"
assert_eq "$(scope web/app.js skills/autodream/SKILL.md)" full "and the skill an install suite reads"
assert_eq "$(scope web/app.js .github/workflows/tests.yml)" full "a workflow change"
assert_eq "$(scope web/app.js .github/ci-scope.sh)" full "a change to this selector"
assert_eq "$(scope tests/autodream-web.sh)" full "the web suite's runner, which run-all also calls"
assert_eq "$(scope .gitignore)" full "a path with no rule"
assert_eq "$(scope README.md)" full "prose alone: nothing web changed, so nothing is narrowed"
assert_eq "$(scope web/../bin/run.sh)" full "a path that climbs out of web/"
assert_eq "$(printf '' | bash "$SCOPE" 2>/dev/null)" full "no changed paths at all"

echo "# given a base and a head, it diffs them itself and sees both sides of a rename"
G=$(mktemp -d "${TMPDIR:-/tmp}/ciscope.XXXXXX")
( cd "$G" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir bin web && printf 'echo run\n' > bin/run.sh && printf 'a{}\n' > web/app.css \
  && git add -A && git commit -qm base && git tag base \
  && git mv bin/run.sh web/run.sh && git commit -qm move && git tag moved \
  && printf 'b{}\n' >> web/app.css && git commit -qam css && git tag css ) >/dev/null 2>&1
if git -C "$G" rev-parse -q --verify css >/dev/null 2>&1; then
  assert_eq "$(cd "$G" && bash "$SCOPE" base moved </dev/null 2>/dev/null)" full "moving bin/run.sh into web/ is not a web-only change"
  assert_eq "$(cd "$G" && bash "$SCOPE" moved css </dev/null 2>/dev/null)" web "a real web-only diff is"
  assert_eq "$(cd "$G" && bash "$SCOPE" base no-such-ref </dev/null 2>/dev/null)" full "a diff that fails"
else
  no "could not build the rename fixture repo"
fi
rm -rf "$G"

echo "# every tracked web file is one the full suite never reads"
web_files=$(cd "$REPO" && git ls-files | while IFS= read -r p; do
  if [ "$(scope "$p")" = web ] && [ "${p%.md}" = "$p" ]; then printf '%s\n' "$p"; fi
done)
[ -n "$web_files" ] && ok "some tracked files classify as web ($(printf '%s\n' "$web_files" | wc -l | tr -d ' '))" || no "no tracked file classifies as web"
darwin_only=$(sed -n 's/.*Darwin \] && _suites="$_suites \(.*\)"$/\1/p' "$HERE/run-all.sh")
[ -n "$darwin_only" ] && ok "run-all.sh's macOS-only suites are known ($darwin_only)" || no "could not read run-all.sh's macOS-only suites"
reader_paths() {
  local p
  cd "$REPO" && git ls-files 'bin/*' 'adapters/*' 'prompts/*' 'tests/*.sh' 'tests/*.py' | while IFS= read -r p; do
    [ "$(scope "$p")" = web ] && continue
    case "$p" in tests/autodream-web.sh|tests/ci-scope.sh|bin/autodream-web) continue ;; esac
    case " $darwin_only " in *" $(basename "$p" .sh) "*) continue ;; esac
    printf '%s\n' "$p"
  done
}
readers=$(reader_paths)
leaks=""
for f in $web_files; do
  base=$(basename "$f")
  hit=$(cd "$REPO" && printf '%s\n' "$readers" | xargs grep -l -F "$base" 2>/dev/null | head -3 | tr '\n' ' ')
  [ -n "$hit" ] && leaks="$leaks $f<-[$hit]"
done
assert_eq "$leaks" "" "no full-suite code names a web-classified file"

echo "# the comment ratchet covers every PR, web-only ones included"
TESTS_YML="$REPO/.github/workflows/tests.yml"
LAUNCHD_YML="$REPO/.github/workflows/launchd.yml"
ratchet_step=$(awk '/- name: comment ratchet, web scope/ { grab = 1 } grab { print } grab && /run:/ { exit }' "$TESTS_YML")
assert_eq "$(printf '%s\n' "$ratchet_step" | grep -c "scope == 'web'")" 1 "tests.yml has a web-scope step for the ratchet"
assert_eq "$(printf '%s\n' "$ratchet_step" | grep -c 'run: bash tests/comment-ratchet.sh')" 1 "and it runs tests/comment-ratchet.sh"
shfmt_step=$(awk '/- name: shfmt/ { grab = 1 } grab { print } grab && /shfmt --version/ { exit }' "$TESTS_YML")
assert_eq "$(printf '%s\n' "$shfmt_step" | grep -c 'apt-get install.* shfmt')" 1 "tests.yml installs shfmt for the ratchet"
assert_eq "$(printf '%s\n' "$shfmt_step" | grep -c "scope == 'full' || matrix.shard == 0")" 1 "on every full shard and on shard 0 of a web run"
assert_eq "$(grep -c 'brew install shfmt' "$LAUNCHD_YML")" 1 "launchd.yml's full suite installs shfmt too"

assert_eq "$(grep -c "^      - '!docs/\*\*'$" "$TESTS_YML") $(grep -c "^      - '!example/\*\*'$" "$TESTS_YML")" "2 2" "tests.yml keeps skipping docs/ and example/ in both lists (CI cost; comment-ratchet.yml covers a comment added there)"
assert_eq "$(grep -c "^      - 'docs/demo/\*\*'$" "$TESTS_YML") $(grep -c "^      - 'docs/screenshots/fixture.py'$" "$TESTS_YML")" "2 2" "and keeps the re-includes for the demo and the screenshot fixture"
assert_eq "$(grep -c "^      - '!\*\*\.md'$" "$TESTS_YML")" 2 "and skips markdown, in both lists"

echo "# a workflow with no paths filter runs the ratchet on every PR, docs-only ones included"
RATCHET_YML="$REPO/.github/workflows/comment-ratchet.yml"
if [ -f "$RATCHET_YML" ]; then
  ok "comment-ratchet.yml exists"
else
  no "comment-ratchet.yml exists"
fi
assert_eq "$(grep -c '^ *paths' "$RATCHET_YML" 2>/dev/null)" 0 "it has no paths or paths-ignore filter, so a docs-only PR starts it"
assert_eq "$(grep -c '^  pull_request:' "$RATCHET_YML" 2>/dev/null) $(grep -c '^  push:' "$RATCHET_YML" 2>/dev/null)" "1 1" "it runs on every pull request and on pushes to main"
assert_eq "$(grep -c 'branches: \[main\]' "$RATCHET_YML" 2>/dev/null)" 1 "the push trigger is main only, as in tests.yml"
assert_eq "$(grep -c 'run: bash tests/comment-ratchet.sh' "$RATCHET_YML" 2>/dev/null)" 1 "it runs only tests/comment-ratchet.sh"
assert_eq "$(grep -c 'apt-get install.* shfmt' "$RATCHET_YML" 2>/dev/null)" 1 "and installs the shfmt the ratchet parses shell with"
assert_eq "$(grep -c 'draft' "$RATCHET_YML" 2>/dev/null)" 0 "a draft PR is checked too: the ratchet takes seconds"
assert_eq "$(grep -c '^ *#' "$RATCHET_YML" 2>/dev/null)" 0 "the workflow adds no comment lines, which the ratchet would count"

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
