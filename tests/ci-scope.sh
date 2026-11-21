#!/bin/bash
# Tests for .github/ci-scope.sh, which decides whether a PR's tests.yml run needs the whole suite
# or only the web dashboard's suite. The failure that matters is a PR classified `web` whose change
# the full suite would have caught, so every assertion here leans toward `full`.
#
# Usage:  tests/ci-scope.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
SCOPE="$REPO/.github/ci-scope.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_eq(){ if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got [$1] want [$2])"; fi; }
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
# --name-only alone reports a rename by its new path only, so moving bin/run.sh into web/ read as a
# web-only change. The selector now runs the diff, with --no-renames, so CI cannot pass it half.
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
# The oracle for the rule: a file the selector calls web must not be named by any code tests.yml's
# full suite runs. web/threads.* fails this, which is why the selector excludes it. Left out of the
# readers: install.sh, which only links the web files; the macOS-only suites run-all adds on Darwin
# (install-web-agent among them), which tests.yml's Linux shards never run and launchd.yml still
# runs on its own paths; and bin/autodream-web, the launcher only the web suite and those macOS
# suites start.
web_files=$(cd "$REPO" && git ls-files | while IFS= read -r p; do
  if [ "$(scope "$p")" = web ] && [ "${p%.md}" = "$p" ]; then printf '%s\n' "$p"; fi
done)
[ -n "$web_files" ] && ok "some tracked files classify as web ($(printf '%s\n' "$web_files" | wc -l | tr -d ' '))" || no "no tracked file classifies as web"
darwin_only=$(sed -n 's/.*Darwin \] && _suites="$_suites \(.*\)"$/\1/p' "$HERE/run-all.sh")
[ -n "$darwin_only" ] && ok "run-all.sh's macOS-only suites are known ($darwin_only)" || no "could not read run-all.sh's macOS-only suites"
# A function, not a loop inside $(...): bash 3.2 cannot parse a case pattern's `)` inside a command
# substitution, which is the interpreter run-all.sh and launchd use on macOS.
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

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
