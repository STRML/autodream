#!/bin/bash

usage() {
  cat <<'EOF'
Detect the Claude config dirs ($HOME/.claude*/projects) and decide which ones autodream indexes.

Usage:
  root-probe.sh --list            every detected root and its state (index/ignore/unasked)
  root-probe.sh --consolidated    colon-joined root list autodream should scan
  root-probe.sh --unindexed       only the found-but-not-indexed roots (or empty)
  root-probe.sh --write-config    the managed SESSION_ROOTS section (used by install.sh)
  root-probe.sh --ask             prompt per unasked root, remember the answer (install TTY)
  root-probe.sh --default-index   never prompt; unasked roots become index (install non-TTY)

Choices are remembered in $AUTODREAM_DIR/root-choices.conf, a KEY=VALUE file:

  # claude-folder-indexing  (managed by bin/root-probe.sh)
  ~/.claude/projects=index
  ~/.claude-ds4/projects=index
  ~/.claude-kimi/projects=ignore

Values are index or ignore. The primary $HOME/.claude/projects is always index. Edit or
delete a line to change a choice.

With neither --ask nor --default-index (the nightly run), choices are never written.
Unasked roots stay unasked, are left out of --consolidated, and are listed by --unindexed
so the morning report can flag folders that appeared after setup.

Env:
  AUTODREAM_DIR   where root-choices.conf lives   default: $HOME/.claude/autodream

Reads directories only; makes no model calls. Safe to re-run.
EOF
}

set -u

AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"
CHOICES="$AUTODREAM_DIR/root-choices.conf"

PRIMARY="$HOME/.claude/projects"
# shellcheck disable=SC2125  # the glob must stay literal so it expands in the `for` loop below
PROBE_GLOB="$HOME"/.claude*/projects

MODE=""
WRITE=0
for a in "$@"; do
  case "$a" in
    --list|--consolidated|--unindexed|--write-config|--ask|--default-index) MODE="${MODE:-$a}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "usage: $0 --list|--consolidated|--unindexed|--write-config [--ask|--default-index]" >&2; exit 2; }
case "$MODE" in
  --ask|--default-index) WRITE=1 ;;
esac

ck=(); cv=()
if [ -f "$CHOICES" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    ck+=("${line%%=*}")
    cv+=("${line#*=}")
  done < "$CHOICES"
fi
choice() {
  local r="$1" i
  [ "$r" = "$PRIMARY" ] && { echo "index"; return; }
  for i in "${!ck[@]}"; do
    [ "${ck[$i]}" = "$r" ] && { echo "${cv[$i]}"; return; }
  done
  echo "unasked"
}

roots=()
for d in $PROBE_GLOB; do
  [ -d "$d" ] || continue
  roots+=("$d")
done
if [ -d "$PRIMARY" ]; then
  sorted=("$PRIMARY")
  for r in "${roots[@]}"; do
    [ "$r" = "$PRIMARY" ] || sorted+=("$r")
  done
  roots=("${sorted[@]}")
fi

[ "${#roots[@]}" -gt 0 ] || roots=("")

unasked=()
for r in "${roots[@]}"; do
  [ -n "$r" ] || continue
  [ "$(choice "$r")" = "unasked" ] && unasked+=("$r")
done

if [ "$WRITE" = "1" ] && [ "${#unasked[@]}" -gt 0 ]; then
  mkdir -p "$AUTODREAM_DIR"
  if [ "$MODE" = "--ask" ] && [ -t 0 ]; then
    for r in "${unasked[@]}"; do
      n=$(find "$r" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
      printf 'Autodream: index sessions under %s (%s transcripts)? [Y/n] ' "$r" "$n"
      IFS= read -r ans
      case "${ans:-y}" in
        y|Y|"") echo "$r=index" >> "$CHOICES" ;;
        *)      echo "$r=ignore" >> "$CHOICES" ;;
      esac
    done
  else
    for r in "${unasked[@]}"; do
      echo "$r=index" >> "$CHOICES"
      echo "indexing $r (no TTY to ask)" >&2
    done
  fi
fi

consolidated_roots() {
  local first=1 r
  for r in "${roots[@]}"; do
    [ -n "$r" ] || continue
    [ "$r" = "$PRIMARY" ] || [ "$(choice "$r")" = "index" ] || continue
    case "$r" in *:*)
      echo "root-probe: refusing to index path containing ':' ($r); SESSION_ROOTS is colon-separated" >&2
      continue ;;
    esac
    [ "$first" = "1" ] || printf ':'
    printf '%s' "$r"
    first=0
  done
}

case "$MODE" in
  --list)
    for r in "${roots[@]}"; do
      [ -n "$r" ] || continue
      printf '%s\t%s\n' "$(choice "$r")" "$r"
    done
    ;;
  --consolidated)
    consolidated_roots
    printf '\n'
    ;;
  --unindexed)
    for r in "${roots[@]}"; do
      [ -n "$r" ] || continue
      [ "$(choice "$r")" = "index" ] && continue
      printf '%s\n' "$r"
    done
    ;;
  --write-config)
    consolidated=$(consolidated_roots)
    printf '# claude-folder-indexing  (managed by bin/root-probe.sh)\n'
    printf 'SESSION_ROOTS=%s\n' "$(printf '%q' "$consolidated")"
    ;;
esac
