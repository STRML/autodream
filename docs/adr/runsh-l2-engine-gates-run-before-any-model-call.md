# runsh: Every L2 engine requirement is checked before L1 is paid for

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the gates after `build_source_sidecar`)

## Context
L2 runs after L1. A requirement of the L2 engine found missing after L1 means a night of paid triage and an aggregator with nothing to run: every L2 attempt fails after the spend. See CLAUDE.md, 'Which engine runs L2'.

## Decision
Before enumeration continues, `run` refuses to start (`log_fatal`, `fatal_exit`, return 1) when:
- `AUTODREAM_L2_ENGINE` is set and is not an accepted adapter (`adapters_list`).
- `prompts/L2_SYSTEM.txt` cannot be read through `bin/l2-prompt.sh` (`find_lib l2-prompt.sh`, `l2_system_prompt`). This is checked for every engine, claude included: its built-in fallback reads the same file, and an engine started without it runs L2 with no word on where the report goes.
- The review engine is not `claude` and its adapter cannot print an L2 command (`adapter_run <engine> l2-argv [model]` prints nothing, for example omp with no model resolved or an adapter without `l2-argv`). The probe skips claude, whose built-in fallback builds the command itself.
- The review engine fails `engine_login_ok` (`AUTODREAM_REQUIRE_LOGIN`). The engine that writes the summary (and runs dream triage) receives every finding, so its login is held to the requirement before anything is read.

## Consequences
- A new L2 engine requirement belongs in this block, not in the L2 attempt loop, or its failure costs a full L1 spend.
- The claude exemption exists only because of the built-in fallback; removing the fallback removes the exemption.
