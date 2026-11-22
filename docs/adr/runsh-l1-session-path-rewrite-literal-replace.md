# runsh: the temp-copy path in a findings JSON is rewritten to the real session path with a literal jq replace, not sed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, success path)

## Context
The worker read a slim, normalized or day-cut copy, so the findings name that copy. `sed` would read a `#` or `&` in the session path as part of its own syntax, and a quote or backslash in the path would break the JSON.

## Decision
`jq --arg a <copy> --arg b <session> 'walk(if type == "string" then split($a) | join($b) else . end)'` replaces the copy's path inside every JSON string literally, then the copies are removed.

## Consequences
Do not switch to `sed` on the raw JSON text. The loop runs over the slim, normalized and day-cut copies in turn, and a rewrite that fails leaves the findings file as it was (the `.rw` temp is removed).
