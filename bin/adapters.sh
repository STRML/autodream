#!/bin/bash
set -u

adapters_reject_log() {
  if [ -n "${ADAPTERS_REJECT_LOG:-}" ]; then printf '%s' "$ADAPTERS_REJECT_LOG"; return 0; fi
  printf '%s' "${TMPDIR:-/tmp}/autodream-adapters-rejected.$$"
}

adapters_root() {
  if [ -n "${ADAPTERS_ROOT:-}" ]; then printf '%s' "$ADAPTERS_ROOT"; return 0; fi
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  if [ -d "$here/adapters" ]; then printf '%s' "$here/adapters"; return 0; fi
  printf '%s' "$(cd "$here/.." && pwd)/adapters"
}

adapters_rejected() {
  local log out; log=$(adapters_reject_log)
  if [ -f "$log" ]; then
    out=$(sort -u "$log" | tr '\n' ',' | sed 's/,$//')
  else
    out=""
  fi
  if [ -z "$out" ] && [ -f "$(_adapter_reject_broken_marker)" ]; then
    out="unknown (the reject log could not be written)"
  fi
  [ -n "$out" ] || out=none
  printf '%s' "$out"
}

_adapter_reject_broken_marker() {
  printf '%s' "${TMPDIR:-/tmp}/autodream-adapters-rejectlog-broken.$$"
}
_adapter_reject() {
  local log; log=$(adapters_reject_log)
  { printf '%s\n' "$1" >> "$log"; } 2>/dev/null \
    || : > "$(_adapter_reject_broken_marker)" 2>/dev/null || true
}

_adapter_name_safe() {
  case "$1" in
    [abcdefghijklmnopqrstuvwxyz]*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;;
  esac
  return 0
}

_adapter_ok() {
  local root dir real realroot name
  root=$(adapters_root)
  dir="$root/$1"

  case "$1" in _*) return 1 ;; esac

  _adapter_name_safe "$1" || { _adapter_reject "$1"; return 1; }

  real=$(realpath "$dir" 2>/dev/null)     || { _adapter_reject "$1"; return 1; }
  realroot=$(realpath "$root" 2>/dev/null) || { _adapter_reject "$1"; return 1; }
  case "$real" in
    "$realroot"/*) : ;;
    *) _adapter_reject "$1"; return 1 ;;
  esac

  [ -f "$dir/manifest.json" ] && [ -x "$dir/adapter.sh" ] || { _adapter_reject "$1"; return 1; }

  name=$(jq -re '.name // empty' "$dir/manifest.json" 2>/dev/null) || { _adapter_reject "$1"; return 1; }
  [ "$name" = "$1" ] || { _adapter_reject "$1"; return 1; }
  return 0
}

adapters_list() {
  local root d n
  root=$(adapters_root)
  [ -d "$root" ] || return 0
  for d in "$root"/*/ "$root"/.*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    case "$n" in .|..) continue ;; esac
    _adapter_ok "$n" && printf '%s\n' "$n"
  done
  return 0
}

adapter_manifest_get() {
  local root v
  _adapter_name_safe "$1" || return 1
  root=$(adapters_root)
  v=$(jq -re "${2} // empty" "$root/$1/manifest.json" 2>/dev/null) || return 1
  printf '%s' "${v//\$HOME/$HOME}"
}

adapter_run() {
  local root name
  name="$1"
  _adapter_name_safe "$name" || return 1
  root=$(adapters_root); shift
  "$root/$name/adapter.sh" "$@"
}

adapter_l1_engine() {
  local name="$1" reviewer="${2:-}" up var v
  _adapter_name_safe "$name" || return 1
  up=$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')
  var="AUTODREAM_L1_ENGINE_$up"
  v="${!var:-${AUTODREAM_L1_ENGINE:-${reviewer:-$name}}}"
  if [ "$v" != "$name" ]; then
    _adapter_name_safe "$v" && _adapter_ok "$v" || return 1
  fi
  printf '%s' "$v"
}

adapter_l1_model() {
  local engine up var v
  engine=$(adapter_l1_engine "$1" "${2:-}") || return 1
  up=$(printf '%s' "$engine" | tr 'a-z-' 'A-Z_')
  var="AUTODREAM_L1_MODEL_$up"
  v="${!var:-}"
  [ -n "$v" ] || v="${AUTODREAM_L1_MODEL:-}"
  [ -n "$v" ] || v=$(adapter_manifest_get "$engine" '.l1_model' 2>/dev/null) || v=""
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

adapter_l2_model() {
  local name="$1" up var v
  _adapter_name_safe "$name" || return 1
  up=$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')
  var="AUTODREAM_L2_MODEL_$up"
  v="${!var:-}"
  [ -n "$v" ] || v="${AUTODREAM_L2_MODEL:-}"
  [ -n "$v" ] || v=$(adapter_manifest_get "$name" '.l2_model' 2>/dev/null) || v=""
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

provider_probe_url() {
  local name="${1:-}" model="${2:-}" provider up var v
  if [ "$name" = "claude" ]; then provider=anthropic
  else
    case "$model" in */*) provider="${model%%/*}" ;; *) return 1 ;; esac
  fi
  up=$(printf '%s' "$provider" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9' '_')
  var="AUTODREAM_NETUP_URL_$up"
  v="${!var:-}"
  if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  case "$provider" in
    anthropic)  printf '%s' "https://api.anthropic.com/" ;;
    deepseek)   printf '%s' "https://api.deepseek.com/" ;;
    neuralwatt) printf '%s' "https://api.neuralwatt.com/" ;;
    zai|z-ai)   printf '%s' "https://api.z.ai/" ;;
    runinfra)   printf '%s' "https://api.runinfra.ai/" ;;
    *) return 1 ;;
  esac
}
