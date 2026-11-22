# bin-a: `whoami` reads the login with `claude auth status --json` and makes no model call

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`whoami`)

## Context

The run reports which account and plan its calls bill to. Asking a model would cost a call, and it would fail exactly when the login is broken. `claude auth status --json` reports the API provider (`firstParty` is Anthropic's own API), the sign-in method, the subscription plan, the account email and, for a stored claude.ai sign-in, when that sign-in ends. The expiry field, `loginExpiresAt`, exists only in Claude Code 2.1.318 and later.

## Decision

`whoami` runs `claude auth status --json` with stdin closed and stderr dropped, and prints one JSON object: `{provider, auth, plan, account, expires}`. A field the login does not report reads `unknown`. A failed call or unparseable output makes all five fields `unknown`.

## Consequences

`expires` reads `unknown` on Claude Code older than 2.1.318 and with an API-key login. That is the expected output there, so `unknown` alone does not mean the adapter is broken. Check the readers of this object before renaming a field.
