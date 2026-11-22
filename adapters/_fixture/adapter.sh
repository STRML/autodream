#!/bin/bash
set -u

publish_staged() {
  mv -f "$1" "$2" 2>/dev/null || { rm -f "$1"; exit 1; }
  [ -f "$2" ] || { rm -f "$2/$(basename "$1")" 2>/dev/null; exit 1; }
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift

case "$cmd" in

  enumerate)
    find "$1" -type f -name '*.fixture' -print0 2>/dev/null
    ;;

  normalize|slim)
    [ -r "$1" ] || exit 1
    [ "$cmd" = normalize ] && { jq -e . "$1" >/dev/null 2>&1 || exit 1; }
    [ ! -d "$2" ] || exit 1
    t=$(mktemp "$2.tmp.XXXXXX" 2>/dev/null) || exit 1
    cp "$1" "$t" 2>/dev/null || { rm -f "$t"; exit 1; }
    publish_staged "$t" "$2"
    ;;

  project)
    [ -r "$1" ] || exit 1
    cwd=$(jq -re '.cwd // empty' "$1" 2>/dev/null) || exit 1
    [ -n "$cwd" ] || exit 1
    realpath "$cwd" 2>/dev/null || exit 1
    ;;

  stats)
    [ -r "$1" ] || exit 1
    bytes=$(wc -c < "$1" | tr -d ' ')
    turns=$(jq -re '.turns // 0' "$1" 2>/dev/null) || turns=0
    [ ! -d "$2" ] || exit 1
    t=$(mktemp "$2.tmp.XXXXXX" 2>/dev/null) || exit 1
    printf '{"transcript_bytes":%s,"user_message_count":%s,"tool_call_count":0}\n' \
      "${bytes:-0}" "${turns:-0}" > "$t" 2>/dev/null || { rm -f "$t"; exit 1; }
    publish_staged "$t" "$2"
    ;;

  is-self)
    [ -r "$1" ] || exit 3
    exit 1
    ;;
  engine-bin) printf '%s\n' true ;;

  l2-argv)
    printf '%s\0' true ${1:+"$1"}
    ;;
  l1-argv|warmup-argv)
    [ "$#" -ge 1 ] && [ -n "$1" ] || exit 2
    printf '%s\0' true "$1"
    ;;

  l1-env) : ;;

  skills-inventory) printf 'fixture-skill\n' ;;

  *)
    printf '_fixture adapter: unknown subcommand: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
