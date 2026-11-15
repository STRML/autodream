#!/usr/bin/env python3
import argparse
import datetime
import errno
import fcntl
import hmac
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time
from urllib.parse import parse_qs, urlsplit


CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; "
    "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
)
COOKIE_NAME = "autodream_session"
STATIC_ROUTES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/web/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/web/app.css": ("app.css", "text/css; charset=utf-8"),
}


def run_bounded(argv, *, timeout=10, input=None):
    return subprocess.run(argv, input=input, capture_output=True, text=True,
                          timeout=timeout, shell=False)


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
        if self.command == "GET" and urlsplit(self.path).path == "/login":
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
        if target.path == "/login":
            tokens = parse_qs(target.query).get("t", [])
            if len(tokens) != 1 or not token_matches(tokens[0], self.server.token):
                self.respond(401, "Run autodream-web open to sign in.\n")
                return
            self.respond(303, headers={
                "Location": "/",
                "Set-Cookie": f"{COOKIE_NAME}={self.server.token}; HttpOnly; SameSite=Strict; Path=/",
            })
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

    def do_POST(self):
        self.respond(404, "Not found\n")


def make_server(config, port):
    if config.get("host", "127.0.0.1") != "127.0.0.1":
        raise ValueError("only 127.0.0.1 binding is permitted")
    token = load_or_create_token(Path(config["autodream_dir"]) / "web-token")
    server = ThreadingHTTPServer(("127.0.0.1", port), AutodreamHandler)
    server.token = token
    server.web_dir = Path(config["web_dir"])
    server.canonical_host = f"127.0.0.1:{server.server_port}"
    server.origin = "http://" + server.canonical_host
    return server


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
        os.environ.get("AUTODREAM_WEB_PORT", "8765"))
    if not 0 <= port <= 65535:
        parser.error("port must be between 0 and 65535")
    if args.command == "open":
        token = load_or_create_token(install / "web-token")
        url = f"http://127.0.0.1:{port}/login?t={token}"
        if args.print_url:
            print(url)
            return
        executable = shutil.which("open" if sys.platform == "darwin" else "xdg-open")
        if executable is None:
            raise ValueError("browser opener unavailable; use autodream-web open --print")
        result = run_bounded([executable, url])
        if result.returncode:
            raise ValueError("browser opener failed; use autodream-web open --print")
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
    with server:
        print(server.origin, flush=True)
        server.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"autodream-web: {type(error).__name__}: startup or local command failed", file=sys.stderr)
        sys.exit(1)
