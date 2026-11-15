#!/bin/bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=bin/portable.sh
. "$REPO/bin/portable.sh"
# shellcheck source=tests/lib-tmp.sh
. "$HERE/lib-tmp.sh"
suite_tmp adweb
tmo 90 env PYTHONDONTWRITEBYTECODE=1 python3 "$HERE/autodream-web.py"
