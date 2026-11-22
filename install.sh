#!/bin/bash

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
cc-autodream installer.

Symlinks the scripts + prompts from this repo into ~/.claude/autodream/ and (on
macOS) installs the nightly launchd schedule so overnight runs Just Work.
Idempotent - safe to re-run.

Usage:
  ./install.sh                 # symlink into $HOME/.claude/ + schedule nightly job
  ./install.sh /path/to        # symlink into /path/to/autodream/ instead
  ./install.sh --no-schedule   # symlink only; don't touch launchd
  ./install.sh --no-review     # schedule the nightly but not the review triage popup agent
  ./install.sh --no-web        # schedule the nightly without the local web dashboard
  ./install.sh --no-skill      # don't link the global /autodream skill into ~/.claude/skills
  ./install.sh --adapters claude,omp   # harnesses a run scans (names or `all`); written to config
  ./install.sh --l2-engine omp         # adapter whose engine runs L2; written to config
  ./install.sh --dry-run       # show every change, make none (no links, config, plist, launchctl)
  ./install.sh -h|--help
EOF
}

SCHEDULE=1
REVIEW=1
WEB=1
SKILL=1
DRY=0
ADAPTERS_ARG=""
L2_ENGINE_ARG=""
TARGET_PARENT="$HOME/.claude"
while [ "$#" -gt 0 ]; do
  a="$1"; shift
  case "$a" in
    --no-schedule) SCHEDULE=0 ;;
    --no-review) REVIEW=0 ;;
    --no-web) WEB=0 ;;
    --no-skill) SKILL=0 ;;
    --dry-run) DRY=1 ;;
    --adapters|--l2-engine)
      [ "$#" -gt 0 ] && [ -n "$1" ] || { echo "install: $a needs a value" >&2; exit 64; }
      case "$a" in --adapters) ADAPTERS_ARG="$1" ;; *) L2_ENGINE_ARG="$1" ;; esac
      shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "install: unknown flag '$a'" >&2; exit 64 ;;
    *) TARGET_PARENT="$a" ;;
  esac
done
TARGET="$TARGET_PARENT/autodream"

valid_adapter() { [ -d "$REPO_DIR/adapters/$1" ] && [ -f "$REPO_DIR/adapters/$1/manifest.json" ]; }
if [ -n "$ADAPTERS_ARG" ]; then
  ADAPTERS_ARG=$(printf '%s' "$ADAPTERS_ARG" | tr ' ' ',')
  for _n in $(printf '%s' "$ADAPTERS_ARG" | tr ',' ' '); do
    [ "$_n" = "all" ] && continue
    case "$_n" in *[!a-z0-9_-]*|_*) echo "install: '$_n' is not a valid adapter name" >&2; exit 64 ;; esac
    valid_adapter "$_n" || { echo "install: no adapter '$_n' under $REPO_DIR/adapters" >&2; exit 64; }
  done
fi
if [ -n "$L2_ENGINE_ARG" ]; then
  valid_adapter "$L2_ENGINE_ARG" || { echo "install: no adapter '$L2_ENGINE_ARG' under $REPO_DIR/adapters" >&2; exit 64; }
fi

dry() { printf '  [dry-run] %s\n' "$*"; }
DRY_SCRATCH=""
if [ "$DRY" = 1 ]; then
  DRY_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/ccad-dry.XXXXXX")
  trap 'rm -rf "$DRY_SCRATCH"' EXIT
fi
if [ "$DRY" = 1 ]; then
  echo "DRY RUN: nothing below is written, linked, loaded or run."
  dry "mkdir -p $TARGET $TARGET_PARENT/dreams $TARGET/findings $TARGET/inbox $TARGET/logs"
else
  mkdir -p "$TARGET" "$TARGET_PARENT/dreams" "$TARGET/findings" "$TARGET/inbox" "$TARGET/logs"
fi

link() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "  WARNING: skipping $dst — source missing: $src" >&2
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    if [ -d "$dst" ] && [ ! -L "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
      echo "  ERROR: $dst is a non-empty real directory; refusing to install over it." >&2
      return 1
    fi
    dry "link $dst -> $src"
    return 0
  fi
  if [ -L "$dst" ] || [ -f "$dst" ]; then
    rm -f "$dst"
  elif [ -d "$dst" ]; then
    if [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
      echo "  ERROR: $dst is a non-empty real directory; refusing to install over it." >&2
      echo "         Move or remove it, then re-run install.sh." >&2
      return 1
    fi
    rmdir "$dst" 2>/dev/null || {
      echo "  ERROR: could not remove existing directory $dst; refusing to continue." >&2
      return 1
    }
  fi
  ln -s "$src" "$dst" || return 1
  echo "  $dst -> $src"
}

echo "Installing cc-autodream into $TARGET"
link "$REPO_DIR/bin/run.sh"             "$TARGET/run.sh"
link "$REPO_DIR/bin/autodream-now.sh"   "$TARGET/autodream-now.sh"
link "$REPO_DIR/bin/autodream-note.sh"  "$TARGET/autodream-note.sh"
link "$REPO_DIR/bin/review.sh"          "$TARGET/review.sh"
link "$REPO_DIR/bin/notify.sh"          "$TARGET/notify.sh"
link "$REPO_DIR/bin/make-notifier.sh"   "$TARGET/make-notifier.sh"
link "$REPO_DIR/bin/prune-self-sessions.sh" "$TARGET/prune-self-sessions.sh"
link "$REPO_DIR/bin/slim-transcript.sh"     "$TARGET/slim-transcript.sh"
link "$REPO_DIR/bin/session-stats.sh"        "$TARGET/session-stats.sh"
link "$REPO_DIR/bin/session-window.sh"       "$TARGET/session-window.sh"
link "$REPO_DIR/bin/chunk-transcript.sh"      "$TARGET/chunk-transcript.sh"
link "$REPO_DIR/bin/merge-chunks.sh"           "$TARGET/merge-chunks.sh"
link "$REPO_DIR/bin/overlap-stats.sh"        "$TARGET/overlap-stats.sh"
link "$REPO_DIR/bin/scheduler-label.sh"      "$TARGET/scheduler-label.sh"
link "$REPO_DIR/bin/oversized-gate.sh"       "$TARGET/oversized-gate.sh"
link "$REPO_DIR/bin/failure-class.sh"        "$TARGET/failure-class.sh"
link "$REPO_DIR/bin/l1-confine.sh"           "$TARGET/l1-confine.sh"
link "$REPO_DIR/bin/portable.sh"             "$TARGET/portable.sh"
link "$REPO_DIR/bin/citation-check.sh"       "$TARGET/citation-check.sh"
link "$REPO_DIR/bin/rollup.sh"               "$TARGET/rollup.sh"
link "$REPO_DIR/bin/triage-dream.sh"         "$TARGET/triage-dream.sh"
link "$REPO_DIR/bin/dream-grounding.sh"      "$TARGET/dream-grounding.sh"
link "$REPO_DIR/bin/cookie-cadence.sh"       "$TARGET/cookie-cadence.sh"
link "$REPO_DIR/bin/vault-notes.sh"          "$TARGET/vault-notes.sh"
link "$REPO_DIR/bin/autodream-focus.sh"      "$TARGET/autodream-focus.sh"
link "$REPO_DIR/bin/x-bookmarks.sh"          "$TARGET/x-bookmarks.sh"
link "$REPO_DIR/bin/prune-worktrees.sh"      "$TARGET/prune-worktrees.sh"
link "$REPO_DIR/bin/triage-candidates.sh"    "$TARGET/triage-candidates.sh"
link "$REPO_DIR/bin/question-streaks.sh"     "$TARGET/question-streaks.sh"
link "$REPO_DIR/bin/threads.sh"                "$TARGET/threads.sh"
link "$REPO_DIR/bin/threads-status.jq"           "$TARGET/threads-status.jq"
link "$REPO_DIR/bin/threads-render.py"          "$TARGET/threads-render.py"
link "$REPO_DIR/bin/autodream-web"            "$TARGET/autodream-web"
link "$REPO_DIR/bin/autodream-web.py"         "$TARGET/autodream-web.py"
link "$REPO_DIR/bin/autodream_web_data.py"    "$TARGET/autodream_web_data.py"
link "$REPO_DIR/web"                          "$TARGET/web"
link "$REPO_DIR/templates/threads.html"         "$TARGET/threads-template.html"
link "$REPO_DIR/bin/apply-pins.sh"           "$TARGET/apply-pins.sh"
link "$REPO_DIR/bin/root-probe.sh"           "$TARGET/root-probe.sh"
link "$REPO_DIR/bin/lib-project.sh"           "$TARGET/lib-project.sh"
link "$REPO_DIR/bin/lib-flock.sh"             "$TARGET/lib-flock.sh"
link "$REPO_DIR/bin/lib-install-dir.sh"       "$TARGET/lib-install-dir.sh"
link "$REPO_DIR/bin/adapters.sh"              "$TARGET/adapters.sh"
link "$REPO_DIR/bin/preflight.sh"             "$TARGET/preflight.sh"
link "$REPO_DIR/bin/report-format.sh"          "$TARGET/report-format.sh"
link "$REPO_DIR/bin/l2-prompt.sh"              "$TARGET/l2-prompt.sh"
link "$REPO_DIR/bin/pending-triage.sh"        "$TARGET/pending-triage.sh"
link "$REPO_DIR/bin/remote-sync.sh"           "$TARGET/remote-sync.sh"
link "$REPO_DIR/bin/err-cause.sh"             "$TARGET/err-cause.sh"
link "$REPO_DIR/adapters"                     "$TARGET/adapters"
link "$REPO_DIR/prompts/PROMPT.md"      "$TARGET/PROMPT.md"
link "$REPO_DIR/prompts/SESSION_TRIAGE.md" "$TARGET/SESSION_TRIAGE.md"
link "$REPO_DIR/prompts/THREAD_LINKER.md" "$TARGET/THREAD_LINKER.md"
link "$REPO_DIR/prompts/TRIAGE_DREAM.md"   "$TARGET/TRIAGE_DREAM.md"
link "$REPO_DIR/prompts/L2_SYSTEM.txt"      "$TARGET/L2_SYSTEM.txt"

if [ "$SKILL" = 1 ] && [ -z "${AUTODREAM_SKILLS_DIR:-}" ] && [ "$(printf '%s' "$TARGET_PARENT" | sed 's:/*$::')" != "$HOME/.claude" ]; then
  echo "  /autodream skill not linked: $TARGET_PARENT is not ~/.claude. Set AUTODREAM_SKILLS_DIR to link it, and export AUTODREAM_DIR=$TARGET."
elif [ "$SKILL" = 1 ]; then
  SKILLS_DIR="${AUTODREAM_SKILLS_DIR:-$HOME/.claude/skills}"
  if [ "$DRY" = 1 ]; then dry "mkdir -p $SKILLS_DIR"; else mkdir -p "$SKILLS_DIR"; fi
  if { [ -e "$SKILLS_DIR/autodream" ] || [ -L "$SKILLS_DIR/autodream" ]; } \
     && [ "$(readlink "$SKILLS_DIR/autodream" 2>/dev/null)" != "$REPO_DIR/skills/autodream" ]; then
    echo "  /autodream skill not linked: $SKILLS_DIR/autodream already exists and is not this repo's. Move it, then re-run install.sh." >&2
  else
    link "$REPO_DIR/skills/autodream" "$SKILLS_DIR/autodream" || echo "  WARNING: /autodream skill not linked (see above); re-run after moving $SKILLS_DIR/autodream" >&2
  fi
fi

if [ "$DRY" = 1 ]; then dry "chmod +x bin/*.sh adapters/*/adapter.sh"; else
chmod +x "$REPO_DIR/bin/"*.sh
chmod +x "$REPO_DIR/adapters/"*/adapter.sh 2>/dev/null || true
fi

if [ "$DRY" = 1 ]; then
  dry "root-probe --default-index, then rewrite the managed SESSION_ROOTS section of $TARGET/config"
elif [ -x "$TARGET/root-probe.sh" ]; then
  CONFIG="$TARGET/config"
  if [ -t 1 ]; then
    AUTODREAM_DIR="$TARGET" "$TARGET/root-probe.sh" --ask
  else
    echo "  non-interactive install: indexing any unasked Claude folders (edit root-choices.conf to change)"
    AUTODREAM_DIR="$TARGET" "$TARGET/root-probe.sh" --default-index
  fi
  if [ -f "$CONFIG" ]; then
    awk '
      /^# claude-folder-indexing/{skip=1; next}
      skip && /^SESSION_ROOTS=/{next}
      skip && /^[^#]/{skip=0}
      {print}
    ' "$CONFIG" > "$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
  fi
  { echo; AUTODREAM_DIR="$TARGET" "$TARGET/root-probe.sh" --write-config; } >> "$CONFIG"
  echo "  session roots written to $CONFIG (see root-choices.conf to adjust)"
fi

if [ "$DRY" = 1 ]; then dry "build the notifier bundle (make-notifier.sh)"; else
AUTODREAM_DIR="$TARGET" "$REPO_DIR/bin/make-notifier.sh" || true
fi

if [ -n "$ADAPTERS_ARG" ] || [ -n "$L2_ENGINE_ARG" ]; then
  CONFIG="$TARGET/config"
  if [ -f "$CONFIG" ]; then
    [ -n "$ADAPTERS_ARG" ] || ADAPTERS_ARG=$(sed -n 's/^AUTODREAM_ADAPTERS=//p' "$CONFIG" | tail -n 1)
    [ -n "$L2_ENGINE_ARG" ] || L2_ENGINE_ARG=$(sed -n 's/^AUTODREAM_L2_ENGINE=//p' "$CONFIG" | tail -n 1)
  fi
  if [ "$DRY" = 1 ]; then
    dry "write to $CONFIG: ${ADAPTERS_ARG:+AUTODREAM_ADAPTERS=$ADAPTERS_ARG }${L2_ENGINE_ARG:+AUTODREAM_L2_ENGINE=$L2_ENGINE_ARG}"
  else
    touch "$CONFIG"
    awk '
      /^# adapters \(managed by install.sh\)/{skip=1; next}
      skip && /^(AUTODREAM_ADAPTERS|AUTODREAM_L2_ENGINE)=/{next}
      skip && /^[^#]/{skip=0}
      {print}
    ' "$CONFIG" > "$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
    {
      echo
      echo "# adapters (managed by install.sh)"
      [ -n "$ADAPTERS_ARG" ] && echo "AUTODREAM_ADAPTERS=$ADAPTERS_ARG"
      [ -n "$L2_ENGINE_ARG" ] && echo "AUTODREAM_L2_ENGINE=$L2_ENGINE_ARG"
    } >> "$CONFIG"
    echo "  adapters written to $CONFIG"
  fi
fi

lctl() {
  if [ "$DRY" = 1 ]; then dry "launchctl $*"; return 0; fi
  launchctl "$@"
}
show_plist() {
  [ "$DRY" = 1 ] || return 0
  dry "would write $real_la_dir/$(basename "$1"):"
  sed 's/^/        /' "$1"
}

xml_escape() {
  printf '%s' "$1" | sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

web_arguments_owned() {
  case "$1" in /*/python3|/*/python3.[0-9]*) ;; *) return 1 ;; esac
  case "$2" in */autodream-web.py) ;; *) return 1 ;; esac
  [ "$3" = serve ] || return 1
  local script_dir target_dir
  script_dir=$(cd "$(dirname "$2")" 2>/dev/null && pwd -P) || return 1
  target_dir=$(cd "$TARGET" 2>/dev/null && pwd -P) || return 1
  [ "$script_dir" = "$target_dir" ]
}

