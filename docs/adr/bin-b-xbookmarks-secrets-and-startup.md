# bin-b: cookies stay out of argv, user-edited files are sourced with nounset off, and config is read here too

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`write_curl_configs`, `cfg_escape`, `warn_perms`, `load_creds`, the config source at the top)

## Context

CLAUDE.md "X bookmarks as idea fuel" and "Bash traps this feature hit" give the background. The cookies are a full account session: anyone who can read them can post as the user. `-H "cookie: auth_token=..."` puts that into the process list for the life of each request, and the nightly run makes several while unattended.

## Decision

- `write_curl_configs` writes the headers to two 0600 `curl --config` files inside the per-run `$TMP`, which the EXIT trap removes. There are two because the bookmarks-page fetch sends cookies only, while the GraphQL call sends cookies, the CSRF token and the bearer. It is the one place credentials touch the disk.
- The JS chunk fetch is deliberately unauthenticated. It hits abs.twimg.com, a public CDN, and a session cookie sent there would widen where the credential goes for nothing.
- `cfg_escape` escapes `\` and `"` because curl's config parser treats a double-quoted value as escapable. X cookie values are hex or base64url in practice, but the failure would be a curl parse error on a line the user pasted by hand.
- `warn_perms` warns about a mode other than 600 or 400 and never refuses. A nightly job that silently does nothing is worse than one that works and complains.
- Both the config and the credentials file are sourced with `set +u`. Under nounset a stray unbound reference in a hand-edited file kills the whole script, `||` cannot catch it, and `collect` then never writes its output stub. L2 would read the feature as off rather than broken. The config source also replays the `export -p` snapshot so the caller's environment wins, and stays quiet because run.sh already warns about the typo.
- The config is sourced here too, not only in run.sh, because `status` is run by hand and must see the settings the nightly run sees.
- The `portable.sh` lookup falls back to the symlink target's directory: installed copies are symlinks, and a merge updates them before `install.sh` links a new helper.

## Consequences

Never pass a credential as a curl argument or an environment value to a child. A new authenticated call site gets its header set in `write_curl_configs`, not inline.
