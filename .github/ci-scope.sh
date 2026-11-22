#!/bin/bash
set -u

if [ "$#" -eq 2 ]; then
  if ! paths=$(git diff --name-only --no-renames "$1" "$2" 2>/dev/null); then
    echo "ci-scope: git diff $1 $2 failed" >&2
    echo full
    exit 0
  fi
  printf '%s\n' "$paths" >&2
  printf '%s\n' "$paths" | bash "$0"
  exit 0
fi

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
