#!/bin/bash
suite_tmp() { # $1=short suite name
  SUITE_TMP=""
  trap 'rm -rf "${SUITE_TMP:-}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  local root="${TMPDIR:-/tmp}"
  SUITE_TMP=$(mktemp -d "${root%/}/$1-suite.XXXXXX") || return 1
  export TMPDIR="$SUITE_TMP"
}
