# bin-a: classification checks login failures first, then size, then provider, and a bare number is not a status code

Status: accepted · Date: 2026-11-21 · Code: `bin/failure-class.sh` (`classify_failure`)

## Context

An expired login under the sandbox can sit beside a context-limit line. Providers and models spell the same words with spaces, hyphens or underscores. A transcript or a log line can contain a number such as 520 with no status code behind it. CLAUDE.md, "A failed worker leaves its evidence, and the failure is classified", records that a wording neither list knows lands in `size`, which is the owner's decision (2026-09-15).

## Decision

- A login failure is checked first and is `provider` (retriable) whatever else the output mentions, so the size rule cannot claim it.
- Size signatures come next, then provider signatures. Anything neither list knows is `size`.
- Word patterns use `[[:space:]_-]` as the separator, so `prompt-too-long` and `prompt too long` match alike.
- A bare number is not a status code: "read 520 bytes" is not a 5xx. A code counts only after an HTTP, status, code or error label, allowing the connecting words of "HTTP status code was 500". Otherwise the reason phrase has to say it.

## Consequences

Reordering the checks lets a size line hide a login failure and defers a date for the wrong reason. Add a wording only when a real `.err` shows one, with a matrix row in `test_failure_class_provider_matrix`.
