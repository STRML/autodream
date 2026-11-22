#!/bin/bash
set -u
set -f

tool_for() {
  case "${L1_CONFINE_TOOL:-}" in
    sandbox-exec|bwrap) command -v "$L1_CONFINE_TOOL" >/dev/null 2>&1 && printf '%s' "$L1_CONFINE_TOOL"; return ;;
    "") ;;
    *) return 1 ;;
  esac
  if command -v sandbox-exec >/dev/null 2>&1; then printf 'sandbox-exec'
  elif command -v bwrap >/dev/null 2>&1; then printf 'bwrap'
  else return 1
  fi
}

phys() { (cd "$1" 2>/dev/null && pwd -P); }

safe_path() {
  case "$1" in
    ""|*[!A-Za-z0-9._/@+~=,:\ -]*) return 1 ;;
  esac
  return 0
}

resolve_path() {
  local p="$1" tail=""
  if [ -e "$p" ] && [ ! -d "$p" ]; then tail="/$(basename "$p")"; p=$(dirname "$p"); fi
  while [ ! -e "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
    tail="/$(basename "$p")$tail"; p=$(dirname "$p")
  done
  printf '%s%s' "$(phys "$p" || printf '%s' "$p")" "$tail"
}

profile_path() { # $1=path -> the resolved path, or exit 1
  local r; r=$(resolve_path "$1")
  safe_path "$r" || { printf 'l1-confine: %s resolves to a path the profile cannot hold: %s\n' "$1" "$r" >&2; return 1; }
  printf '%s' "$r"
}

check_writable() { # $1=path as listed (a trailing * makes it a prefix)
  local p="${1%\*}"
  case "$p" in
    /*) ;;
    *) printf 'l1-confine: a writable path must be absolute: %s\n' "$1" >&2; return 1 ;;
  esac
  safe_path "$p" || { printf 'l1-confine: refusing writable path with a character the profile cannot hold: %s\n' "$1" >&2; return 1; }
  if [ -L "$p" ]; then
    printf 'l1-confine: a writable path must not be a symlink, it would grant its target: %s\n' "$1" >&2; return 1
  fi
}

check_protect() { # $1=path
  case "$1" in
    /*) ;;
    *) printf 'l1-confine: a protected path must be absolute: %s\n' "$1" >&2; return 1 ;;
  esac
  safe_path "$1" || { printf 'l1-confine: a protected path cannot be written into a profile: %s\n' "$1" >&2; return 1; }
}

check_stage() { # $1=stage
  local s="$1" real root
  if [ -L "$s" ]; then printf 'l1-confine: the staging directory is a symlink: %s\n' "$s" >&2; return 1; fi
  real=$(phys "$s") || { printf 'l1-confine: the staging directory does not exist: %s\n' "$s" >&2; return 1; }
  [ -n "${L1_STAGE_ROOT:-}" ] || return 0
  root=$(phys "$L1_STAGE_ROOT") || { printf 'l1-confine: the staging root does not exist: %s\n' "$L1_STAGE_ROOT" >&2; return 1; }
  case "$real/" in
    "$root"/?*) ;;
    *) printf 'l1-confine: %s does not resolve under the staging root %s\n' "$s" "$root" >&2; return 1 ;;
  esac
}

check_all() { # $1=stage, rest: writable paths
  local stage="$1" p; shift
  check_stage "$stage" || return 1
  for p in "$@"; do [ -n "$p" ] || continue; check_writable "$p" || return 1; done
  local IFS=:
  for p in ${L1_CONFINE_PROTECT:-}; do [ -n "$p" ] || continue; check_protect "$p" || return 1; done
}

sb_profile() { # $1=stage, rest: writable paths. Protected paths come from L1_CONFINE_PROTECT.
  local stage="$1" p base; shift
  safe_path "$stage" || { printf 'l1-confine: the staging path cannot be written into a profile: %s\n' "$stage" >&2; return 1; }
  printf '(version 1)\n(allow default)\n(deny file-write*)\n'
  printf '(allow file-write* (literal "/dev/null") (literal "/dev/tty") (literal "/dev/dtracehelper") (literal "/dev/stdout") (literal "/dev/stderr") (regex #"^/dev/fd/[0-9]+$"))\n'
  for p in "$@"; do
    [ -n "$p" ] || continue
    safe_path "${p%\*}" || { printf 'l1-confine: refusing writable path with a character the profile cannot hold: %s\n' "$p" >&2; return 1; }
    case "$p" in
      *"*") base=$(profile_path "${p%\*}") || return 1
            printf '(allow file-write* (regex #"^%s"))\n' "$(printf '%s' "$base" | sed 's/[][\.^$*+?(){}|]/\\&/g')" ;;
      *) base=$(profile_path "$p") || return 1
         printf '(allow file-write* (subpath "%s"))\n' "$base" ;;
    esac
  done
  local IFS=:
  for p in ${L1_CONFINE_PROTECT:-}; do
    [ -n "$p" ] || continue
    safe_path "$p" || { printf 'l1-confine: a protected path cannot be written into a profile: %s\n' "$p" >&2; return 1; }
    base=$(profile_path "$p") || return 1
    printf '(deny file-write* (subpath "%s"))\n' "$base"
  done
  printf '(allow file-write* (subpath "%s"))\n' "$stage"
}

emit_prefix() { # $1=tool $2=stage, rest: writable paths -> NUL-delimited argv
  local tool="$1" stage="$2" p; shift 2
  check_all "$stage" "$@" || return 1
  stage=$(phys "$stage") || return 1
  case "$tool" in
    sandbox-exec)
      local profile; profile=$(sb_profile "$stage" "$@") || return 1
      printf '%s\0' "$(command -v sandbox-exec)" -p "$profile"
      ;;
    bwrap)
      printf '%s\0' "$(command -v bwrap)" --ro-bind / / --dev /dev --proc /proc --die-with-parent
      local f
      for p in "$@"; do
        case "$p" in
          "") continue ;;
          *"*") set +f; for f in "${p%\*}"*; do [ -L "$f" ] && continue; [ -e "$f" ] && printf '%s\0' --bind "$f" "$f"; done; set -f ;;
          *) [ -e "$p" ] && printf '%s\0' --bind "$p" "$p" ;;
        esac
      done
      ( IFS=:; for p in ${L1_CONFINE_PROTECT:-}; do [ -n "$p" ] && [ -e "$p" ] && printf '%s\0' --ro-bind "$p" "$p"; done )
      printf '%s\0' --bind "$stage" "$stage" --
      ;;
    *) return 1 ;;
  esac
}

cmd_probe() {
  local tool d stage outside err rc argv=() a
  tool=$(tool_for) || { printf 'no\tno sandbox tool on PATH (sandbox-exec or bwrap)\n'; return 0; }
  d=$(mktemp -d "${TMPDIR:-/tmp}/l1-confine-probe.XXXXXX") || { printf 'no\tcould not make a probe directory\n'; return 0; }
  stage="$d/stage"; outside="$d/outside"; err="$d/err"
  mkdir -p "$stage" "$outside"
  while IFS= read -r -d '' a; do argv+=("$a"); done < <(L1_CONFINE_PROTECT='' L1_STAGE_ROOT='' emit_prefix "$tool" "$stage" 2>"$err")
  if [ "${#argv[@]}" -eq 0 ]; then
    printf 'no\t%s could not build a profile: %s\n' "$tool" "$(head -c 200 "$err" | tr '\n\t' '  ')"
    rm -rf "$d"; return 0
  fi
  "${argv[@]}" /bin/sh -c 'printf ok > "$1/in" && { printf no > "$2/out"; true; }' _ "$(phys "$stage")" "$outside" >/dev/null 2>"$err"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'no\t%s rejected the profile or could not start (exit %s): %s\n' "$tool" "$rc" "$(head -c 200 "$err" | tr '\n\t' '  ')"
  elif [ "$(cat "$stage/in" 2>/dev/null)" != ok ]; then
    printf 'no\t%s ran but the staging directory was not writable\n' "$tool"
  elif [ -e "$outside/out" ]; then
    printf 'no\t%s ran but did not refuse a write outside the staging directory\n' "$tool"
  else
    printf 'yes\t%s\n' "$tool"
  fi
  rm -rf "$d"
  return 0
}

cmd_prefix() { # $1=stage, rest: writable paths
  local tool; tool=$(tool_for) || return 1
  emit_prefix "$tool" "$@"
}

cmd_engine_prefix() { # $1=adapter.sh, $2=stage
  local adapter="$1" stage="$2" out err rc
  err=$(mktemp "${TMPDIR:-/tmp}/l1-confine-writes.XXXXXX") || { printf 'l1-confine: could not make a temp file to read the write list\n' >&2; return 1; }
  out=$("$adapter" l1-writes 2>"$err"); rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 2 ]; then printf 'l1-confine: %s declares no write profile\n' "$adapter" >&2
    else printf 'l1-confine: %s l1-writes failed (exit %s): %s\n' "$adapter" "$rc" "$(head -c 200 "$err" | tr '\n' ' ')" >&2; fi
    rm -f "$err"; return 1
  fi
  rm -f "$err"
  local IFS=$'\n'
  # shellcheck disable=SC2086
  set -- $out
  IFS=$' \t\n'
  cmd_prefix "$stage" "$@"
}

case "${1:-}" in
  probe) cmd_probe ;;
  engine-prefix) shift; [ "$#" -eq 2 ] || exit 2; cmd_engine_prefix "$@" ;;
  prefix) shift; [ "$#" -ge 1 ] || exit 2; cmd_prefix "$@" ;;
  *) echo "usage: l1-confine.sh probe | prefix <stage> [writable-path ...] | engine-prefix <adapter.sh> <stage>" >&2; exit 2 ;;
esac
