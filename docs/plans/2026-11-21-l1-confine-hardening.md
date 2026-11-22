# L1 confinement hardening (follow-up to #169)

PR #241 shipped the confinement. A Fable review passed it with four P2 and six P3 findings, all
fixed here. Each P2 is a place where the run says "confined" and the workers are not, or where a
confined worker fails every session with no word.

## What changes

```
setup                         before                          after
-----                         ------                          -----
probe (no paths) ok  ───────▶ l1_confined: yes                build each engine's REAL prefix
                              first real prefix fails          │ any fails ──▶ fatal, no L1, no stubs
                              ──▶ every session a stub         ▼
                                                              l1_confined: yes | partial | no
```

| # | Finding | Fix |
|---|---|---|
| P2a | Setup checked the probe and `$AUTODREAM_DIR`, not each engine's real write list. A bad character in `$HOME`, the work bucket or `AUTODREAM_L1_WRITES_EXTRA` failed the prefix of every call: every session stubbed, run-stats still `l1_confined: yes`. | `l1-confine.sh engine-prefix <adapter> <stage>` builds the prefix from the adapter's own `l1-writes`. Setup runs it once per engine with sessions, with a throwaway stage. A failure is `log_fatal` plus `fatal_exit` before any L1 call. The worker calls the same verb, so there is one definition. |
| P2b | `l1_confined: yes` while an engine runs unconfined (`l1_confined_omp: no`). | The top-level line is `yes` only when every engine with sessions is confined, `partial` when some are, `no` otherwise. PROMPT.md's self-audit names `no`, `partial`, the reason and a non-`none` `l1_confine_extra`. |
| P2c | The work bucket is the one shared writable default (parallel workers, the thread linker, a concurrent date's L2). | `tests/l1-confine-real.sh --no-bucket` printed ALL PASS (2026-11-21, unsandboxed shell): a confined call exits 0 with the stub write refused. The bucket leaves `l1-writes` and the mkdir that existed so bwrap could bind it goes. The wipes stay (before L1, after L1, after L2): an unconfined engine can still write it, and L2 launches from it. |
| P2d | Token refresh inside the sandbox is unverified. | Documented as unverified in the write-list plan. The serial warmup is unconfined and refreshes the token before any confined worker starts. A login failure under confinement classifies as `provider` (retriable), never `size`. |

P3 items, one line each:

- A stage that is a symlink, or does not resolve under the physical staging root, is refused.
- A writable path whose last component is a symlink is refused (it would grant its target).
- The answer is moved to `$2.stage` first (`mv` does not follow a symlink), then tested.
- `*.stage` joins the leftovers the next run sweeps.
- The protect and extra loops run with globbing off. `AUTODREAM_L1_WRITES_EXTRA` entries and the
  protected paths must be absolute, and the three protected directories must not contain `:`.
- `bubblewrap` is installed in `tests.yml`, so the bwrap branch runs in CI where user namespaces work.
- The stale "still to be run" text is replaced by the measured result.
- `failure-class.sh` skips the four lines `run.sh` writes about staging and the sandbox.

## Failure matrix

| State | Before | After |
|---|---|---|
| `$HOME` or the bucket path holds a quote | every session stubbed, `l1_confined: yes` | run stops before L1: `fatal:` in run-stats, banner, no report, date retried |
| `AUTODREAM_L1_WRITES_EXTRA` entry is relative or has a quote | same | same fatal, names the entry |
| protected dir holds `:` | protect list splits wrong, a path silently unprotected | fatal at setup |
| claude confined, omp has no write profile | `l1_confined: yes` | `l1_confined: partial`, reason names omp |
| no engine has a write profile | `yes` | `no` |
| stage dir is a symlink | followed | refused, attempt fails with evidence |
| `~/.cache/claude-cli-nodejs` is a symlink | its target became writable | refused, fatal at setup, names the path |
| answer path is a symlink | read through `cp` after a test | moved aside by name, tested, not read |
| run killed between copy and rename | `$2.stage` left forever | swept next run |
| token expired under confinement | `size` class, stub | `provider` class |

## Tests (red first)

`tests/l1-confine.sh` pins the verb, the symlink refusals and the path checks with shims.
`tests/run-all.sh` pins setup and the run-stats lines with a fake `sandbox-exec` that passes the
probe (it makes the probe's outside directory read-only), so no real sandbox is needed. The
real-sandbox cases stay in the existing blocks, which skip where the probe says no.
