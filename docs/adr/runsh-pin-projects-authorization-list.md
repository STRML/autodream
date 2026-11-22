# runsh: A project gets a pin cwd only when all its sessions agree on one usable cwd

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`pin_projects_from_rows`, `write_pin_projects`)

## Context
Anything looser stores one project's pin in another project's bank: a transcript sitting in a bucket its cwd does not encode to, or two directories that encode to one bucket (`/tmp/a_b` and `/tmp/a-b`).

## Decision
`pin_projects_from_rows` prints one `project<TAB>cwd` row per project. The cwd is filled only when the project has exactly one distinct cwd and it is not `?`; an unusable `?` still counts as a distinct cwd, so it makes the project ambiguous rather than vanishing. A project with no usable cwd keeps an empty column, and `apply-pins.sh` refuses its pins as `no_cwd`. `write_pin_projects` removes the old `pin-projects.tsv` first, so an authorization list from an earlier run never outlives a failed write, and fails when the build itself failed.

## Consequences
This file is the pin authorization list: do not loosen the single-cwd rule or build it from anything a model could have touched.
