# rest: the inventory is written to a temp in the outfile's directory and renamed, and the script's exits tell usage and write failure apart from success

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (the `tmpfile` and `mv` block, the `usage` check)

## Context

The output is the file L2 reads. A half-written inventory would read as a short, authoritative list. The caller (`adapters/omp/adapter.sh`, verb `skills-inventory`) writes an unavailable sentinel whenever the script fails, so the exit code is the contract.

## Decision

- Exit 1 with a `usage:` line when `<outfile>` is missing.
- Create the output directory if needed, then `mktemp "$outdir/skills-inventory.XXXXXX"`. An unwritable directory exits 1 with `cannot create a temp inventory`.
- Write the whole inventory (four `#` header lines, then one `name<TAB>description` line per active skill) into the temp, then `mv -f` it onto `<outfile>`. A failed `mv` removes the temp and exits 1.
- Exit 0 on any successful emit, including zero skills found.

## Consequences

The temp lives in the destination directory so the rename stays on one filesystem. Success with zero skills and failure must stay distinguishable: an empty inventory is a valid answer, a failure is not, and the sentinel only fires on the exit code. The header line the script prints names `bin/skills-inventory.sh` as its writer, which is a historical path in a printed string and is not changed here.
