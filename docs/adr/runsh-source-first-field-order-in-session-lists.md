# runsh: in the tab-separated session lists the adapter name comes first and the path last

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots` writing `sessions.txt.src`, `build_source_sidecar` reading it)

## Context

The adapter name is a validated safe identifier with no tab, but a session path can hold any remaining oddity. With `read -r src sp`, the last variable absorbs the whole remainder of the line. The reverse order (path first) truncated any path holding a tab and silently lost its provenance.

## Decision

`scan_roots` writes `<src><TAB><path>` and `build_source_sidecar` reads it with `IFS=$'\t' read -r src sp`, so the path is absorbed whole by the last variable.

## Consequences

Do not reorder the columns, and do not add a field after the path. A new field goes before the path. Tab-bearing paths are also rejected at enumeration, see `session-path-newline-tab-rejected`, so this is a second guard rather than the only one.
