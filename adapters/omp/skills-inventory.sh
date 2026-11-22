#!/bin/bash
set -u

outfile="${1:-}"
if [ -z "$outfile" ]; then
  echo "usage: $0 <outfile>" >&2
  exit 1
fi

CLEAN_ITEM='sub(/[ \t]+#.*$/, "", item); gsub(/^[ \t]+|[ \t]+$/, "", item);
if (length(item) >= 2 && substr(item,1,1) == "\"") { if (substr(item,length(item),1) == "\"") item = substr(item, 2, length(item) - 2) }
else if (length(item) >= 2 && substr(item,1,1) == "\047") { if (substr(item,length(item),1) == "\047") item = substr(item, 2, length(item) - 2) }
if (item != "") print item'
ignored=""
CONF="$HOME/.omp/agent/config.yml"
if [ -r "$CONF" ]; then
  if command -v python3 >/dev/null 2>&1; then
    ignored="$(IGNORED_SKILLS_CONF="$CONF" python3 - <<'PY' 2>/dev/null
import os, re
try:
    lines = open(os.environ.get("IGNORED_SKILLS_CONF", ""), "r", encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)
key_indent = -1
in_block = False
for raw in lines:
    if not in_block:
        stripped = raw.lstrip(" \t")
        if stripped.startswith("ignoredSkills:"):
            key_indent = len(raw) - len(stripped)
            in_block = True
        continue
    if not raw.strip():
        continue                      # blank line inside the block keeps parsing
    indent = len(raw) - len(raw.lstrip(" \t"))
    if indent <= key_indent:
        in_block = False              # sibling key at same-or-less indent ends the block
        continue
    s = raw.lstrip(" \t")
    if not s.startswith("- "):
        continue
    item = s[2:]
    item = re.sub(r"[ \t]+#.*$", "", item)   # inline comment
    item = item.strip()
    if len(item) >= 2 and item[0] == item[-1] and item[0] in ('"', "'"):
        item = item[1:-1]
    if item:
        print(item)
PY
    )"
    if [ $? -ne 0 ]; then
      echo "skills-inventory.sh: python3 parser failed for $CONF; cannot compute the ignored-skills list" >&2
      exit 1
    fi
  elif command -v awk >/dev/null 2>&1; then
    ignored="$(awk '
      BEGIN { in_block = 0; key_indent = -1 }
      {
        if (!in_block) {
          st = $0; sub(/^[ \t]+/, "", st)
          if (st ~ /^ignoredSkills:/) { in_block = 1; key_indent = index($0, st) - 1 }
          next
        }
        st = $0; sub(/^[ \t]+/, "", st)
        if (st == "") next                          # blank inside block keeps parsing
        indent = index($0, st) - 1
        if (indent <= key_indent) { in_block = 0; next }   # sibling key ends the block
        if (st ~ /^- /) {
          item = st; sub(/^- /, "", item)
          '"$CLEAN_ITEM"'
        }
      }
    ' "$CONF" 2>/dev/null || true)"
  else
    echo "skills-inventory.sh: no python3/awk for ignoredSkills parse; treating ignore list as empty" >&2
  fi
fi

in_ignored() {                                       # $1=name ; exact membership
  local name="$1" item
  [ -n "$ignored" ] || return 1
  while IFS= read -r item; do
    [ "$name" = "$item" ] && return 0
  done <<< "$ignored"
  return 1
}

strip_comment() { printf '%s' "${1%% \#*}"; }

