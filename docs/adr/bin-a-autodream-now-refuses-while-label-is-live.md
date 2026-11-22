# bin-a: autodream-now.sh refuses to launch while its label holds a live pid

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (the `launchctl print` block before the plist write)

## Context

Every on-demand run for an install shares one label, and the `bootout` that precedes a launch kills the process behind it. Launching a second date while the first was still running evicted the first mid-run, with no report and no error (#78).

## Decision

Before the plist is rewritten, `launchctl print` is captured and parsed for `pid = N`. A loaded job with a live pid is in flight: the script prints the date that holds the label and exits 75. A loaded job with no pid has finished and is safe to boot out. A failed `print` means the label is not loaded, so there is nothing to protect. The check runs before the plist is rewritten because the holder's date is read back out of the old plist. The output is captured first and parsed afterwards, because a pipeline under `pipefail` could lose a pid it had read.

## Consequences

Moving the check below the plist write loses the holder's date. A user who really wants to replace the run stops it first with the `launchctl bootout` command the message names.
