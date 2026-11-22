# runsh: an engine's login is read once with a model-free whoami, checked against AUTODREAM_REQUIRE_LOGIN, and an ended claude.ai sign-in is a refusal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`engine_login_ok`, `login_expiry_warn`, `ENGINE_LOGINS`, `LOGIN_REFUSAL`)

## Context
A run on the wrong account bills or authenticates the wrong login, and a claude.ai sign-in past its end date fails every model call. The answer must be known before the engine is handed anything, without spending a model call.

## Decision
- Each engine is asked once through the adapter's `whoami` verb (claude: `claude auth status`, no model call); an engine without the verb reports `unknown`. The answer is logged once and kept in `ENGINE_LOGINS` (engine, provider, auth, plan, account, expires; tab-separated) for run-stats.
- `AUTODREAM_REQUIRE_LOGIN` lists `key=value` pairs (provider, auth, plan, account) that must all match; a claude.ai sign-in past its end date fails too, since every model call on it would. Either way `engine_login_ok` returns 1 with the reason in `LOGIN_REFUSAL`.
- A claude.ai sign-in that ends within `AUTODREAM_LOGIN_WARN_DAYS` (default 10, the lead time Claude Code's own `claude -p` warning uses) posts one warning banner per engine per run, in a notification group of its own (`login-<engine>`) so a later warning on the same date cannot replace it. One that has already ended posts nothing here: `engine_login_ok` refuses it, and the caller's failure says so.

## Consequences
Keep the warning group per engine; a shared group lets the changelog or remote-sync warnings replace it. A malformed or non-claude.ai expiry never refuses a run (`login_seconds_left` fails closed to "unknown").
