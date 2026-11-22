#!/bin/bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp pf
PF="$REPO/bin/preflight.sh"

pass=0; fail=0
# shellcheck source=/dev/null
. "$HERE/lib-assert.sh"
has(){ case "$2" in *"$1"*) ok "$3" ;; *) no "$3 (got: $2)" ;; esac; }

[ -x "$PF" ] || { printf '  FAIL - bin/preflight.sh missing or not executable\n\npassed: 0   failed: 1\n'; exit 1; }

echo "# preflight: a host with every dependency present exits 0"
if "$PF" --l2-bin bash >/dev/null 2>&1; then ok "exits 0 when all present"; else no "exits 0 when all present"; fi

echo "# preflight: a missing L2 engine is a hard failure, named"
out=$("$PF" --l2-bin definitely-not-a-real-binary-xyz 2>&1); rc=$?
assert_eq "$rc" "1" "exits 1 on a missing L2 engine"
has "definitely-not-a-real-binary-xyz" "$out" "names the missing engine"

echo "# preflight: missing shared dependencies are named, not silently skipped"
empty=$(mktemp -d "${TMPDIR:-/tmp}/pf.XXXXXX")
out=$(PATH="$empty" "$PF" --l2-bin bash 2>&1); rc=$?
assert_eq "$rc" "1" "exits 1 when dependencies are missing"
has "jq"       "$out" "names jq"
has "shasum"   "$out" "names shasum"
has "python3"  "$out" "mentions python3"

echo "# preflight: python3 alone is a DEGRADED warning, never a hard stop"
if AUTODREAM_PREFLIGHT_FORCE_MISSING=python3 "$PF" --l2-bin bash >/dev/null 2>&1; then
  ok "a missing python3 alone still exits 0"
else
  no "a missing python3 alone still exits 0"
fi
out3=$(AUTODREAM_PREFLIGHT_FORCE_MISSING=python3 "$PF" --l2-bin bash 2>&1)
case "$out3" in *MISSING*python3*) no "python3 is not reported as MISSING" ;; *) ok "python3 is not reported as MISSING" ;; esac
case "$out3" in *DEGRADED*python3*) ok "python3 absence emits a DEGRADED warning" ;;
                *) no "python3 absence emits a DEGRADED warning (got: $out3)" ;; esac
has "realpath" "$out" "names realpath"

echo "# preflight: the reason is carried, not just the name"
has "one filename" "$out" "says what a missing shasum actually costs"
has "containment"  "$out" "says why realpath is security-critical"

echo "# preflight: a flag with no value is a usage error, never a hang"
TO=""
command -v timeout  >/dev/null 2>&1 && TO=timeout
[ -n "$TO" ] || { command -v gtimeout >/dev/null 2>&1 && TO=gtimeout; }
if [ -n "$TO" ]; then
  "$TO" 5 "$PF" --l2-bin >/dev/null 2>&1; rc4=$?
  assert_eq "$rc4" "2" "--l2-bin with no value exits 2 rather than hanging"
else
  ok "no timeout binary available; skipped the hang assertion"
fi

echo "# preflight: the failure is machine-readable for run-stats"
has "preflight_missing:" "$out" "emits a preflight_missing key"

rm -rf "$empty"
printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
