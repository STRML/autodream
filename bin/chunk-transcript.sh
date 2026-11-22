#!/bin/bash
set -u

umask 077

usage() { echo "usage: $0 SRC OUTDIR CHUNK_BYTES MAX_CHUNKS" >&2; exit 2; }
is_pos() { case "$1" in ''|*[!0-9]*) return 1 ;; *) [ "$((10#$1))" -gt 0 ] ;; esac; }

[ "$#" -eq 4 ] || usage
src="$1"; outdir="$2"; limit="$3"; maxc="$4"
is_pos "$limit" && is_pos "$maxc" || usage
limit=$((10#$limit)); maxc=$((10#$maxc))
[ -r "$src" ] || { echo "chunk-transcript: cannot read $src" >&2; exit 2; }
[ -s "$src" ] || exit 1
mkdir -p "$outdir" || exit 2

rm -f "$outdir"/chunk-*.jsonl "$outdir"/raw-*.jsonl
fail() { rm -f "$outdir"/chunk-*.jsonl "$outdir"/raw-*.jsonl; exit 2; }

total=$(LC_ALL=C awk -v dir="$outdir" -v limit="$limit" '
  {
    b = length($0) + 1
    if (n == 0 || (cur > 0 && cur + b > limit)) {
      if (f != "") close(f)
      n++
      f = sprintf("%s/raw-%05d.jsonl", dir, n)
      cur = 0
    }
    print $0 > f
    cur += b
  }
  END { print n + 0 }' "$src") || fail
case "$total" in ''|*[!0-9]*) fail ;; esac
[ "$total" -gt 0 ] || { rm -f "$outdir"/raw-*.jsonl; exit 1; }

if [ "$total" -le "$maxc" ]; then
  head_n="$total"; tail_n=0; elided=0
else
  head_n=$(( (maxc + 1) / 2 )); tail_n=$(( maxc / 2 )); elided=$(( total - maxc ))
fi

out=0
take() {
  out=$((out + 1))
  mv "$outdir/$(printf 'raw-%05d.jsonl' "$1")" "$outdir/$(printf 'chunk-%02d.jsonl' "$out")" || fail
}
k=1
while [ "$k" -le "$head_n" ]; do take "$k"; k=$((k + 1)); done
if [ "$tail_n" -gt 0 ]; then
  k=$(( total - tail_n + 1 ))
  while [ "$k" -le "$total" ]; do take "$k"; k=$((k + 1)); done
fi
rm -f "$outdir"/raw-*.jsonl
printf '%s %s\n' "$out" "$elided"
