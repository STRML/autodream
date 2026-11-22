#!/bin/bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

if ! command -v python3 >/dev/null 2>&1; then
  echo "comment-count: python3 not found" >&2
  exit 2
fi

exec python3 -I "$here/comment-count.py" "$@"
