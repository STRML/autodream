#!/bin/bash
path_state() {
  local p="$1" probe
  [ -e "$p" ] && return 0
  [ -L "$p" ] && return 2
  probe="$p"
  while [ ! -e "$probe" ] && [ ! -L "$probe" ] && [ "$probe" != / ] && [ "$probe" != . ]; do
    probe=$(dirname "$probe")
  done
  { [ -d "$probe" ] && [ -x "$probe" ]; } || return 2
  return 1
}