web_plist_owned() {
  local plist="$1" executable script verb
  executable=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null) || return 1
  script=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$plist" 2>/dev/null) || return 1
  verb=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$plist" 2>/dev/null) || return 1
  web_arguments_owned "$executable" "$script" "$verb"
}

web_agent_conflict() {
  local label="$1" destination="$2" plist found loaded executable script verb
  if { [ -e "$destination" ] || [ -L "$destination" ]; } && ! web_plist_owned "$destination"; then
    return 0
  fi
  for plist in "$HOME/Library/LaunchAgents/"*.plist; do
    [ -e "$plist" ] || continue
    found=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null) || continue
    [ "$found" = "$label" ] || continue
    web_plist_owned "$plist" || return 0
  done
  if loaded=$(launchctl print "gui/$(id -u)/$label" 2>/dev/null); then
    executable=$(printf '%s\n' "$loaded" | web_loaded_argument 1)
    script=$(printf '%s\n' "$loaded" | web_loaded_argument 2)
    verb=$(printf '%s\n' "$loaded" | web_loaded_argument 3)
    web_arguments_owned "$executable" "$script" "$verb" || return 0
  else
    [ "$?" -eq 113 ] || return 0
  fi
  return 1
}

web_loaded_argument() {
  awk -v ordinal="$1" '
    /^[[:space:]]*arguments = \{$/ {args=1; next}
    args && /^[[:space:]]*\}/ {exit}
    args {sub(/^[[:space:]]+/, ""); if (++n == ordinal) {print; exit}}
  '
}

