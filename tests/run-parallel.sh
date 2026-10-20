#!/bin/bash
# Run tests/run-all.sh as N shards at once on this machine and report them as one run.
#
#   tests/run-parallel.sh          4 shards
#   tests/run-parallel.sh 8        8 shards
#
# Each shard is `RUNALL_SHARD=i/N bash tests/run-all.sh` with a TMPDIR of its own, so no shard
# sees another's sandboxes. The shards partition the suite (tests/shard.sh), so together they run
# every test exactly once, in roughly 1/N of the time. The totals print in run-all.sh's own format.
#
# Exit: 0 if every shard passed, 1 if any failed, 2 on a bad argument.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
N="${1:-4}"
case "$N" in ''|*[!0-9]*) echo "usage: tests/run-parallel.sh [shards]" >&2; exit 2 ;; esac
[ "$N" -ge 1 ] || { echo "usage: tests/run-parallel.sh [shards]" >&2; exit 2; }

# Short on purpose: the suite's sandbox paths sit under TMPDIR, and some fixtures embed them in lines
# that are cut at a fixed length, so every character here is a character those lines lose.
OUT=$(mktemp -d "${TMPDIR:-/tmp}/rp.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start=$SECONDS
for ((i = 0; i < N; i++)); do
  mkdir -p "$OUT/$i"
  (
    TMPDIR="$OUT/$i" RUNALL_SHARD="$i/$N" bash "$HERE/run-all.sh" > "$OUT/shard$i.txt" 2>&1
    echo $? > "$OUT/rc$i"
  ) &
done
wait

pass=0; fail=0; bad=0
for ((i = 0; i < N; i++)); do
  p=$(sed -n 's/^passed: *\([0-9][0-9]*\).*/\1/p' "$OUT/shard$i.txt" | tail -1)
  f=$(sed -n 's/.*failed: *\([0-9][0-9]*\).*/\1/p' "$OUT/shard$i.txt" | tail -1)
  rc=$(cat "$OUT/rc$i" 2>/dev/null || echo 1)
  pass=$((pass + ${p:-0})); fail=$((fail + ${f:-0}))
  printf 'shard %d/%d: passed %s, failed %s (exit %s)\n' "$i" "$N" "${p:-?}" "${f:-?}" "$rc"
  # A shard that died before printing totals counts as one failure rather than reading as green.
  if [ -z "$p" ] || [ -z "$f" ]; then fail=$((fail + 1)); bad=1; fi
  if [ "$rc" -ne 0 ]; then bad=1; grep 'FAIL' "$OUT/shard$i.txt" | head -20 | sed 's/^/    /'; fi
done

echo
echo "----------------------------------------"
echo "passed: $pass   failed: $fail   ($N shards, $((SECONDS - start))s)"
[ "$bad" -eq 0 ] && [ "$fail" -eq 0 ]
