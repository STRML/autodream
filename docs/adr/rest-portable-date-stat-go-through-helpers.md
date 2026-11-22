# rest: date and stat calls go through portable.sh, whose date parsing is strict on purpose

Status: accepted · Date: 2026-10-07 · Code: `bin/portable.sh` (`pdate_*`, `pstat_*`, `repo_slug`)

## Context

The scripts and tests called `date -v`, `date -j -f` and `stat -f` directly, which is why the whole suite needed a macOS runner. `portable.sh` is sourced, never executed, by the scripts and by the suite, so the pure-logic suites run on Linux (#153; CLAUDE.md, "Tests"). GNU `date -d` also accepts "tomorrow" and "last friday", while BSD `date -j -f %Y-%m-%d` does not, so a caller handed garbage would fail on one platform and not the other.

## Decision

Every caller goes through these functions. Each tool is detected on its own (`_P_GNU_DATE`, `_P_GNU_STAT`), because a Mac with coreutils' gnubin on PATH has a GNU date and a BSD stat. Dates are checked for shape first (`_p_is_date`, `_p_is_stamp`, `_p_is_int`) so garbage fails the same way on both.

- `pdate_yesterday` prints yesterday, local time, `YYYY-MM-DD`.
- `pdate_shift <YYYY-MM-DD> <signed whole number> <d|y>` prints the shifted date; exit 1 on a bad date, number or unit.
- `pdate_epoch "<YYYY-MM-DD HH:MM:SS>"` (local) prints epoch seconds, exit 1 when it does not parse; a bare `YYYY-MM-DD` is midnight.
- `pdate_fmt_epoch <epoch> <+FORMAT>` prints the epoch formatted in local time (`TZ=UTC pdate_fmt_epoch` for UTC).
- `pstat_mtime <file>` prints the mtime in epoch seconds; `pstat_mode <file>` the permission bits in octal with no leading zeros (600, 755).
- `repo_slug <repo dir>` prints `owner/repo` from a github.com origin URL, and nothing otherwise.
- `tmo` is in `rest-portable-tmo-keeps-stdin-and-reaps-its-watchdog`.

## Consequences

A new script or test that needs one of those calls the helper, never the raw tool. `tests/portable.sh` pins the behavior with literal expected values on both platforms, and `launchd.yml` runs it on macOS when this file changes. Relaxing the shape checks would let GNU-only inputs pass on Linux CI and fail on the Mac.
