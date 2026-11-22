# tests-run-all: the L2 diag tests come from a recurring exit-143 incident and use probe shims shaped to the real hazards

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_l2_diag_written_on_exit_143`, `test_l2_diag_probes_never_fail_or_stall_the_run`, `test_l2_diag_long_command_lines_keep_the_sections_intact`)

## Context

Exit 143 on the L2 aggregator was seen on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02, with nothing in the log to say who sent the TERM (issue 42). A 143, 137 or 124 now writes `findings/<date>/l2-attempt-N.diag`. The probes behind it must never fail or stall the run.

- `AUTODREAM_LAUNCHD_LABEL` is set in the probe test because macOS resets `XPC_SERVICE_NAME` to `0` in a child process. Without it the label is empty and the per-label `launchctl` probe, the one the test makes hang, never runs. `run.sh` reads `${AUTODREAM_LAUNCHD_LABEL:-${XPC_SERVICE_NAME:-}}`.
- A real claude launch carries a very long argv. The `ps` shim answers with one 9000-byte line and no trailing newline, which is what lets a long line swallow the next section's heading.

## Decision

The probe test shims `launchctl` to hang and `ps`, `uptime`, `vm_stat`, `sysctl` and `pmset` to fail, and sets the label override so the hanging probe runs. The long-line test shims `ps` with the 9000-byte line without a newline.

## Consequences

If the label override is removed, the hung-probe assertion passes without exercising the hang. Adding a newline to the `ps` shim removes the case the test exists for.
