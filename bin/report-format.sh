#!/bin/bash
# Sourced, never executed. How a finished autodream report says what is still open.
# review.sh and pending-triage.sh both read these two facts, so they read them here.

# How many open questions the report says need a human call. Prints an integer,
# or "unknown" when it cannot tell (the caller must then launch the session).
#
# The marker is the contract: PROMPT.md makes L2 emit
# `<!-- autodream:open-questions=N -->` in the Open questions section. Reports
# written before that contract existed have no marker, so we fall back to
# reading the prose L2 has used consistently ("None that clear the triviality
# gate this run."). The fallback only ever recognises a shape it is sure about;
# everything else is "unknown" rather than a guess.
report_open_questions(){
  local report="$1" marker section first

  marker=$(sed -n 's/.*<!-- *autodream:open-questions=\([0-9][0-9]*\) *-->.*/\1/p' "$report" | head -1)
  if [ -n "$marker" ]; then printf '%s\n' "$marker"; return 0; fi

  # Empty-day stub: run.sh writes this when no sessions were modified at all.
  if grep -q '^No Claude Code sessions were modified' "$report"; then echo 0; return 0; fi

  section=$(awk '/^## Open questions/{f=1;next} /^## /{f=0} f' "$report")
  first=$(printf '%s\n' "$section" | grep -v '^[[:space:]]*$' | head -1)
  # No section at all, or an empty one: not a shape we recognise. Launch.
  [ -n "$first" ] || { echo unknown; return 0; }

  case "$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]')" in
    none*) echo 0; return 0 ;;
  esac
  echo unknown
}

report_is_triaged(){ grep -q '^## Triage decisions' "$1"; }
