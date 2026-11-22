#!/bin/bash
# Confine an L1 worker's writes to its own staging directory (#169).
#
# An L1 worker holds the Write tool, so until now it could write any path the user can: another
# session's findings, a chunk answer before the runner checked it, a new *.json in the findings
# dir, $AUTODREAM_DIR/config. No check on files in the findings dir can tell the runner's writes
# from a worker's, so the access is what changes. The runner makes a staging directory per answer,
# tells the worker to write its answer there, runs the engine under an OS sandbox that can write
# only that directory (plus the narrow list of state paths the engine itself needs), and copies the
# answer into the findings dir after the engine has exited. The staging directory itself is made by
# run.sh; this helper builds the sandbox around it.
#
#   l1-confine.sh probe
#       One line: "yes<TAB><tool>" or "no<TAB><reason>". Runs a real confined shell and checks it
#       can write inside a staging directory and cannot write beside it, so a tool that accepts a
#       profile and then confines nothing reads as "no". Always exits 0.
#   l1-confine.sh engine-prefix <adapter.sh> <stage>
#       The prefix for one engine: its writable paths come from `<adapter.sh> l1-writes`, so setup and
#       every worker call build the same thing from the same list. Exits 1 with the reason when the
#       adapter declares no write profile or a path in it is refused.
#   l1-confine.sh prefix <stage> [writable-path ...]
#       NUL-delimited argv to put in front of the engine command. A writable path is a directory
#       (subpath), or a prefix when it ends in "*" (~/.claude.json and, under sandbox-exec, the temp
#       files claude renames over it). L1_CONFINE_PROTECT (colon-separated) names paths the engine
#       cannot write even when a writable path covers them: $AUTODREAM_DIR sits under ~/.claude on
#       a default install. Under bwrap a prefix binds only the files that already match it.
#
# Every path that reaches a profile or a bind is checked first, whatever the tool: absolute, from the
# characters a profile can hold (no glob, no quote), and a writable path is not a symlink itself (it would
# grant its target). The staging directory is not a symlink and, when L1_STAGE_ROOT is set, resolves
# under it. Globbing is off for the whole script; the one place a prefix rule needs it turns it on.
#
# L1_CONFINE_TOOL=sandbox-exec|bwrap picks a tool (default: sandbox-exec, then bwrap).
#
# The profile denies writes only. Reads, the network and process exec are unchanged: the engine
# must read transcripts and reach its provider, and read access is not what #169 is about.
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

# A path that goes into the profile text must not be able to close the string or add a rule.
safe_path() {
  case "$1" in
    ""|*[!A-Za-z0-9._/@+~=,:\ -]*) return 1 ;;
  esac
  return 0
}

# Resolve the part of a path that exists, so a symlinked parent (/tmp, /var, ~ on some hosts)
# compares as the kernel sees it. A path that does not exist yet keeps its tail.
resolve_path() {
  local p="$1" tail=""
  # A regular file cannot be cd'd into: resolve its parent and keep its name.
  if [ -e "$p" ] && [ ! -d "$p" ]; then tail="/$(basename "$p")"; p=$(dirname "$p"); fi
  while [ ! -e "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
    tail="/$(basename "$p")$tail"; p=$(dirname "$p")
  done
  printf '%s%s' "$(phys "$p" || printf '%s' "$p")" "$tail"
}

# A path as the kernel sees it, checked again after resolving: a symlink can lead to a name that
# the profile text cannot hold (a quote or a newline), which the check on the supplied path never saw.
profile_path() { # $1=path -> the resolved path, or exit 1
  local r; r=$(resolve_path "$1")
  safe_path "$r" || { printf 'l1-confine: %s resolves to a path the profile cannot hold: %s\n' "$1" "$r" >&2; return 1; }
  printf '%s' "$r"
}

# What every path must satisfy before it can reach a profile or a bind (a message on stderr, exit 1).
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
      # A bind mount names an existing path, so a prefix rule binds the files that already match it
      # (.claude.json itself, written in place) and cannot cover a temp file created later: the
      # sandbox-exec profile can, bwrap cannot. A protected path is bound read-only after the state
      # paths, and the stage last, so it wins inside a protected directory.
      printf '%s\0' "$(command -v bwrap)" --ro-bind / / --dev /dev --proc /proc --die-with-parent
      local f
      for p in "$@"; do
        case "$p" in
          "") continue ;;
          *"*") set +f; for f in "${p%\*}"*; do [ -e "$f" ] && printf '%s\0' --bind "$f" "$f"; done; set -f ;;
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
  local adapter="$1" stage="$2" l out paths=()
  if ! out=$("$adapter" l1-writes 2>/dev/null); then
    printf 'l1-confine: %s declares no write profile\n' "$adapter" >&2; return 1
  fi
  while IFS= read -r l; do [ -n "$l" ] && paths+=("$l"); done <<< "$out"
  cmd_prefix "$stage" ${paths[@]+"${paths[@]}"}
}

case "${1:-}" in
  probe) cmd_probe ;;
  engine-prefix) shift; [ "$#" -eq 2 ] || exit 2; cmd_engine_prefix "$@" ;;
  prefix) shift; [ "$#" -ge 1 ] || exit 2; cmd_prefix "$@" ;;
  *) echo "usage: l1-confine.sh probe | prefix <stage> [writable-path ...] | engine-prefix <adapter.sh> <stage>" >&2; exit 2 ;;
esac
