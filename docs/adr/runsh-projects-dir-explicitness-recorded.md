# runsh: PROJECTS_DIR's default is applied at startup and whether the caller set it is recorded separately

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`PROJECTS_DIR_EXPLICIT`, top of file)

## Context
Session-root resolution is SESSION_ROOTS, then PROJECTS_DIR (only when the caller chose it), then autodetect. `${PROJECTS_DIR:-default}` cannot tell "unset" from "set to the default value".

## Decision
`PROJECTS_DIR_EXPLICIT` is set from `${PROJECTS_DIR+x}` before the default is applied (a variable set but empty counts as explicit and takes the default value). `probe_roots` treats PROJECTS_DIR as a single root only when that flag is 1 and `SESSION_ROOTS` is empty. See CLAUDE.md, "Session roots: one dir is not the corpus".

## Consequences
Treating the always-present default as explicit would make autodetect unreachable (every run would be a single-root run). Do not collapse the flag into the `:-` default.
