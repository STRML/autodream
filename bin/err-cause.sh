# shellcheck shell=bash
err_cause_line() {
  local line
  line=$(tr -d '\r' < "$1" 2>/dev/null \
    | grep -v -i -e '^[[:space:]]*$' -e '^[[:space:]]*hint:' -e '^[[:space:]]*warning:' \
    | head -n 1 | tr '\t`<>' " '()" | tr -d '\000-\037\177' \
    | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')
  [ "${#line}" -le 200 ] || line="${line:0:197}..."
  printf '%s' "$line"
}
