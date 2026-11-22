#!/bin/bash
# path_state <path>: is there something at <path>, was there nothing, or could this user not tell?
# Returns 0 (present), 1 (absent) or 2 (cannot tell). Prints nothing.
#
# `[ -e p ]` answers false for a path that exists but cannot be reached: a symlink whose target sits in a
# directory this user cannot search, a path under an unsearchable parent. Code that reads false as "not
# there" then skips state it should have refused to run without. Here "absent" is believed only when the
# nearest ancestor that does exist is a directory this user can search; a symlink at the path itself that
# `-e` cannot follow is "cannot tell".
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
