#!/bin/bash
set -u

L2_BIN=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --l2-bin)
      [ "$#" -ge 2 ] || { printf 'preflight: --l2-bin requires a value\n' >&2; exit 2; }
      L2_BIN="$2"; shift 2
      ;;
    *) shift ;;
  esac
done

MISSING_KEYS=""
missing=0

_forced_missing() {
  case ",${AUTODREAM_PREFLIGHT_FORCE_MISSING:-}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

record_missing() {
  MISSING_KEYS="${MISSING_KEYS:+$MISSING_KEYS,}$1"
  missing=$((missing + 1))
}

need() {
  if _forced_missing "$1" || ! command -v "$1" >/dev/null 2>&1; then
    printf 'MISSING: %s — %s\n' "$1" "$2" >&2
    record_missing "$1"
  fi
}

need jq       "every findings record, sidecar and adapter manifest is parsed with it"
need shasum   "the artifact key is sha1 of the session path; without it the hash is empty and every session collides on one filename, silently"
if _forced_missing python3 || ! command -v python3 >/dev/null 2>&1; then
  printf 'DEGRADED: python3 — project-field normalisation will be skipped; L2 grouping may show duplicate projects\n' >&2
fi
need realpath "adapter directory containment and cwd canonicalisation; without it containment is weaker, which is the failure this check exists to prevent"

if [ -n "$L2_BIN" ] && ! command -v "$L2_BIN" >/dev/null 2>&1; then
  printf 'MISSING: %s — the configured L2 engine; no report is possible without it\n' "$L2_BIN" >&2
  record_missing l2_engine
fi

if [ "$missing" -ne 0 ]; then
  printf 'preflight_missing: %s\n' "$MISSING_KEYS"
  exit 1
fi
exit 0
