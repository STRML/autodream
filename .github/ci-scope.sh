#!/bin/bash
# Reads a PR's changed paths, one per line, and prints `web` or `full`.
#
# `web` means every path belongs to the web dashboard (or is prose markdown) and at least one is
# web code, so tests.yml runs only tests/autodream-web.sh. Anything else prints `full`: a path with
# no rule, a path this list has not been told about, no paths at all. A wrong `full` costs a few
# minutes; a wrong `web` merges a change the suite would have caught. tests/ci-scope.sh pins it.
#
# Not web, on purpose:
#   web/threads.*      bin/threads-render.py inlines them into the page run-all asserts on
#   bin/autodream-web  the shell launcher install.sh links
#   tests/autodream-web.sh, this file, any workflow: they change how tests run
#   markdown under prompts/, adapters/ or skills/: the suites assert on what it says

set -u

web=0
other=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    *..*) other=1 ;;
    web/threads.*) other=1 ;;
    web/*|docs/demo/*|docs/screenshots/*) web=1 ;;
    bin/autodream-web.py|bin/autodream_web_data.py) web=1 ;;
    tests/autodream-web.py|tests/autodream-web-data.py|tests/autodream-web-browser.py) web=1 ;;
    prompts/*|adapters/*|skills/*) other=1 ;;
    *.md) ;;
    *) other=1 ;;
  esac
done

if [ "$web" = 1 ] && [ "$other" = 0 ]; then echo web; else echo full; fi
