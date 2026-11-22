#!/bin/bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$REPO/bin/portable.sh"

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
eq() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got [$1] want [$2])"; fi; }
refuses() { # $1=description, rest=command
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi
}

echo "# pdate_shift"
eq "$(pdate_shift 2026-03-08 1 d)" 2026-03-09 "one day forward"
eq "$(pdate_shift 2026-03-01 -1 d)" 2026-02-28 "one day back across a month"
eq "$(pdate_shift 2024-02-28 2 d)" 2024-03-01 "a leap day is counted"
eq "$(pdate_shift 2026-12-31 1 d)" 2027-01-01 "across a year"
eq "$(pdate_shift 2026-10-07 5 y)" 2031-10-07 "five years"
eq "$(pdate_shift 2026-10-07 +1 d)" 2026-10-08 "an explicit plus sign"
refuses "a word is not a date" pdate_shift tomorrow 1 d
refuses "a date with a time is not a date" pdate_shift "2026-10-07 12:00:00" 1 d
refuses "an unknown unit is refused" pdate_shift 2026-10-07 1 w
refuses "a non-number is refused" pdate_shift 2026-10-07 x d

echo "# pdate_epoch and pdate_fmt_epoch"
eq "$(TZ=UTC pdate_epoch '1970-01-02 00:00:00')" 86400 "a UTC stamp"
eq "$(TZ=UTC pdate_epoch 1970-01-02)" 86400 "a bare date is midnight"
eq "$(TZ=UTC pdate_fmt_epoch 86400 +%Y-%m-%d)" 1970-01-02 "epoch back to a date"
eq "$(TZ=UTC pdate_fmt_epoch 90061 +%Y-%m-%dT%H:%M:%S)" 1970-01-02T01:01:01 "epoch back to a stamp"
a=$(TZ=America/New_York pdate_epoch 2026-03-08); b=$(TZ=America/New_York pdate_epoch 2026-03-09)
eq "$((b - a))" 82800 "a spring-forward day is 23 hours"
a=$(TZ=America/New_York pdate_epoch 2026-11-01); b=$(TZ=America/New_York pdate_epoch 2026-11-02)
eq "$((b - a))" 90000 "a fall-back day is 25 hours"
refuses "a word is not a stamp" pdate_epoch yesterday
refuses "a date and a bare hour is not a stamp" pdate_epoch "2026-10-07 12"
refuses "a non-number epoch is refused" pdate_fmt_epoch abc +%F

echo "# pdate_yesterday"
y=$(pdate_yesterday)
case "$y" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ok "yesterday is a date" ;; *) no "yesterday is a date (got [$y])" ;; esac
eq "$(pdate_shift "$y" 1 d)" "$(date +%Y-%m-%d)" "yesterday plus a day is today"

echo "# pstat_mtime and pstat_mode"
t=$(mktemp -d "${TMPDIR:-/tmp}/portable.XXXXXX")
: > "$t/f"
TZ=UTC touch -t 200001010000 "$t/f"
eq "$(pstat_mtime "$t/f")" 946684800 "mtime is epoch seconds"
chmod 600 "$t/f"; eq "$(pstat_mode "$t/f")" 600 "mode 600"
chmod 755 "$t/f"; eq "$(pstat_mode "$t/f")" 755 "mode 755"
chmod 640 "$t/f"; eq "$(pstat_mode "$t/f")" 640 "mode 640"
refuses "a missing file has no mtime" pstat_mtime "$t/none"
rm -rf "$t"

echo "# tmo and repo_slug"
tmo 5 true; eq "$?" 0 "tmo passes a zero status through"
tmo 5 sh -c 'exit 7'; eq "$?" 7 "tmo passes a nonzero status through"
start=$SECONDS; tmo 1 sleep 5 && slow_rc=0 || slow_rc=$?
[ "$slow_rc" -ne 0 ] && [ $((SECONDS - start)) -lt 4 ] && eq ok ok "tmo kills a command past its bound" || eq "rc=$slow_rc" ok "tmo kills a command past its bound"
nt=$(mktemp -d "${TMPDIR:-/tmp}/tmo-nt.XXXXXX")
for tool in cat sleep kill pkill; do p=$(command -v "$tool") && ln -s "$p" "$nt/$tool"; done
fallback_out=$(printf 'piped\n' | PATH="$nt" /bin/bash -c '. "$1"; tmo 5 cat' _ "$REPO/bin/portable.sh")
eq "$fallback_out" "piped" "tmo without a timeout binary keeps the caller's stdin"
closed_out=$(PATH="$nt" /bin/bash -c '. "$1"; tmo 5 cat 0<&-; echo "rc=$?"' _ "$REPO/bin/portable.sh" 0<&-)
eq "$closed_out" "rc=0" "tmo without a timeout binary still runs when the caller closed stdin"
fallback_err=$(PATH="$nt" /bin/bash -c '. "$1"; tmo 5 /bin/bash -c '\''echo child-error >&2; exit 7'\''; rc=$?; echo caller-error >&2; exit "$rc"' _ "$REPO/bin/portable.sh" 2>&1) && fallback_rc=0 || fallback_rc=$?
eq "$fallback_rc" 7 "fallback preserves a failing command status"
eq "$fallback_err" "$(printf 'child-error\ncaller-error')" "fallback preserves child and caller stderr"
rm -rf "$nt"
g=$(mktemp -d "${TMPDIR:-/tmp}/portable.XXXXXX")
git init -q "$g" 2>/dev/null
eq "$(repo_slug "$g")" "" "no remote has no slug"
git -C "$g" config remote.origin.url https://github.com/STRML/cc-autodream.git
eq "$(repo_slug "$g")" STRML/cc-autodream "https origin"
git -C "$g" config remote.origin.url git@github.com:STRML/cc-autodream.git
eq "$(repo_slug "$g")" STRML/cc-autodream "ssh origin"
git -C "$g" config remote.origin.url https://gitlab.com/STRML/cc-autodream.git
eq "$(repo_slug "$g")" "" "a non-github origin has no slug"
rm -rf "$g"

printf '\npassed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
