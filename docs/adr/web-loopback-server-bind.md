# web: the server skips HTTPServer's reverse DNS lookup on bind

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-web.py` (`LoopbackServer.server_bind`)

## Context

`HTTPServer.server_bind` calls `socket.getfqdn(host)`, a reverse DNS lookup. On a loopback address it blocked for many seconds on the macOS CI runner before the server printed its origin, so 25 of the web suite's 31 tests failed in `start_server` (#223). CLAUDE.md, section "Local web dashboard", records the incident.

## Decision

`LoopbackServer` overrides `server_bind` to call `socketserver.TCPServer.server_bind` and then set `server_name` and `server_port` from `server_address`. Nothing in the server reads `server_name`.

## Consequences

If anything starts reading `server_name`, set it explicitly instead of restoring the lookup. Test fixture servers use `tests/loopback_http.py` for the same reason.
