#!/usr/bin/env python3
import argparse
import datetime
import errno
import fcntl
import hmac
import hashlib
import html
import http.client
import json
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import secrets
import shutil
import socketserver
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from autodream_web_data import NightCache


CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; "
    "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
)
COOKIE_NAME = "autodream_session"
SAME_ORIGIN_HOP = '<!doctype html><meta http-equiv="refresh" content="0;url=/">'
STATIC_ROUTES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/web/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/web/app.css": ("app.css", "text/css; charset=utf-8"),
    "/web/threads.js": ("threads.js", "text/javascript; charset=utf-8"),
    "/web/threads.css": ("threads.css", "text/css; charset=utf-8"),
}


def run_bounded(argv, *, timeout=10, input=None, env=None):
    return subprocess.run(argv, input=input, capture_output=True, text=True,
                          timeout=timeout, shell=False, env=env)


def load_or_create_token(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        fd = os.open(path, flags | os.O_CREAT | os.O_EXCL, 0o600)
        created = True
    except FileExistsError:
        fd = os.open(path, flags)
        created = False
    with os.fdopen(fd, "r+", encoding="ascii") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("web-token must be a regular file owned by this user")
        deadline = time.monotonic() + 2
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ValueError("web-token is busy")
                time.sleep(0.01)
                continue
            os.fchmod(stream.fileno(), 0o600)
            if created:
                token = secrets.token_hex(32)
                stream.write(token + "\n")
                stream.flush()
                os.fsync(stream.fileno())
                return token
            stream.seek(0)
            token = stream.read(256).strip()
            if re.fullmatch(r"[0-9a-f]{64}", token):
                return token
            fcntl.flock(stream, fcntl.LOCK_UN)
            if token or time.monotonic() >= deadline:
                raise ValueError("web-token is malformed")
            time.sleep(0.01)


def token_matches(candidate, expected):
    return hmac.compare_digest(candidate.encode("utf-8"), expected.encode("utf-8"))


def identity_proof(token, nonce):
    return hmac.new(token.encode("ascii"), nonce.encode("ascii"), hashlib.sha256).hexdigest()


THREAD_ACTIONS = {
    "resume": lambda ident: ["resume", ident, "--launch"],
    "move-open": lambda ident: ["move", ident, "open"],
    "move-idea": lambda ident: ["move", ident, "idea"],
    "move-done": lambda ident: ["move", ident, "done"],
}
PRE_RECORD_PORT = 8765


def verify_service(port, token):
    nonce = secrets.token_hex(16)
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        connection.request("GET", "/api/identify?nonce=" + nonce)
        response = connection.getresponse()
        proof = response.read(65)
        return response.status == 200 and hmac.compare_digest(
            proof, identity_proof(token, nonce).encode("ascii"))
    except (OSError, http.client.HTTPException):
        return False
    finally:
        connection.close()


HANDOFF_NAME = re.compile(r"web-login(-[0-9a-f]{16})?\.html")
HANDOFF_ID = re.compile(r"[0-9a-f]{16}")
HANDOFF_MAX_AGE = 600


def sweep_stale_handoffs(install, now):
    for path in Path(install).iterdir():
        if not HANDOFF_NAME.fullmatch(path.name):
            continue
        try:
            if now - path.lstat().st_mtime > HANDOFF_MAX_AGE:
                path.unlink()
        except OSError:
            pass


def open_browser(executable, url, install):
    sweep_stale_handoffs(install, time.time())
    handoff_id = secrets.token_hex(8)
    page = Path(install) / f"web-login-{handoff_id}.html"
    target = url + "&h=" + handoff_id
    fd = os.open(page, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            fd = -1
            stream.write('<!doctype html><meta name="referrer" content="no-referrer">'
                         '<meta http-equiv="refresh" content="0;url=' + html.escape(target, quote=True) + '">')
    except BaseException:
        if fd >= 0:
            os.close(fd)
        page.unlink(missing_ok=True)
        raise
    try:
        result = run_bounded([executable, page.absolute().as_uri()])
    except BaseException:
        page.unlink(missing_ok=True)
        raise
    if result.returncode:
        page.unlink(missing_ok=True)
        raise ValueError("browser opener failed; use autodream-web open --print")


class AutodreamHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def end_headers(self):
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        super().end_headers()

    def log_message(self, format, *args):
        sys.stderr.write("autodream-web: HTTP request error\n")

    def log_request(self, code="-", size="-"):
        path = self.path.split("?", 1)[0].encode("unicode_escape").decode("ascii")
        sys.stderr.write(f"autodream-web: {self.command} {path} {code}\n")

    def respond(self, status, body="", *, content_type="text/plain; charset=utf-8", headers=None):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def parse_request(self):
        if not super().parse_request():
            return False
        if not self.check_host():
            return False
        if self.command == "GET" and urlsplit(self.path).path in ("/login", "/api/identify"):
            return True
        if not self.require_session():
            return False
        if self.command == "POST" and not self.require_write_headers():
            return False
        return True

    def check_host(self):
        hosts = self.headers.get_all("Host", [])
        if hosts == [self.server.canonical_host]:
            return True
        if self.command == "GET" and hosts == [f"localhost:{self.server.server_port}"]:
            target = urlsplit(self.path)
            location = self.server.origin + target.path
            if target.query:
                location += "?" + target.query
            self.respond(303, headers={"Location": location})
            return False
        self.respond(421, "Noncanonical Host\n")
        return False

    def require_session(self):
        cookies = self.headers.get_all("Cookie", [])
        if len(cookies) == 1:
            parsed = SimpleCookie()
            try:
                parsed.load(cookies[0])
                credential = parsed.get(COOKIE_NAME)
                if credential and token_matches(credential.value, self.server.token):
                    return True
            except CookieError:
                pass
        self.respond(401, "Run autodream-web open to sign in.\n")
        return False

    def require_write_headers(self):
        if (self.headers.get_all("Origin", []) == [self.server.origin]
                and self.headers.get_all("X-Autodream", []) == ["1"]):
            return True
        self.respond(403, "Canonical Origin and X-Autodream: 1 required\n")
        return False

    def do_GET(self):
        target = urlsplit(self.path)
        if target.path == "/api/identify":
            nonces = parse_qs(target.query, keep_blank_values=True).get("nonce", [])
            if len(nonces) != 1 or not re.fullmatch(r"[0-9a-f]{32}", nonces[0]):
                self.respond(400, "Invalid nonce\n")
                return
            self.respond(200, identity_proof(self.server.token, nonces[0]))
            return
        if target.path == "/login":
            tokens = parse_qs(target.query).get("t", [])
            if len(tokens) != 1 or not token_matches(tokens[0], self.server.token):
                self.respond(401, "Run autodream-web open to sign in.\n")
                return
            handoffs = parse_qs(target.query).get("h", [])
            if len(handoffs) == 1 and HANDOFF_ID.fullmatch(handoffs[0]):
                (self.server.install / f"web-login-{handoffs[0]}.html").unlink(missing_ok=True)
            self.respond(200, SAME_ORIGIN_HOP, content_type="text/html; charset=utf-8", headers={
                "Set-Cookie": f"{COOKIE_NAME}={self.server.token}; HttpOnly; SameSite=Strict; Path=/",
            })
            return
        if target.path.startswith("/api/"):
            self.serve_api(target)
            return
        route = STATIC_ROUTES.get(target.path)
        if route is None:
            self.respond(404, "Not found\n")
            return
        filename, content_type = route
        try:
            data = (self.server.web_dir / filename).read_bytes()
        except OSError:
            self.respond(404, "Not found\n")
            return
        self.respond(200, data, content_type=content_type)

    def serve_api(self, target):
        try:
            if target.path == "/api/lately":
                values = parse_qs(target.query, keep_blank_values=True).get("days", ["7"])
                if len(values) != 1 or not re.fullmatch(r"[0-9]+", values[0]):
                    raise ValueError("invalid days")
                data = self.server.data.lately(int(values[0]))
            elif target.path == "/api/stats":
                data = self.server.data.stats()
            elif target.path == "/api/progress":
                data = self.server.data.progress(time.time())
            elif target.path == "/api/threads":
                rows = self.thread_rows()
                if rows is None:
                    return
                data = dict(threads=rows)
            elif target.path == "/api/dreams":
                data = self.server.data.dream_dates()
            elif target.path.startswith("/api/dreams/"):
                data = self.server.data.read_dream(target.path[len("/api/dreams/"):])
            else:
                self.respond(404, "Not found\n")
                return
            self.respond(200, json.dumps(data, allow_nan=False),
                         content_type="application/json; charset=utf-8")
        except ValueError:
            self.respond(400, "Invalid request\n")
        except FileNotFoundError:
            self.respond(404, "Dream not found\n")
        except OSError:
            self.respond(503, "Artifacts unavailable; retry\n")

    def respond_json(self, status, data):
        self.respond(status, json.dumps(data, allow_nan=False),
                     content_type="application/json; charset=utf-8")

    def action_error(self, status, error, message, **details):
        self.respond_json(status, dict(ok=False, error=error, message=message, **details))

    def thread_rows(self):
        rows = self.server.data.threads()
        if rows is None:
            self.action_error(503, "threads_unavailable", "Could not read threads; refresh to retry")
            return None
        return [dict(row, display_status=row["status"]) for row in rows]

    def do_POST(self):
        path = urlsplit(self.path).path
        match = re.fullmatch(r"/api/threads/([^/]+)/([^/]+)", path)
        if match is None or match[2] not in THREAD_ACTIONS:
            self.action_error(404, "not_found", "Unknown thread action")
            return
        ident, action = match.groups()
        if not re.fullmatch(r"t-[0-9a-f]{8}", ident):
            self.action_error(400, "invalid_id", "Invalid thread id")
            return
        rows = self.thread_rows()
        if rows is None:
            return
        if not any(row["id"] == ident for row in rows):
            self.action_error(404, "not_found", "Unknown thread id")
            return
        argv = ["/bin/bash", str(Path(__file__).resolve().with_name("threads.sh"))] + THREAD_ACTIONS[action](ident)
        try:
            root = self.server.data.root
            result = run_bounded(argv, timeout=20 if action == "resume" else 30,
                env=dict(os.environ, AUTODREAM_DIR=str(root),
                         AUTODREAM_CONFIG=str(root / "config"),
                         AUTODREAM_THREADS_STATE=str(root / "threads.jsonl")))
        except subprocess.TimeoutExpired:
            self.action_error(504, "timeout", "The outcome is unknown. Refresh before trying again.")
            return
        except OSError:
            self.action_error(503, "command_unavailable", "threads.sh is unavailable")
            return
        self.action_result(result, ident, action)

    def action_result(self, result, ident, action):
        if result.returncode == 0:
            self.respond_json(200, dict(ok=True, id=ident, action=action))
            return
        lock_failure = any(line.startswith(("threads: lock is held or unavailable at ",
            "threads: a writer from an older version holds ")) for line in result.stderr.splitlines())
        if result.returncode == 75 or (result.returncode == 1 and lock_failure):
            self.action_error(409, "busy", "busy, retry")
        elif result.returncode == 76:
            self.action_error(409, "already_resuming", "Already resuming")
        elif action == "resume" and result.returncode in {69, 70}:
            message = "cmux is unavailable" if "threads: cmux is unavailable" in result.stderr.splitlines() else "Session launch failed"
            error = "cmux_unavailable" if message == "cmux is unavailable" else "launch_failed"
            self.action_error(503, error, message, brief=result.stdout.strip())
        else:
            self.action_error(503, "command_failed", "Thread action failed; refresh to check state")


class LoopbackServer(ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def make_server(config, port):
    if config.get("host", "127.0.0.1") != "127.0.0.1":
        raise ValueError("only 127.0.0.1 binding is permitted")
    token = load_or_create_token(Path(config["autodream_dir"]) / "web-token")
    server = LoopbackServer(("127.0.0.1", port), AutodreamHandler)
    server.data = NightCache(config["autodream_dir"], config.get("dreams_dir",
        os.environ.get("DREAMS_DIR", Path.home() / ".claude/dreams")))
    server.token = token
    server.install = Path(config["autodream_dir"])
    server.web_dir = Path(config["web_dir"])
    server.canonical_host = f"127.0.0.1:{server.server_port}"
    server.origin = "http://" + server.canonical_host
    return server


def record_port(install, port):
    fd, temporary = tempfile.mkstemp(prefix=".web-port-", dir=install)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            fd = -1
            stream.write(str(port) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, Path(install) / "web-port")
    except BaseException:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def warn_port_in_use(install, port):
    notifier = Path(install) / "notify.sh"
    if not notifier.is_file():
        notifier = Path(__file__).resolve().with_name("notify.sh")
    try:
        run_bounded([str(notifier), "--warning", datetime.date.today().isoformat(),
                     f"web server port {port} is already in use"], timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        pass


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    serve = commands.add_parser("serve")
    serve.add_argument("--port", type=int)
    open_command = commands.add_parser("open")
    open_command.add_argument("--print", action="store_true", dest="print_url")
    args = parser.parse_args()
    install = Path(os.environ.get("AUTODREAM_DIR", Path.home() / ".claude/autodream"))
    port = args.port if args.command == "serve" and args.port is not None else int(
        os.environ.get("AUTODREAM_WEB_PORT", "47823"))
    if not 0 <= port <= 65535:
        parser.error("port must be between 0 and 65535")
    if args.command == "open":
        token = load_or_create_token(install / "web-token")
        candidates = list(dict.fromkeys((port, PRE_RECORD_PORT)))
        port = next((candidate for candidate in candidates if verify_service(candidate, token)), None)
        if port is None:
            print(f"autodream-web: port {candidates[0]} is not this autodream-web", file=sys.stderr)
            return 1
        url = f"http://127.0.0.1:{port}/login?t={token}"
        if args.print_url:
            print(url)
            return
        executable = shutil.which("open" if sys.platform == "darwin" else "xdg-open")
        if executable is None:
            raise ValueError("browser opener unavailable; use autodream-web open --print")
        open_browser(executable, url, install)
        return
    web_dir = install / "web"
    if not web_dir.is_dir():
        web_dir = Path(__file__).resolve().parent.parent / "web"
    try:
        server = make_server({"autodream_dir": install, "web_dir": web_dir}, port)
    except OSError as error:
        if error.errno != errno.EADDRINUSE:
            raise
        warn_port_in_use(install, port)
        return
    try:
        record_port(install, server.server_port)
    except BaseException:
        server.server_close()
        raise
    with server:
        print(server.origin, flush=True)
        server.serve_forever()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"autodream-web: {type(error).__name__}: startup or local command failed", file=sys.stderr)
        sys.exit(1)