install_web_agent() {
  local label="$1" path_val="$2" cmux_bin="$3" claude_bin="$4" dreams_xml="$5"
  local la_dir="$HOME/Library/LaunchAgents" domain
  domain="gui/$(id -u)"
  local real_la_dir="$la_dir" web_label="${label}-web" cfg_web="" cfg_port=""
  local web_off="" python_bin="" web_port="" plist_path=""
  local path_xml home_xml target_xml python_xml cmux_xml claude_xml port_xml
  [ "$DRY" = 1 ] && la_dir="$DRY_SCRATCH"
  cfg_web=$(cfg_get AUTODREAM_WEB)
  cfg_port=$(cfg_get AUTODREAM_WEB_PORT)
  if [ "$WEB" = 0 ]; then
    web_off="--no-web"
  else
    case "${AUTODREAM_WEB-$cfg_web}" in
      0|no|off|false|NO|OFF|FALSE) web_off="AUTODREAM_WEB=${AUTODREAM_WEB-$cfg_web}" ;;
    esac
  fi
  if [ -n "$web_off" ]; then
    echo "  web LaunchAgent not provisioned ($web_off)"
  else
    python_bin=$(PATH="$path_val" command -v python3 2>/dev/null || true)
    case "$python_bin" in /*) ;; *) python_bin="" ;; esac
    if [ -z "$python_bin" ] || [ ! -x "$python_bin" ]; then
      echo "  ! python3 not found; skipping web LaunchAgent"
      web_off="python3 unavailable"
    fi
  fi
  plist_path="$real_la_dir/$web_label.plist"
  if web_agent_conflict "$web_label" "$plist_path"; then
    echo "  ! web LaunchAgent skipped: ownership conflict for $web_label ($plist_path)"
    return 0
  fi
  if [ -n "$web_off" ]; then
    lctl bootout "$domain/$web_label" 2>/dev/null || true
    if [ "$DRY" = 1 ]; then
      [ -e "$plist_path" ] && dry "rm $plist_path"
    else
      rm -f "$plist_path"
    fi
    return 0
  fi
  [ "$DRY" = 1 ] || mkdir -p "$la_dir"
  web_port="${AUTODREAM_WEB_PORT-${cfg_port:-47823}}"
  [ -n "$web_port" ] || web_port=47823
  path_xml=$(xml_escape "$path_val")
  home_xml=$(xml_escape "$HOME")
  target_xml=$(xml_escape "$TARGET")
  python_xml=$(xml_escape "$python_bin")
  cmux_xml=$(xml_escape "$cmux_bin")
  claude_xml=$(xml_escape "$claude_bin")
  port_xml=$(xml_escape "$web_port")
  local target_plist="$la_dir/$web_label.plist"
  cat > "$target_plist" <<PLIST || { echo "  ERROR: could not write $target_plist" >&2; return 1; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$web_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$python_xml</string>
        <string>$target_xml/autodream-web.py</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>60</integer>
    <key>ProcessType</key><string>Background</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$path_xml</string>
        <key>HOME</key><string>$home_xml</string>
        <key>AUTODREAM_DIR</key><string>$target_xml</string>
        <key>DREAMS_DIR</key><string>$dreams_xml</string>
        <key>AUTODREAM_WEB_PORT</key><string>$port_xml</string>
        <key>CMUX_BIN</key><string>$cmux_xml</string>
        <key>CLAUDE_BIN</key><string>$claude_xml</string>
    </dict>
    <key>StandardOutPath</key><string>$target_xml/logs/web-launch.out.log</string>
    <key>StandardErrorPath</key><string>$target_xml/logs/web-launch.err.log</string>
</dict>
</plist>
PLIST
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$target_plist" >/dev/null || {
      echo "  ! generated web plist failed plutil lint: $target_plist" >&2
      return 1
    }
  fi
  show_plist "$target_plist"
  lctl bootout "$domain/$web_label" 2>/dev/null || true
  lctl bootstrap "$domain" "$target_plist" || {
    echo "  ERROR: launchctl bootstrap failed for $web_label ($target_plist)" >&2
    return 1
  }
  echo "  scheduled: $web_label  (RunAtLoad, restart on failure)  -> $target_plist"
}

ephemeral_dir() {
  local d p pr list
  list="${AUTODREAM_EPHEMERAL_DIRS-${TMPDIR:-}:/tmp:/private/tmp:/var/folders:/private/var/folders}"
  [ -n "$list" ] || return 1
  d=$(cd "$1" 2>/dev/null && pwd -P) || d="$1"
  local IFS=:
  for p in $list; do
    [ -n "$p" ] || continue
    pr=$(cd "$p" 2>/dev/null && pwd -P) || pr="$p"
    [ -n "${pr%/}" ] || continue
    case "$d/" in "${pr%/}"/*) return 0 ;; esac
  done
  return 1
}

cfg_get() {
  [ -f "$TARGET/config" ] || return 0
  AUTODREAM_DIR="$TARGET" bash -c 'unset "$2"; . "$1" >/dev/null 2>&1; v="$2"; printf "%s" "${!v:-}"' _ "$TARGET/config" "$1"
}

config_bin_dir() {
  local path
  path=$(cfg_get "$1")
  [ -n "$path" ] && [ -f "$path" ] && [ -x "$path" ] && [ "${path#/}" != "$path" ] \
    && ! ephemeral_dir "$(dirname "$path")" && dirname "$path"
}

adapter_bin_dirs() {
  local list="$ADAPTERS_ARG" l2="$L2_ENGINE_ARG" a m
  [ -n "$list" ] || list=$(cfg_get AUTODREAM_ADAPTERS)
  [ -n "$l2" ] || l2=$(cfg_get AUTODREAM_L2_ENGINE)
  list=$(printf '%s' "${list:-claude}" | tr -d "\"'" | tr ',' ' ')
  for a in $list; do
    if [ "$a" = all ]; then
      for m in "$REPO_DIR"/adapters/*/manifest.json; do
        [ -e "$m" ] || continue
        adapter_bin_dirs_one "$(basename "$(dirname "$m")")" "$1"
      done
    else
      adapter_bin_dirs_one "$a" "$1"
    fi
  done
  [ -z "$l2" ] || adapter_bin_dirs_one "$(printf '%s' "$l2" | tr -d "\"'")" "$1"
}
adapter_bin_dirs_one() {
  local m="$REPO_DIR/adapters/$1/manifest.json" bin var b
  case "$1" in ""|_*|*[!a-z0-9_-]*) return 0 ;; esac
  [ -f "$m" ] || return 0
  bin=$(sed -n 's/.*"engine_bin"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$m" | head -n 1)
  [ -n "$bin" ] || return 0
  var="$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')_BIN"
  config_bin_dir "$var" && return 0
  b=$(PATH="$2" command -v "$bin" 2>/dev/null) || return 0
  case "$b" in /*) dirname "$b" ;; esac
}

x_browser_bin_dirs() {
  [ "$(cfg_get AUTODREAM_X_FETCH)" = browser ] || return 0
  local b
  if ! config_bin_dir X_BROWSER_BIN && b=$(PATH="$1" command -v agent-browser 2>/dev/null); then
    case "$b" in /*) dirname "$b" ;; esac
  fi
  if b=$(PATH="$1" command -v node 2>/dev/null); then
    case "$b" in /*) dirname "$b" ;; esac
  fi
  return 0
}

install_schedule() {
  local la_dir="$HOME/Library/LaunchAgents" real_la_dir
  real_la_dir="$la_dir"
  if [ "$DRY" = 1 ]; then
    la_dir="$DRY_SCRATCH"
  else
    mkdir -p "$la_dir"
  fi

  local label="" rc=0
  label="$("$REPO_DIR/bin/scheduler-label.sh" "$TARGET")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  Skipping the schedule. Fix the conflict above, or re-run with --no-schedule." >&2
    return "$rc"
  fi

  local path_dirs="" tool b d CLAUDE_BIN_ABS="" clean_path="" skipped_dirs="" old_ifs="$IFS"
  IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if ephemeral_dir "$d"; then skipped_dirs="${skipped_dirs:+$skipped_dirs }$d"
    else clean_path="${clean_path:+$clean_path:}$d"; fi
  done
  IFS="$old_ifs"
  [ -z "$skipped_dirs" ] || echo "  note: ignoring PATH entries under a temp directory (launchd will not have them): $skipped_dirs"
  for tool in claude git bash rsync; do
    if b="$(PATH="$clean_path" command -v "$tool" 2>/dev/null)"; then
      if [ "$tool" = "claude" ] && [ -n "$b" ]; then
        CLAUDE_BIN_ABS="$b"
      fi
      d="$(cd "$(dirname "$b")" && pwd)"
      case ":$path_dirs:" in *":$d:"*) ;; *) path_dirs="${path_dirs:+$path_dirs:}$d" ;; esac
    fi
  done
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    d="$(cd "$d" 2>/dev/null && pwd)" || continue
    case ":$path_dirs:" in *":$d:"*) ;; *) path_dirs="${path_dirs:+$path_dirs:}$d" ;; esac
  done < <(adapter_bin_dirs "$clean_path"; x_browser_bin_dirs "$clean_path")
  local path_val="${path_dirs:+$path_dirs:}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  local reports_dir dreams_xml
  reports_dir="${DREAMS_DIR-$(cfg_get DREAMS_DIR)}"
  dreams_xml=$(xml_escape "${reports_dir:-$TARGET_PARENT/dreams}")

  local target_plist="$la_dir/$label.plist"
  local domain
  domain="gui/$(id -u)"

  cat > "$target_plist" <<PLIST || { echo "  ERROR: could not write $target_plist" >&2; return 1; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$TARGET/run.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>15</integer></dict>
        <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>15</integer></dict>
        <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>15</integer></dict>
        <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>15</integer></dict>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$path_val</string>
        <key>HOME</key><string>$HOME</string>
        <key>AUTODREAM_DIR</key><string>$TARGET</string>
        <key>DREAMS_DIR</key><string>$dreams_xml</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$TARGET/logs/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET/logs/launchd.err.log</string>
</dict>
</plist>
PLIST

  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$target_plist" >/dev/null || {
      echo "  ! generated plist failed plutil lint: $target_plist" >&2
      return 1
    }
  fi
  show_plist "$target_plist"

  lctl bootout   "$domain/$label" 2>/dev/null || true
  lctl bootstrap "$domain" "$target_plist" || {
    echo "  ERROR: launchctl bootstrap failed for $label ($target_plist)" >&2
    return 1
  }
  echo "  scheduled: $label  (daily 03:15/06:15/09:15/12:15)  -> $target_plist"

  local cfg_cmux="" cfg_claude="" cfg_review=""
  cfg_review=$(cfg_get AUTODREAM_REVIEW_AGENT); cfg_review=${cfg_review//\"/}
  cfg_cmux=$(cfg_get CMUX_BIN); cfg_cmux=${cfg_cmux//\"/}
  cfg_claude=$(cfg_get CLAUDE_BIN); cfg_claude=${cfg_claude//\"/}
  CMUX_DEFAULT="${AUTODREAM_CMUX_DEFAULT:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
  CMUX_FOUND=""
  { [ -n "$cfg_cmux" ] && [ -x "$cfg_cmux" ]; } && CMUX_FOUND="$cfg_cmux"
  { [ -z "$CMUX_FOUND" ] && PATH="$clean_path" command -v cmux >/dev/null 2>&1; } && CMUX_FOUND=$(PATH="$clean_path" command -v cmux)
  { [ -z "$CMUX_FOUND" ] && [ -x "$CMUX_DEFAULT" ]; } && CMUX_FOUND="$CMUX_DEFAULT"
  if [ -n "$CMUX_FOUND" ] && [ "${CMUX_FOUND#/}" = "$CMUX_FOUND" ]; then
    echo "  ! cmux at $CMUX_FOUND is relative; review LaunchAgent needs an absolute path" >&2
    CMUX_FOUND=""
  fi
  CMUX_FOUND_XML=$(xml_escape "${CMUX_FOUND:-}")
  local eff_claude="" cand
  for cand in "$cfg_claude" "$CLAUDE_BIN_ABS"; do
    if [ -n "$cand" ] && [ -f "$cand" ] && [ -x "$cand" ]; then eff_claude="$cand"; break; fi
  done
  local review_off=""
  if [ "$REVIEW" = 0 ]; then review_off="--no-review"
  else
    case "${AUTODREAM_REVIEW_AGENT-$cfg_review}" in
      0|no|off|false|NO|OFF|FALSE) review_off="AUTODREAM_REVIEW_AGENT=${AUTODREAM_REVIEW_AGENT-$cfg_review}" ;;
    esac
  fi
  if [ -z "$eff_claude" ] && [ -z "$review_off" ]; then
    echo "  ! claude binary not usable (config [${cfg_claude}], PATH [${CLAUDE_BIN_ABS}]); review LaunchAgent will abort every trigger"
  fi
  CLAUDE_BIN_XML=$(xml_escape "$eff_claude")
  install_web_agent "$label" "$path_val" "$CMUX_FOUND" "$eff_claude" "$dreams_xml" || return $?
  local review_label="${label}-review"
  if [ -n "$review_off" ] || [ -z "$CMUX_FOUND" ] || [ -z "$eff_claude" ]; then
    if [ -n "$review_off" ]; then
      echo "  review LaunchAgent not provisioned ($review_off)"
    elif [ -z "$CMUX_FOUND" ]; then
      echo "  ! cmux not found (config CMUX_BIN, PATH, or $CMUX_DEFAULT); skipping review LaunchAgent"
    else
      echo "  ! claude binary not usable; skipping review LaunchAgent"
    fi
    lctl bootout "$domain/$review_label" 2>/dev/null || true
    if [ "$DRY" = 1 ]; then
      [ -e "$real_la_dir/$review_label.plist" ] && dry "rm $real_la_dir/$review_label.plist"
      :
    else
      rm -f "$la_dir/$review_label.plist"
    fi
    return 0
  fi
  local review_plist="$la_dir/$review_label.plist"
  cat > "$review_plist" <<PLIST || { echo "  ERROR: could not write $review_plist" >&2; return 1; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$review_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>exec "\$1" "\$(date -v-1d +%Y-%m-%d)"</string>
        <string>triage</string>
        <string>$TARGET/review.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>15</integer></dict>
        <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>15</integer></dict>
        <dict><key>Hour</key><integer>15</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>15</integer></dict>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$path_val</string>
        <key>HOME</key><string>$HOME</string>
        <key>AUTODREAM_DIR</key><string>$TARGET</string>
        <key>DREAMS_DIR</key><string>$dreams_xml</string>
        <key>AUTODREAM_TRIAGE_SURFACE</key><string>cmux</string>
        <key>CMUX_BIN</key><string>${CMUX_FOUND_XML}</string>
        <key>CLAUDE_BIN</key><string>${CLAUDE_BIN_XML}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$TARGET/logs/review-launch.out.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET/logs/review-launch.err.log</string>
</dict>
</plist>
PLIST

  grep -qF '$(date -v-1d +%Y-%m-%d)' "$review_plist" || {
    echo "  ! review plist lost the fire-time date expression; aborting" >&2
    return 1
  }
  grep -qF 'exec "$1"' "$review_plist" || {
    echo "  ! review plist lost the argv path reference; aborting" >&2
    return 1
  }

  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$review_plist" >/dev/null || {
      echo "  ! generated review plist failed plutil lint: $review_plist" >&2
      return 1
    }
  fi
  show_plist "$review_plist"
  lctl bootout   "$domain/$review_label" 2>/dev/null || true
  lctl bootstrap "$domain" "$review_plist" || {
    echo "  ERROR: launchctl bootstrap failed for $review_label ($review_plist)" >&2
    return 1
  }
  echo "  scheduled: $review_label  (daily 08:00/09:15/12:15/15:30/18:15)  -> $review_plist"
  return 0
}

echo
if [ "$SCHEDULE" = 1 ] && command -v launchctl >/dev/null 2>&1; then
  echo "Installing nightly schedule (launchd):"
  schedule_rc=0
  install_schedule || schedule_rc=$?
  if [ "$schedule_rc" -eq 3 ]; then
    echo "  Schedule not installed: another install holds our label. Everything else is in place." >&2
  elif [ "$schedule_rc" -ne 0 ]; then
    echo "  Schedule FAILED (exit $schedule_rc). The symlinks are installed; the schedule is not." >&2
    exit "$schedule_rc"
  fi
  if [ "$schedule_rc" -eq 0 ]; then
    echo
    echo "  Guarantee the Mac is awake for the 03:15 trigger (launchd won't wake it):"
    echo "    sudo pmset repeat wake MTWRFSU 03:10:00"
  fi
elif [ "$SCHEDULE" = 1 ]; then
  echo "Skipping schedule: launchctl not found (not macOS?). See launchd/ for the template."
else
  echo "Skipping schedule (--no-schedule). See launchd/com.user.autodream.plist.example to add one."
fi

echo
echo "Installed. Try:"
echo "  $TARGET/run.sh \$(date -v-1d +%Y-%m-%d)   # process yesterday"
echo "  $TARGET/review.sh                        # triage the latest report"
