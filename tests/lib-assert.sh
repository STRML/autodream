#!/bin/bash

ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }

assert_eq(){
  if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got [$1] want [$2])"; fi
}
assert_file(){
  if [ -f "$1" ]; then ok "$2"; else no "$2 (missing: $1)"; fi
}
assert_no_file(){
  if [ ! -e "$1" ]; then ok "$2"; else no "$2 (unexpected: $1)"; fi
}
assert_grep(){
  if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else no "$3 (no /$2/ in $1)"; fi
}
assert_nogrep(){
  if grep -q -- "$2" "$1" 2>/dev/null; then no "$3 (/$2/ unexpectedly in $1)"; else ok "$3"; fi
}
