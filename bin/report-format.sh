#!/bin/bash

QUESTIONS_BEGIN='AUTODREAM_QUESTIONS_BEGIN'
QUESTIONS_END='AUTODREAM_QUESTIONS_END'
QUESTIONS_EPOCH_DEFAULT='2026-10-27'

report_marker_count(){
  LC_ALL=C sed -n 's/.*<!-- *autodream:open-questions=\([0-9][0-9]*\) *-->.*/\1/p' "$1" 2>/dev/null | head -1
}

report_has_marker(){ LC_ALL=C grep -q 'autodream:open-questions=' "$1" 2>/dev/null; }

report_has_sentinel(){ LC_ALL=C grep -q '^AUTODREAM_REPORT_END$' "$1" 2>/dev/null; }

report_has_questions_block(){
  LC_ALL=C awk -v b="$QUESTIONS_BEGIN" -v e="$QUESTIONS_END" '
    $0 == b { open = 1; next }
    $0 == e { if (open) { closed = 1 } }
    END { exit closed ? 0 : 1 }' "$1" 2>/dev/null
}

report_questions(){
  local report="$1"
  if report_has_questions_block "$report"; then
    LC_ALL=C awk -v b="$QUESTIONS_BEGIN" -v e="$QUESTIONS_END" '
      $0 == b { if (!open) { open = 1 }; next }
      open { line[++n] = $0; if ($0 == e) last = n }
      END { for (i = 1; i < last; i++) print line[i] }' "$report" 2>/dev/null
    return 0
  fi
  LC_ALL=C awk '
    {
      if ($0 ~ /^[ \t]*(```+|~~~+)/) {
        tmp = $0; sub(/^[ \t]*/, "", tmp); ch = substr(tmp, 1, 1); n = 0
        while (substr(tmp, n + 1, 1) == ch) n++
        blank = (substr(tmp, n + 1) ~ /^[ \t\r]*$/)
        if (fence == "") { fence = ch; flen = n }
        else if (ch == fence && n >= flen && blank) { fence = ""; flen = 0 }
      }
      if (!capture) { if (fence == "" && $0 ~ /^## Open questions/) { capture = 1 }; next }
      if (fence == "" && $0 ~ /^## /) exit
      if (fence == "" && $0 ~ /^---[[:space:]]*$/) exit
      print
    }' "$report" 2>/dev/null
}

report_finishes(){
  local report="$1" date_label="${2:-}" epoch
  [ -s "$report" ] || return 1
  report_has_marker "$report" || return 1
  [ -n "$date_label" ] || return 0
  epoch="${AUTODREAM_QUESTIONS_EPOCH:-$QUESTIONS_EPOCH_DEFAULT}"
  if [[ ! "$date_label" < "$epoch" ]]; then
    report_has_questions_block "$report" || return 1
  fi
  return 0
}

report_last_line(){
  LC_ALL=C awk '
    { t = $0; sub(/\r$/, "", t) }
    t ~ /[^[:space:]]/ && t !~ /^<!-- autodream:remote-short=.* -->$/ { line = $0 }
    END { print line }' "$1" 2>/dev/null | LC_ALL=C sed 's/[[:space:]]*$//'
}

report_tail_question(){
  LC_ALL=C awk '
    { t = $0; sub(/\r$/, "", t) }
    t ~ /[^[:space:]]/ && t !~ /^<!-- autodream:remote-short=.* -->$/ { l[++n] = $0 }
    END {
      for (i = n; i >= 1 && i > n - 5; i--) {
        t = l[i]
        sub(/[[:space:]*_)"`\047]+$/, "", t)
        if (t ~ /\?$/) { print l[i]; exit }
      }
    }' "$1" 2>/dev/null | LC_ALL=C sed 's/[[:space:]]*$//'
}

report_cut_chars(){
  LC_ALL=C awk -v max="$1" '{
    n = 0; out = ""; cont = 0
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c < "\200") { cont = 0; n++ }
      else if (c >= "\365") { cont = 0; n++ }
      else if (c >= "\360") { cont = 3; n++ }
      else if (c >= "\340") { cont = 2; n++ }
      else if (c >= "\302") { cont = 1; n++ }
      else if (c >= "\300") { cont = 0; n++ }
      else if (cont > 0) { cont-- }
      else { n++ }
      if (n > max) break
      out = out c
    }
    print out
  }'
}

report_last_line_excerpt(){
  local line
  line=$(report_tail_question "$1")
  [ -n "$line" ] || line=$(report_last_line "$1")
  printf '%s\n' "$line" | LC_ALL=C tr -d '[:cntrl:]' | report_cut_chars 80
}

report_incomplete_cause(){
  local report="$1"
  report_has_questions_block "$report" && return 0
  if report_has_marker "$report"; then
    printf 'an open-questions marker but no AUTODREAM_QUESTIONS_BEGIN/END block\n'
    return 0
  fi
  if [ -n "$(report_tail_question "$report")" ]; then
    printf 'no open-questions marker, and the report carries a question written as prose near its end, outside an AUTODREAM_QUESTIONS_BEGIN/END block\n'
  else
    printf 'no open-questions marker and no AUTODREAM_QUESTIONS_BEGIN/END block\n'
  fi
}

report_body(){
  LC_ALL=C awk '/^AUTODREAM_REPORT_END$/ { last=NR } { line[NR]=$0 } END { for (i=1; i<last; i++) print line[i] }' "$1"
}

report_after_sentinel(){ LC_ALL=C awk '/^AUTODREAM_REPORT_END$/ { f=1; next } f { print }' "$1" 2>/dev/null; }

report_pin_lines(){
  LC_ALL=C awk '
    /^AUTODREAM_REPORT_END$/ { last = NR }
    { line[NR] = $0 }
    END {
      for (i = last + 1; i <= NR; i++) {
        if (!inb && line[i] == "AUTODREAM_PINS_BEGIN") { inb = 1; continue }
        if (inb && line[i] == "AUTODREAM_PINS_END") { closed = 1; break }
        if (inb) buf[++n] = line[i]
      }
      if (closed) for (j = 1; j <= n; j++) if (buf[j] ~ /^\{/) print buf[j]
    }' "$1" 2>/dev/null
}

report_section_item_count(){
  LC_ALL=C awk -v h="## $2" 'index($0, h) == 1 { f = 1; next } /^## / { f = 0 } f' "$1" | LC_ALL=C grep -cE '^([-*]|[0-9]+\.) ' || true
}

report_open_questions(){
  local report="$1" marker section first

  marker=$(report_marker_count "$report")
  if [ -n "$marker" ]; then printf '%s\n' "$marker"; return 0; fi

  if LC_ALL=C grep -q '^No Claude Code sessions were modified' "$report"; then echo 0; return 0; fi

  section=$(LC_ALL=C awk '/^## Open questions/{f=1;next} /^## /{f=0} f' "$report")
  first=$(printf '%s\n' "$section" | LC_ALL=C grep -v '^[[:space:]]*$' | head -1)
  [ -n "$first" ] || { echo unknown; return 0; }

  case "$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]')" in
    none*) echo 0; return 0 ;;
  esac
  echo unknown
}

report_is_triaged(){ LC_ALL=C grep -q '^## Triage decisions' "$1"; }

report_progress_count(){ report_section_item_count "$1" 'Triage in progress'; }

report_decision_count(){ report_section_item_count "$1" 'Triage decisions'; }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "$#" -eq 2 ] && [ "$1" = open-questions ] && [ -r "$2" ]; then
    report_open_questions "$2"
  else
    printf 'Usage: report-format.sh open-questions REPORT\n' >&2
    exit 2
  fi
fi
