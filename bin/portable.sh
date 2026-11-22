#!/bin/bash
_p_is_date() { case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;; *) return 1 ;; esac; }
_p_is_stamp() { case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) return 0 ;; *) return 1 ;; esac; }
_p_is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

if date --version >/dev/null 2>&1; then _P_GNU_DATE=1; else _P_GNU_DATE=0; fi
if stat --version >/dev/null 2>&1; then _P_GNU_STAT=1; else _P_GNU_STAT=0; fi

pdate_yesterday() {
  if [ "$_P_GNU_DATE" = 1 ]; then date -d yesterday +%Y-%m-%d; else date -v-1d +%Y-%m-%d; fi
}

pdate_shift() {
  _p_is_date "${1:-}" || return 1
  case "${2:-}" in [+-][0-9]*|[0-9]*) ;; *) return 1 ;; esac
  local n="$2" unit="${3:-}" sign="+"
  case "$n" in -*) sign="-"; n="${n#-}" ;; +*) n="${n#+}" ;; esac
  _p_is_int "$n" || return 1
  case "$unit" in d|y) ;; *) return 1 ;; esac
  if [ "$_P_GNU_DATE" = 1 ]; then
    local word=days; [ "$unit" = y ] && word=years
    date -d "$1 $sign$n $word" +%Y-%m-%d 2>/dev/null
  else
    date -j -f %Y-%m-%d -v"$sign$n$unit" "$1" +%Y-%m-%d 2>/dev/null
  fi
}

pdate_epoch() {
  local s="${1:-}"
  _p_is_date "$s" && s="$s 00:00:00"
  _p_is_stamp "$s" || return 1
  if [ "$_P_GNU_DATE" = 1 ]; then date -d "$s" +%s 2>/dev/null
  else date -j -f '%Y-%m-%d %H:%M:%S' "$s" +%s 2>/dev/null; fi
}

pdate_fmt_epoch() {
  _p_is_int "${1:-}" || return 1
  if [ "$_P_GNU_DATE" = 1 ]; then date -d "@$1" "${2:-+%Y-%m-%d}" 2>/dev/null
  else date -r "$1" "${2:-+%Y-%m-%d}" 2>/dev/null; fi
}

pstat_mtime() {
  if [ "$_P_GNU_STAT" = 1 ]; then stat -c %Y "$1" 2>/dev/null; else stat -f %m "$1" 2>/dev/null; fi
}

pstat_mode() {
  if [ "$_P_GNU_STAT" = 1 ]; then stat -c %a "$1" 2>/dev/null; else stat -f %Lp "$1" 2>/dev/null; fi
}

tmo() {
  local s=$1 pid wd rc; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"; return $?; fi
  { exec 3<&0; } 2>/dev/null || exec 3</dev/null
  "$@" <&3 & pid=$!
  exec 3<&-
  ( trap 'kill "${sp:-}" 2>/dev/null; exit 0' TERM
    sleep "$s" & sp=$!; wait "$sp" || exit 0
    pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 & wd=$!
  wait "$pid"; rc=$?
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  return $rc
}

repo_slug() {
  local url
  url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || return 0
  case "$url" in
    *github.com[:/]*) url=${url#*github.com[:/]}; url=${url%.git}; printf '%s' "$url" ;;
  esac
}