read_frontmatter() {
  local f="$1" line lspace line_nw in_fm=0 desc_block=0 pending_name=0 rest rest_nw
  FM_NAME=""; FM_DESC=""; FM_ENABLED=1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_fm" = 0 ]; then
      [ "$line" = "---" ] && in_fm=1
      continue
    fi
    [ "$line" = "---" ] && break

    lspace=""; line_nw=""
    case "$line" in
      *[![:space:]]*)
        lspace="${line%%[![:space:]]*}"
        line_nw="${line#"$lspace"}"
        ;;
    esac

    if [ "$pending_name" = 1 ]; then
      [ -n "$line_nw" ] || continue                 # blank: keep waiting
      if [ -z "$lspace" ]; then
        pending_name=0                              # empty block value -> dirname fallback; fall through to key processing
      else
        FM_NAME="$(strip_comment "$line_nw")"
        pending_name=0
        continue                                    # consumed a block value line
      fi
    fi

    if [ "$desc_block" = 1 ]; then
      case "$line" in
        "") continue ;;                             # blank inside the fold
        *[![:space:]]*)
          if [ -n "$lspace" ]; then
            [ -n "$FM_DESC" ] && FM_DESC="$FM_DESC "
            FM_DESC="$FM_DESC$(strip_comment "$line_nw")"
            continue
          fi
          desc_block=0                              # column-0 line ends the fold
          ;;
      esac
    fi

    case "$line" in
      name:*)
        rest="${line#name:}"
        rest_nw="${rest#"${rest%%[![:space:]]*}"}"
        case "$rest_nw" in
          ">"|">-"|"|"|"|-") pending_name=1 ;;
          *)
            FM_NAME="$(strip_comment "${rest_nw%"${rest_nw##*[![:space:]]}"}")"
            FM_NAME="${FM_NAME%\"}"; FM_NAME="${FM_NAME#\"}"
            FM_NAME="${FM_NAME%\'}"; FM_NAME="${FM_NAME#\'}"
            ;;
        esac
        ;;
      description:*)
        rest="${line#description:}"
        rest_nw="${rest#"${rest%%[![:space:]]*}"}"
        case "$rest_nw" in
          ">"|">-"|"|"|"|-") FM_DESC=""; desc_block=1 ;;
          *)
            FM_DESC="$(strip_comment "${rest_nw%"${rest_nw##*[![:space:]]}"}")"
            FM_DESC="${FM_DESC%\"}"; FM_DESC="${FM_DESC#\"}"
            FM_DESC="${FM_DESC%\'}"; FM_DESC="${FM_DESC#\'}"
            ;;
        esac
        ;;
      enabled:*)
        rest="${line#enabled:}"
        rest_nw="${rest#"${rest%%[![:space:]]*}"}"
        rest_nw="${rest_nw%%[[:space:]]*}"          # first token (drops inline comment)
        rest_nw="${rest_nw%\"}"; rest_nw="${rest_nw#\"}"
        rest_nw="${rest_nw%\'}"; rest_nw="${rest_nw#\'}"
        case "$rest_nw" in
          false|False|0|no) FM_ENABLED=0 ;;
        esac
        ;;
    esac
  done < "$f"
}

emitted=""
already_emitted() {                                  # $1=name ; first occurrence wins
  local name="$1" e
  [ -n "$emitted" ] || return 1
  while IFS= read -r e; do
    [ "$name" = "$e" ] && return 0
  done <<< "$emitted"
  return 1
}

scan_skill() {                                       # $1=path to SKILL.md ; emit if active
  local s="$1" name dir_name
  [ -f "$s" ] || return 0
  read_frontmatter "$s"
  [ "$FM_ENABLED" = 1 ] || return 0
  dir_name="$(basename "$(dirname "$s")")"
  name="$FM_NAME"
  case "$name" in
    ">"|">-"|"|"|"|-") name="" ;;
  esac
  [ -n "$name" ] || name="$dir_name"
  in_ignored "$name" && return 0
  [ "$name" != "$dir_name" ] && in_ignored "$dir_name" && return 0
  already_emitted "$name" && return 0
  emitted="$emitted
$name"
  printf '%s\t%s\n' "$name" "$FM_DESC"
}

outdir="$(dirname "$outfile")"
mkdir -p "$outdir" 2>/dev/null || true
tmpfile="$(mktemp "$outdir/skills-inventory.XXXXXX" 2>/dev/null)" || {
  echo "skills-inventory.sh: cannot create a temp inventory in $outdir (unwritable?)" >&2
  exit 1
}

{
  printf '# skills-inventory.txt — authoritative active on-disk skill list for L2 (write: bin/skills-inventory.sh)\n'
  printf '# Lines: name<TAB>description. Excludes skills.ignoredSkills and frontmatter `enabled: false`.\n'
  printf '# Scanned: every $HOME/.claude* bucket (user skills + plugin skills) plus agent/opencode/OMP managed roots; deduplicated by name, first wins.\n'
  printf '# Built-in binary skills are compiled into the omp binary and are NOT listed — reconcile via the session skill surface.\n'

  for root in "$HOME/.agents/skills" "$HOME/.config/opencode/skills" "$HOME/.omp/agent/managed-skills"; do
    for s in "$root"/*/SKILL.md; do
      scan_skill "$s"
    done
  done

  for bucket in "$HOME"/.claude*; do
    [ -d "$bucket" ] || continue
    for s in "$bucket/skills"/*/SKILL.md; do
      scan_skill "$s"
    done
    if [ -d "$bucket/plugins" ]; then
      while IFS= read -r s; do
        scan_skill "$s"
      done < <(find "$bucket/plugins" -path '*/skills/*/SKILL.md' -type f 2>/dev/null)
    fi
  done
} > "$tmpfile"

if [ -f "$tmpfile" ] && mv -f "$tmpfile" "$outfile"; then
  exit 0
fi
echo "skills-inventory.sh: could not produce $outfile" >&2
rm -f "$tmpfile"
exit 1
