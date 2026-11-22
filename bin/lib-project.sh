#!/bin/bash

encode_project() {
  local cont=$'\200-\277' l4=$'\360-\367' l3=$'\340-\357' l2=$'\300-\337'
  printf '%s' "$1" | LC_ALL=C sed \
    -e "s/[$l4][$cont][$cont][$cont]/--/g" \
    -e "s/[$l3][$cont][$cont]/-/g" \
    -e "s/[$l2][$cont]/-/g" \
    | LC_ALL=C tr -c 'A-Za-z0-9-' '-'
}

canonical_project() {
  local real
  [ -e "$1" ] || return 1
  real=$(realpath "$1" 2>/dev/null) || return 1
  [ -n "$real" ] || return 1
  encode_project "$real"
}

session_hash() {
  local out h
  out=$(printf '%s' "$1" | shasum -a 1 2>/dev/null) || return 1
  [ -n "$out" ] || return 1
  h=${out:0:12}
  [ "${#h}" -eq 12 ] || return 1
  case "$h" in
    *[!0123456789abcdef]*) return 1 ;;
  esac
  printf '%s' "$h"
}
