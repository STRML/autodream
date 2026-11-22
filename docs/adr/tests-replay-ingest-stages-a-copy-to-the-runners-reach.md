# tests-replay: ingest replays a copy of the store, staged from the report day to five years after

Status: accepted · Date: 2026-11-22 · Code: `tests/replay.sh` (`replay_ingest`)

## Context

`run.sh` enumerates with `find`, which does not follow a symlinked root, so a sandbox whose root is only a link finds nothing. The real store must also never be written. The runner places a session in a day by the timestamps inside it, not by mtime (#113), so a session written to again after its day closed still belongs to that day. Staging only files last modified on the day would drop exactly those sessions. The runner's own reach is the report day plus five years (`ENUM_END` in `run.sh`).

## Decision

- The sandbox holds a copy of every `*.jsonl` modified from the start of the date until five years after it (`pdate_shift "$date" 5 y`), with mtimes preserved. The runner applies its own window to what is staged, so an older runner, which bounds mtime itself, reads the same copy.
- Files from later days are staged too. A run whose window holds none of them is a quiet day and the runner counts it in `sessions_out_of_window`. That is a WARN. Staged files with no enumerated session and nothing counted out of window is a FAIL, because the runner lost them.
- The sandbox is removed on every exit path, since it holds real transcripts, and kept only when `REPLAY_KEEP` is set.

## Consequences

Narrowing the staging window to the day itself would make the replay pass while leaving out the resumed sessions it exists to check. The five years track `ENUM_END`; if the runner's reach changes, change both. See CLAUDE.md, "Which day a session belongs to (the report-day window, #113)".
