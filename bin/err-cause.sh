# shellcheck shell=bash
# The cause line of a failed tool's stderr, cleaned for a one-line report. Sourced by run.sh (the
# changelog sections) and remote-sync.sh (the remote_sync_<label>_cause key), so both quote a
# failure the same way.
#
# The FIRST line that is not blank, `hint:` or `warning:` (any case: OpenSSH prints `Warning:
# Permanently added ...` before the real error), because git and rsync both end with boilerplate
# that says nothing. Backticks and angle brackets would open a code span or an HTML tag in the
# markdown L2 reads, so they are swapped out; control characters go; length is capped at 200.
err_cause_line() { # $1=stderr file
  local line
  line=$(tr -d '\r' < "$1" 2>/dev/null \
    | grep -v -i -e '^[[:space:]]*$' -e '^[[:space:]]*hint:' -e '^[[:space:]]*warning:' \
    | head -n 1 | tr '\t`<>' " '()" | tr -d '\000-\037\177' \
    | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')
  [ "${#line}" -le 200 ] || line="${line:0:197}..."
  printf '%s' "$line"
}
