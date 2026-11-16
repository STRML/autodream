#!/usr/bin/env python3
import concurrent.futures
import contextlib
import io
import fcntl
import shutil
from datetime import date, timedelta
import http.client
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
import socket
import stat
import time
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock
import urllib.error
import urllib.request
from urllib.parse import quote
import plistlib


REPO = Path(__file__).resolve().parents[1]
COMMAND = REPO / "bin/autodream-web"
SERVER = REPO / "bin/autodream-web.py"
EXPECTED_CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; "
    "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
)
PRIVATE_GOAL = "Private fixture goal: finish the secret project"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Response:
    def __init__(self, response):
        self.status = response.code
        self.headers = response.headers
        self.text = response.read().decode("utf-8")


class WebTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="web.")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.install = self.root / "install with spaces"
        self.install.mkdir()
        self.env = dict(os.environ, AUTODREAM_DIR=str(self.install),
                        HOME=str(self.root), PYTHONDONTWRITEBYTECODE="1")
        self.env.pop("AUTODREAM_CONFIG", None)
        self.env.pop("AUTODREAM_WEB_PORT", None)
        web = self.install / "web"
        web.mkdir()
        (web / "index.html").write_text("<!doctype html><p>" + PRIVATE_GOAL + "</p>")
        (web / "app.js").write_text("console.log('fixture');")
        (web / "app.css").write_text("body { color: black; }")
        (web / "threads.js").write_text("// shared fixture")
        (web / "threads.css").write_text(".thread-view {}")
        (self.install / "threads.jsonl").write_text(PRIVATE_GOAL)

    def run_command(self, *args, env=None):
        self.assertTrue(COMMAND.is_file(), "local web command has not been implemented")
        return subprocess.run(["/bin/bash", str(COMMAND), *args],
                              env=env or self.env, capture_output=True, text=True,
                              timeout=15)

    def run_install(self, *args, env_extra=None, without_tools=()):
        home = self.root / "installer-home"
        shim = self.root / "installer-shim"
        tools = self.root / "installer-tools"
        launch_agents = home / "Library" / "LaunchAgents"
        shim.mkdir(exist_ok=True)
        tools.mkdir(exist_ok=True)
        launch_agents.mkdir(parents=True, exist_ok=True)
        calls = self.root / "launchctl-calls"
        if not calls.exists():
            calls.write_text("")
        launchctl = shim / "launchctl"
        launchctl.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + str(calls) + "\"\n")
        with launchctl.open("a") as stream:
            stream.write('[ "$1" = print ] && exit 113\nexit 0\n')
        launchctl.chmod(0o755)
        for name in ("cmux", "claude"):
            if name in without_tools:
                continue
            tool = tools / name
            if not tool.exists():
                tool.write_text("#!/bin/sh\nexit 0\n")
                tool.chmod(0o755)
        env = dict(os.environ, HOME=str(home), PATH=f"{shim}:{tools}:/usr/bin:/bin",
                   AUTODREAM_CMUX_DEFAULT=str(self.root / "missing-cmux"),
                   AUTODREAM_EPHEMERAL_DIRS="", TMPDIR=str(self.root))
        env.update(env_extra or {})
        result = subprocess.run(["/bin/bash", str(REPO / "install.sh"), *args],
                                env=env, capture_output=True, text=True, timeout=30)
        return result, home, launch_agents, calls, tools

    @staticmethod
    def plist(path):
        with path.open("rb") as stream:
            return plistlib.load(stream)

    @staticmethod
    def tree_snapshot(root):
        entries = []
        for path in root.rglob("*"):
            if path.is_symlink():
                entries.append((str(path.relative_to(root)), "link", os.readlink(path)))
            elif path.is_file():
                entries.append((str(path.relative_to(root)), "file", path.read_bytes()))
            elif path.is_dir():
                entries.append((str(path.relative_to(root)), "dir", None))
        return sorted(entries)

    # Drives install.sh's launchd path, which needs macOS tools. Linux CI skips it; the macOS
    # launchd workflow runs it, and tests/install-web-agent.sh covers the same rules there.
    @unittest.skipUnless(sys.platform == "darwin", "install.sh's launchd path runs on macOS only")
    def test_install_web_agent_ownership_and_options(self):
        result, _, launch_agents, calls, tools = self.run_install(str(self.root / "target"))
        self.assertEqual(result.returncode, 0, result.stderr)
        nightly = next(path for path in launch_agents.glob("*.plist")
                       if not path.stem.endswith(("-review", "-web")))
        nightly_label = self.plist(nightly)["Label"]
        nightly_contents = nightly.read_bytes()
        web = launch_agents / (nightly_label + "-web.plist")
        self.assertTrue(web.exists())
        self.assertEqual(self.plist(web)["Label"], nightly_label + "-web")

        launch_agents.joinpath(nightly.name).write_text(
            "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
            "<key>Label</key><string>" + nightly_label + "</string>"
            "<key>ProgramArguments</key><array><string>/elsewhere/run.sh</string>"
            "</array></dict></plist>")
        web.unlink()
        calls.write_text("")
        refused, _, _, _, _ = self.run_install(str(self.root / "refused"))
        self.assertEqual(refused.returncode, 0, refused.stderr)
        self.assertEqual(calls.read_text().splitlines(), [])
        self.assertFalse((launch_agents / (nightly_label + "-web.plist")).exists())
        nightly.write_bytes(nightly_contents)
        restored, _, _, _, _ = self.run_install(str(self.root / "target"))
        self.assertEqual(restored.returncode, 0, restored.stderr)
        self.assertTrue((launch_agents / (nightly_label + "-web.plist")).exists())

        self.assertIn("--no-web", subprocess.run(
            ["/bin/bash", str(REPO / "install.sh"), "--help"],
            capture_output=True, text=True, timeout=10).stdout)

        dry_before = self.tree_snapshot(self.root)
        dry, _, _, _, _ = self.run_install("--dry-run", str(self.root / "dry-target"))
        self.assertEqual(dry.returncode, 0, dry.stderr)
        dry_after = self.tree_snapshot(self.root)
        self.assertEqual([entry for entry in dry_after if entry[0] != 'launchctl-calls'],
                         [entry for entry in dry_before if entry[0] != 'launchctl-calls'])

        no_web, _, _, _, _ = self.run_install("--no-web", str(self.root / "target"))
        self.assertEqual(no_web.returncode, 0, no_web.stderr)
        self.assertFalse((launch_agents / (nightly_label + "-web.plist")).exists())
        config = self.root / "target" / "autodream" / "config"
        config.write_text("AUTODREAM_WEB=0\n")
        disabled, _, _, _, _ = self.run_install(str(self.root / "target"))
        self.assertEqual(disabled.returncode, 0, disabled.stderr)
        self.assertFalse((launch_agents / (nightly_label + "-web.plist")).exists())
        enabled, _, _, _, _ = self.run_install(
            str(self.root / "target"), env_extra={"AUTODREAM_WEB": "1"})
        self.assertEqual(enabled.returncode, 0, enabled.stderr)
        self.assertTrue((launch_agents / (nightly_label + "-web.plist")).exists())

    def test_install_web_survives_review_opt_out(self):
        result, _, launch_agents, _, tools = self.run_install(
            "--no-review", str(self.root / "target"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(path.stem.endswith("-web") for path in launch_agents.glob("*.plist")))
        (tools / "cmux").unlink()
        for path in launch_agents.iterdir():
            path.unlink()
        without_cmux, _, _, _, _ = self.run_install(
            str(self.root / "without-cmux"), without_tools=("cmux",))
        self.assertEqual(without_cmux.returncode, 0, without_cmux.stderr)
        self.assertTrue(any(path.stem.endswith("-web") for path in launch_agents.glob("*.plist")))
        self.assertFalse(any(path.stem.endswith("-review") for path in launch_agents.glob("*.plist")))

    def test_install_web_restart_policy(self):
        result, _, launch_agents, _, tools = self.run_install(str(self.root / "target"))
        self.assertEqual(result.returncode, 0, result.stderr)
        web = next(path for path in launch_agents.glob("*-web.plist"))
        plist = self.plist(web)
        plist_env = plist["EnvironmentVariables"]
        self.assertTrue(plist["RunAtLoad"])
        self.assertEqual(plist["KeepAlive"], {"SuccessfulExit": False})
        self.assertEqual(plist["ThrottleInterval"], 60)
        self.assertEqual(plist_env["CMUX_BIN"], str(tools / "cmux"))
        self.assertEqual(plist_env["CLAUDE_BIN"], str(tools / "claude"))
        self.assertEqual(plist_env["AUTODREAM_WEB_PORT"], "47823")

    def test_web_port_in_use_warns_once_and_exits_zero(self):
        self.start_server()
        occupied = socket.socket()
        occupied.bind(("127.0.0.1", 0))
        port = occupied.getsockname()[1]
        notification = self.install / "notification-argv"
        notification_count = self.install / "notification-count"
        notify = self.install / "notify.sh"
        notify.write_text("#!/bin/sh\nprintf 'call\\n' >> \"" + str(notification_count) +
                          "\"\nprintf '%s\\n' \"$@\" > \"" + str(notification) + "\"\n")
        notify.chmod(0o755)
        result = self.run_command("serve", "--port", str(port))
        occupied.close()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(notification_count.read_text().splitlines(), ["call"])
        notification_argv = notification.read_text().splitlines()
        self.assertGreaterEqual(len(notification_argv), 3)
        self.assertEqual(notification_argv[0], "--warning")

    def load_module(self):
        self.assertTrue(SERVER.is_file(), "HTTP boundary is not implemented")
        spec = importlib.util.spec_from_file_location("autodream_web", SERVER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def start_server(self):
        self.assertTrue(SERVER.is_file() and COMMAND.is_file(),
                        "HTTP boundary does not exist yet; no real service can start")
        self.logs = self.root / "server.log"
        log = self.logs.open("w")
        self.addCleanup(log.close)
        self.process = subprocess.Popen(
            ["/bin/bash", str(COMMAND), "serve", "--port", "0"],
            env=self.env, stdout=subprocess.PIPE, stderr=log, text=True)
        self.addCleanup(self.stop_server)
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            self.assertTrue(selector.select(timeout=10), "server did not announce its port")
            line = self.process.stdout.readline().strip()
        match = re.fullmatch(r"http://127\.0\.0\.1:([0-9]+)", line)
        self.assertIsNotNone(match, "server startup failed: " + line + self.logs.read_text())
        self.port = int(match[1])
        self.origin = "http://127.0.0.1:" + str(self.port)
        self.token_path = self.install / "web-token"
        self.token = self.token_path.read_text().strip()

    def stop_server(self):
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait(timeout=5)
        self.process.stdout.close()

    def request(self, method, path, *, cookie=None, host=None, origin=None,
                headers=None, body=None):
        request_headers = dict(headers or {})
        if cookie is not None:
            request_headers["Cookie"] = cookie
        if host is not None:
            request_headers["Host"] = host
        if origin is not None:
            request_headers["Origin"] = origin
        request = urllib.request.Request(self.origin + path, data=body,
                                         headers=request_headers, method=method)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            response = opener.open(request, timeout=12)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            result = Response(response)
        with (self.root / "http-transcript.txt").open("a") as transcript:
            transcript.write(f"{method} {path.split('?')[0]} -> {result.status}\n")
        return result

    def login(self):
        response = self.request("GET", "/login?t=" + self.token)
        self.assertEqual(response.status, 200)
        return response.headers["Set-Cookie"].split(";", 1)[0]

    def progress_locks(self):
        locks = self.install / "locks"
        locks.mkdir()
        current = time.strftime("%a %b %d %H:%M:%S %Y", time.localtime())
        try:
            current = subprocess.run(["ps", "-o", "lstart=", "-p", str(os.getpid())],
                                     capture_output=True, text=True, check=True, timeout=2).stdout
        except PermissionError:
            tools = self.root / "process-fixture"
            tools.mkdir()
            ps = tools / "ps"
            ps.write_text("#!/bin/sh\nprintf '%s\\n' '" + current + "'\n")
            ps.chmod(0o755)
            self.env["PATH"] = str(tools) + os.pathsep + os.environ["PATH"]
        exited = subprocess.run([sys.executable, "-c", "import os; print(os.getpid())"],
                                capture_output=True, text=True, check=True, timeout=2)
        for day, pid, start in (("2026-11-14", str(os.getpid()), current),
                                ("2026-11-13", exited.stdout.strip(), current),
                                ("2026-11-12", str(os.getpid()), "Mon Jan  1 00:00:00 2001"),
                                ("2026-11-11", None, None),
                                ("2026-11-10", str(os.getpid()), None),
                                ("2026-11-09", "-1", current)):
            lock = locks / ("run-" + day + ".lock")
            lock.mkdir()
            if pid is not None:
                (lock / "pid").write_text(pid + "\n")
            if start is not None:
                (lock / "start").write_text(start)
        (locks / "run-2026-02-30.lock").mkdir()
        (locks / "run-2026-11-08.lock.stale-1").mkdir()
        return locks

    def test_web_progress_checks_pid_and_start(self):
        locks = self.progress_locks()
        before = self.tree_snapshot(locks)
        self.start_server()
        response = self.request("GET", "/api/progress", cookie=self.login())
        self.assertEqual(response.status, 200, "progress route is absent")
        rows = {row["date"]: row for row in json.loads(response.text)["runs"]}
        self.assertEqual(len(rows), 6)
        self.assertEqual(rows["2026-11-14"]["state"], "running")
        self.assertGreaterEqual(rows["2026-11-14"]["elapsed_seconds"], 0)
        self.assertLess(rows["2026-11-14"]["elapsed_seconds"], 120)
        self.assertRegex(rows["2026-11-14"]["started_at"], r"T.*Z$")
        for day in ("2026-11-13", "2026-11-12", "2026-11-09"):
            self.assertEqual(rows[day]["state"], "stale")
            self.assertIsNone(rows[day]["elapsed_seconds"])
        self.assertEqual(rows["2026-11-11"]["state"], "starting")
        self.assertIsNone(rows["2026-11-11"]["elapsed_seconds"])
        self.assertEqual(rows["2026-11-10"]["state"], "running", "live pid fallback lost")
        self.assertEqual(self.tree_snapshot(locks), before, "Progress must never mutate locks")

    def test_web_progress_bounds_process_start_lookup(self):
        lock = self.install / "locks/run-2026-11-14.lock"
        lock.mkdir(parents=True)
        (lock / "pid").write_text(str(os.getpid()))
        (lock / "start").write_text("recorded start")
        tools = self.root / "slow-process-fixture"
        tools.mkdir()
        ps = tools / "ps"
        ps.write_text("#!/bin/sh\nexec python3 -c 'import time; time.sleep(5)'\n")
        ps.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + os.environ["PATH"]
        self.start_server()
        cookie = self.login()
        for recorded, expected in ((True, "unverified"), (False, "running")):
            if not recorded:
                (lock / "start").unlink()
            before = self.tree_snapshot(lock)
            started = time.monotonic()
            response = self.request("GET", "/api/progress", cookie=cookie)
            elapsed = time.monotonic() - started
            self.assertEqual(response.status, 200)
            self.assertLess(elapsed, 4, "the process-start probe must be bounded to two seconds")
            row = json.loads(response.text)["runs"][0]
            self.assertEqual(row["state"], expected)
            self.assertIsNone(row["elapsed_seconds"])
            self.assertEqual(self.tree_snapshot(lock), before)

    def test_web_progress_never_infers_phase(self):
        self.progress_locks()
        logs = self.install / "logs"
        logs.mkdir()
        old_line = 'L2 aggregation attempt 1/3... <img src=x onerror="window.pwned=1">'
        path = logs / "run-2026-11-13.log"
        path.write_text("Earlier line\n" + old_line + "\n")
        self.start_server()
        cookie = self.login()
        response = self.request("GET", "/api/progress", cookie=cookie)
        self.assertEqual(response.status, 200, "progress route is absent")
        rows = {row["date"]: row for row in json.loads(response.text)["runs"]}
        self.assertTrue(all("phase" not in row for row in rows.values()))
        self.assertEqual(rows["2026-11-13"]["state"], "stale")
        self.assertEqual(rows["2026-11-13"]["last_log_line"], old_line)
        self.assertIsNone(rows["2026-11-14"]["last_log_line"])
        path.write_text("New last line")
        refreshed = json.loads(self.request("GET", "/api/progress", cookie=cookie).text)
        self.assertEqual(next(row for row in refreshed["runs"] if row["date"] ==
                              "2026-11-13")["last_log_line"], "New last line")

    def test_web_stats_exposes_only_allowed_keys(self):
        allowed = set("""sessions_found_raw sessions_triaged sessions_top_level sessions_nested
self_sessions_excluded gated l1_rounds_used l1_rounds_max l1_timed_out
l1_missing_after_retries l1_findings_with_error l1_elapsed_seconds
stats_sidecars_unparseable overlap_measured overlap_events network_down_seconds
network_deferred network_down_seconds_l2 network_deferred_l2 l1_served_mismatch
l1_served_unmeasured l1_cost_usd_estimate l1_cost_unmeasured l1_chunk_calls
l1_chunks_elided threads_linked threads_unassigned threads_unmeasured""".split())
        day = self.install / "findings/2026-11-14"
        day.mkdir(parents=True)
        (day / "run-stats.txt").write_text(
            "sessions_triaged: 12\nsessions_top_level: 2\nsessions_nested: 10\n"
            "l1_cost_usd_estimate: 0.1250\noverlap_measured: no\noverlap_events: 0\n"
            "login_claude: account=account-canary\nlogin_omp: account=account-canary\n"
            "unknown_future_key: 123\naccount: account-canary\n"
            "gated: account-canary\nl1_chunk_calls: NaN\n")
        self.start_server()
        cookie = self.login()
        self.assertEqual(self.request("GET", "/api/stats").status, 401)
        self.assertEqual(self.request("GET", "/api/stats", cookie=cookie, host="evil.example").status, 421)
        response = self.request("GET", "/api/stats", cookie=cookie)
        self.assertEqual(response.status, 200, "stats route is absent")
        self.assertEqual(response.headers["Content-Security-Policy"], EXPECTED_CSP)
        night = json.loads(response.text)["nights"][0]
        self.assertLessEqual(set(night["run"]), allowed)
        self.assertEqual(night["run"]["sessions_triaged"], 12)
        self.assertEqual(night["run"]["l1_cost_usd_estimate"], 0.125)
        self.assertEqual(night["sessions"], {"top_level": 2, "nested": 10})
        self.assertIsNone(night["run"].get("gated"))
        self.assertIsNone(night["run"].get("overlap_events"), "unmeasured overlap must be a gap")
        for secret in ("login_claude", "login_omp", "account-canary", "unknown_future_key"):
            self.assertNotIn(secret, response.text)
        (day / "run-stats.txt").write_text("sessions_triaged: 21\n")
        refreshed = json.loads(self.request("GET", "/api/stats", cookie=cookie).text)
        self.assertEqual(refreshed["nights"][0]["run"]["sessions_triaged"], 21)

    def test_web_requires_cookie(self):
        self.start_server()
        for path in ("/", "/web/app.js", "/web/app.css", "/api/lately", "/api/threads", "/api/progress", "/api/stats", "/web/threads.js", "/web/threads.css", "/threads.jsonl"):
            with self.subTest(path=path):
                response = self.request("GET", path)
                self.assertEqual(response.status, 401)
                self.assertNotIn(PRIVATE_GOAL, response.text)
                self.assertIn("autodream-web open", response.text)
        self.assertEqual(self.request("HEAD", "/").status, 401)

    def test_web_rejects_foreign_host(self):
        self.start_server()
        cookie = self.login()
        for credential in (None, cookie):
            for host in ("evil.example", "127.0.0.1", "127.0.0.1:1",
                         "localhost:1", "127.0.0.1:" + str(self.port) + ".evil"):
                with self.subTest(host=host, cookie=credential is not None):
                    response = self.request("GET", "/", cookie=credential, host=host)
                    self.assertEqual(response.status, 421)
                    self.assertNotIn(PRIVATE_GOAL, response.text)
            response = self.request("GET", "/?private=query", cookie=credential,
                                    host="localhost:" + str(self.port))
            self.assertEqual(response.status, 303)
            self.assertEqual(response.headers["Location"], self.origin + "/?private=query")
            self.assertNotIn(PRIVATE_GOAL, response.text)
        response = self.request("POST", "/", cookie=cookie,
                                host="localhost:" + str(self.port))
        self.assertEqual(response.status, 421)
        for hosts in ([], [f"127.0.0.1:{self.port}", "evil.example"]):
            connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
            try:
                connection.putrequest("GET", "/", skip_host=True)
                for host in hosts:
                    connection.putheader("Host", host)
                connection.endheaders()
                self.assertEqual(connection.getresponse().status, 421)
            finally:
                connection.close()

    def test_web_login_cookie_and_token_scope(self):
        self.start_server()
        response = self.request("GET", "/login?t=" + self.token)
        self.assertEqual(response.status, 200)
        self.assertIsNone(response.headers["Location"])
        self.assertIn('http-equiv="refresh" content="0;url=/"', response.text)
        cookie_header = response.headers["Set-Cookie"]
        for attribute in ("HttpOnly", "SameSite=Strict", "Path=/"):
            self.assertIn(attribute, cookie_header)
        cookie = cookie_header.split(";", 1)[0]
        authenticated = self.request("GET", "/", cookie=cookie)
        self.assertEqual(authenticated.status, 200)
        self.assertIn(PRIVATE_GOAL, authenticated.text)
        self.assertEqual(self.request("GET", "/?t=" + self.token).status, 401)
        for headers in ({"Authorization": "Bearer " + self.token},
                        {"X-Autodream": self.token}):
            self.assertEqual(self.request("GET", "/", headers=headers).status, 401)
        for query in ("", "?t=wrong", "?t=" + self.token + "&t=wrong"):
            self.assertEqual(self.request("GET", "/login" + query).status, 401)
        self.assertEqual(self.request("GET", "/", cookie="autodream_session=wrong").status, 401)
        self.assertEqual(stat.S_IMODE(self.token_path.stat().st_mode), 0o600)
        self.assertRegex(self.token, r"^[0-9a-f]{64}$")
        self.request("GET", "/unknown?secret=" + self.token, cookie=cookie)
        self.stop_server()
        logs = self.logs.read_text()
        self.assertNotIn(self.token, logs)
        self.assertNotIn("?", logs)

    def test_web_sets_frame_blocking_csp(self):
        self.start_server()
        cookie = self.login()
        for credential, path in ((None, "/"), (cookie, "/"),
                                 (cookie, "/missing"), (None, "/login?t=" + self.token)):
            response = self.request("GET", path, cookie=credential)
            self.assertEqual(response.headers["Content-Security-Policy"], EXPECTED_CSP)
            self.assertEqual(response.headers["Referrer-Policy"], "no-referrer")
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertIsNone(response.headers.get("Access-Control-Allow-Origin"))

    def test_web_refuses_non_loopback_bind(self):
        self.start_server()
        module = self.load_module()
        config = {"autodream_dir": self.install, "web_dir": self.install / "web"}
        for address in ("0.0.0.0", "::", "192.0.2.1"):
            result = self.run_command("serve", "--port", "0", "--host", address)
            self.assertNotEqual(result.returncode, 0)
            with self.assertRaises(ValueError):
                with module.make_server(dict(config, host=address), 0):
                    pass
        with module.make_server(config, 0) as server:
            self.assertEqual(server.server_address[0], "127.0.0.1")

    def seed_actions(self):
        self.thread = {"id": "t-00000001", "kind": "work", "repo": str(self.root),
                       "title": "Title <repo>", "goal": "Goal $(touch unwanted)",
                       "status": "open", "done_by": None, "last_seen": "2020-01-01",
                       "sessions": [{"date": "2020-01-01", "hash": "0123456789ab",
                                     "outcome": "not_achieved"}]}
        self.state_path = self.install / "threads.jsonl"
        self.state_path.write_text(json.dumps(self.thread) + "\n")
        tools = self.root / "tools"
        tools.mkdir()
        self.creates = self.root / "workspace-creates"
        cmux = tools / "cmux"
        cmux.write_text("#!/bin/sh\nprintf 'create\\n' >> '" + str(self.creates) + "'\n")
        cmux.chmod(0o755)
        claude = tools / "claude"
        claude.write_text("#!/bin/sh\nexit 99\n")
        claude.chmod(0o755)
        for name in ("jq", "python3", "timeout"):
            executable = shutil.which(name)
            if executable:
                (tools / name).symlink_to(executable)
        self.env.update(CMUX_BIN=str(cmux), CLAUDE_BIN=str(claude),
                        PATH=str(tools) + ":/usr/bin:/bin",
                        DREAMS_DIR=str(self.root / "dreams"),
                        AUTODREAM_THREADS_STATE=str(self.state_path),
                        AUTODREAM_CONFIG=str(self.install / "no-config"))
        self.start_server()
        self.cookie = self.login()

    def action(self, action, ident="t-00000001", **kwargs):
        return self.request("POST", "/api/threads/" + ident + "/" + action,
                            cookie=self.cookie, origin=self.origin,
                            headers={"X-Autodream": "1"}, **kwargs)

    def test_web_actions_require_origin_and_header(self):
        self.seed_actions()
        before = self.state_path.read_bytes()
        for action in ("move-open", "move-idea", "move-done", "resume"):
            path = "/api/threads/t-00000001/" + action
            self.assertEqual(self.request("POST", path, origin=self.origin,
                headers={"X-Autodream": "1"}).status, 401)
            self.assertEqual(self.request("POST", path, cookie=self.cookie,
                origin=self.origin, host="evil.example", headers={"X-Autodream": "1"}).status, 421)
            for origin, marker in ((None, "1"), ("http://evil.example", "1"),
                                   (self.origin + "/", "1"), (self.origin, None),
                                   (self.origin, "0")):
                response = self.request("POST", path, cookie=self.cookie, origin=origin,
                    headers={} if marker is None else {"X-Autodream": marker})
                self.assertEqual(response.status, 403)
        self.assertEqual(self.state_path.read_bytes(), before)
        self.assertFalse(self.creates.exists())
        self.assertEqual(self.action("move-done").status, 200, "thread action routes are absent")

    def test_web_validates_action_paths(self):
        self.seed_actions()
        before = self.state_path.read_bytes()
        shell_side_effect = self.root / "unwanted"
        injected_id = "t-00000001;touch%20" + quote(str(shell_side_effect), safe="")
        for ident in ("bad", "t-0000000g", injected_id, "%24(touch%20unwanted)"):
            self.assertEqual(self.action("move-done", ident).status, 400)
        self.assertEqual(self.action("move-done", "t-ffffffff").status, 404)
        for action in ("delete", "move-dropped", "move-", "move"):
            self.assertEqual(self.action(action).status, 404)
        self.assertEqual(self.state_path.read_bytes(), before)
        self.assertFalse(shell_side_effect.exists())
        self.assertFalse(self.creates.exists())

    def test_web_move_targets_use_real_threads_cli(self):
        self.seed_actions()
        listing = self.request("GET", "/api/threads", cookie=self.cookie)
        self.assertEqual(listing.status, 200, "thread list route is absent")
        row = json.loads(listing.text)["threads"][0]
        self.assertEqual((row["status"], row["display_status"]), ("dropped", "dropped"))
        self.assertEqual(row["title"], self.thread["title"])
        for action, expected, shown in (
                ("move-done", {"kind": "work", "status": "closed_by_sam", "done_by": "sam"}, "closed_by_sam"),
                ("move-idea", {"kind": "idea", "status": "open"}, "open"),
                ("move-open", {"kind": "work", "status": "open"}, "open")):
            response = self.action(action)
            self.assertEqual(response.status, 200, response.text)
            self.assertEqual(json.loads(response.text), {"ok": True, "id": self.thread["id"], "action": action})
            stored = json.loads(self.state_path.read_text())
            self.assertEqual({key: stored.get(key) for key in expected}, expected)
            if action != "move-done":
                self.assertNotIn("done_by", stored)
            self.assertEqual("kept_open" in stored, action == "move-open")
            derived = json.loads(self.request("GET", "/api/threads", cookie=self.cookie).text)["threads"][0]
            self.assertEqual(derived["display_status"], shown)
        for retired in ("close", "reopen"):
            self.assertEqual(self.action(retired).status, 404)
        self.assertFalse(self.creates.exists())

    def test_web_busy_thread_lock_returns_409(self):
        self.seed_actions()
        before = self.state_path.read_bytes()
        with Path(str(self.state_path) + ".flock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            response = self.action("move-done")
        self.assertEqual(response.status, 409, response.text)
        self.assertEqual(json.loads(response.text), {"ok": False, "error": "busy", "message": "busy, retry"})
        self.assertEqual(self.state_path.read_bytes(), before)
        self.assertFalse(self.creates.exists())

    def test_web_resume_twice_is_refused(self):
        self.seed_actions()
        before = self.state_path.read_bytes()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda _: self.action("resume"), range(2)))
        self.assertEqual(sorted(r.status for r in responses), [200, 409])
        refused = next(r for r in responses if r.status == 409)
        self.assertEqual(json.loads(refused.text), {"ok": False, "error": "already_resuming", "message": "Already resuming"})
        self.assertEqual(self.creates.read_text().splitlines(), ["create"])
        self.assertEqual(self.state_path.read_bytes(), before)

    def test_web_resume_cmux_down_returns_brief(self):
        self.seed_actions()
        expected = subprocess.run(["/bin/bash", str(REPO / "bin/threads.sh"), "resume", self.thread["id"]],
                                  env=self.env, capture_output=True, text=True, timeout=10).stdout.strip()
        (self.root / "tools/cmux").unlink()
        response = self.action("resume")
        self.assertEqual(response.status, 503, response.text)
        self.assertEqual(json.loads(response.text), {"ok": False, "error": "cmux_unavailable",
                         "message": "cmux is unavailable", "brief": expected})
        self.assertFalse(self.creates.exists())

    def test_web_action_deadlines_and_subprocess_errors(self):
        self.seed_actions()
        module = self.load_module()
        server = module.make_server({"autodream_dir": self.install,
                                     "web_dir": self.install / "web"}, 0)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        self.origin = server.origin
        before = self.state_path.read_bytes()
        try:
            with mock.patch.object(module, "run_bounded") as run:
                for action, deadline in (("move-open", 30), ("move-idea", 30), ("move-done", 30), ("resume", 20)):
                    run.side_effect = subprocess.TimeoutExpired("threads.sh", deadline)
                    response = self.action(action)
                    self.assertEqual(response.status, 504)
                    error = json.loads(response.text)
                    self.assertFalse(error["ok"])
                    self.assertEqual(error["error"], "timeout")
                    self.assertIn("outcome is unknown", error["message"])
                    self.assertIn("Refresh", error["message"])
                    argv = ["/bin/bash", str(REPO / "bin/threads.sh"), "resume", self.thread["id"], "--launch"]
                    if action != "resume":
                        argv = ["/bin/bash", str(REPO / "bin/threads.sh"), "move", self.thread["id"], action[5:]]
                    self.assertEqual(run.call_args.args, (argv,))
                    self.assertEqual(run.call_args.kwargs["timeout"], deadline)
                run.side_effect = None
                for rc, stderr, status, error in (
                        (75, "", 409, "busy"), (76, "", 409, "already_resuming"),
                        (69, "threads: claude CLI is unavailable", 503, "launch_failed"),
                        (70, "threads: cmux workspace creation failed", 503, "launch_failed"),
                        (1, "unexpected CLI failure", 503, "command_failed")):
                    run.return_value = subprocess.CompletedProcess([], rc, "Copyable brief", stderr)
                    response = self.action("resume")
                    self.assertEqual(response.status, status)
                    data = json.loads(response.text)
                    self.assertEqual(data["error"], error)
                    if rc in (69, 70):
                        self.assertEqual(data["brief"], "Copyable brief")
                run.side_effect = OSError("cannot execute")
                response = self.action("move-done")
                self.assertEqual(response.status, 503)
                self.assertEqual(json.loads(response.text)["error"], "command_unavailable")
            self.assertEqual(self.state_path.read_bytes(), before)
            self.assertFalse(self.creates.exists())
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=3)

    def test_web_static_routes_are_fixed(self):
        self.start_server()
        cookie = self.login()
        for path, content_type in (("/", "text/html"), ("/web/app.js", "text/javascript"),
                                   ("/web/app.css", "text/css"), ("/web/threads.js", "text/javascript"),
                                   ("/web/threads.css", "text/css")):
            response = self.request("GET", path, cookie=cookie)
            self.assertEqual(response.status, 200)
            self.assertIn(content_type, response.headers["Content-Type"])
        for path in ("/threads.jsonl", "/web/../web-token", "/web/%2e%2e/web-token",
                     "//web-token", "/web/index.html"):
            response = self.request("GET", path, cookie=cookie)
            self.assertEqual(response.status, 404)
            self.assertNotIn(self.token, response.text)
        (self.install / "web/app.js").unlink()
        self.assertEqual(self.request("GET", "/web/app.js", cookie=cookie).status, 404)

    def test_web_open_refuses_foreign_service_without_sending_token(self):
        module = self.load_module()
        token = module.load_or_create_token(self.install / "web-token")
        requests = []
        shim = self.root / "blocked-opener"
        shim.mkdir()
        marker = self.root / "opener-called"
        opener = shim / ("open" if sys.platform == "darwin" else "xdg-open")
        opener.write_text("#!/bin/sh\ntouch '" + str(marker) + "'\n")
        opener.chmod(0o755)

        class Foreign(BaseHTTPRequestHandler):
            def do_GET(handler):
                requests.append((handler.path, str(handler.headers)))
                handler.send_response(200)
                handler.end_headers()
                handler.wfile.write(b"0" * 64)

            def log_message(*args):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), Foreign) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            env = dict(self.env, AUTODREAM_WEB_PORT=str(server.server_port),
                       PATH=str(shim) + os.pathsep + os.environ['PATH'])
            try:
                for args in (("open", "--print"), ("open",)):
                    result = self.run_command(*args, env=env)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"port {server.server_port} is not this autodream-web", result.stderr)
                    self.assertNotIn(token, result.stdout + result.stderr)
            finally:
                server.shutdown()
                worker.join()
        self.assertFalse(marker.exists(), "foreign service must never invoke the browser")
        self.assertEqual(len(requests), 2)
        for path, headers in requests:
            self.assertRegex(path, r"^/api/identify\?nonce=[0-9a-f]{32}$")
            self.assertNotIn(token, path + headers)

    def test_web_identity_challenge_and_private_browser_handoff(self):
        self.start_server()
        nonce = "1234567890abcdef" * 2
        proof = self.request("GET", "/api/identify?nonce=" + nonce)
        self.assertEqual(proof.status, 200)
        self.assertEqual(proof.text, hmac.new(self.token.encode(), nonce.encode(), hashlib.sha256).hexdigest())
        self.assertIsNone(proof.headers.get("Set-Cookie"))
        for query in ("", "?nonce=x", "?nonce=" + nonce + "&nonce=" + nonce):
            self.assertEqual(self.request("GET", "/api/identify" + query).status, 400)
        self.assertEqual(self.request("GET", "/api/identify?nonce=" + nonce, host="evil.example").status, 421)
        self.assertEqual(self.request("HEAD", "/api/identify?nonce=" + nonce).status, 401)
        shim = self.root / "opener"
        shim.mkdir()
        capture = self.root / "handoff.json"
        opener = shim / ("open" if sys.platform == "darwin" else "xdg-open")
        opener.write_text("#!" + sys.executable + "\n" +
                          "import json, pathlib, sys\n" +
                          "pathlib.Path(" + repr(str(capture)) + ").write_text(json.dumps({'argv': sys.argv}))\n")
        opener.chmod(0o755)
        handoff_path = self.install / "web-login.html"
        previous = self.root / "previous-handoff"
        previous.write_text("untouched")
        handoff_path.symlink_to(previous)
        result = self.run_command("open", env=dict(self.env, AUTODREAM_WEB_PORT=str(self.port),
                                  PATH=str(shim) + os.pathsep + os.environ["PATH"]))
        self.assertEqual(result.returncode, 0, result.stderr)
        handoff = json.loads(capture.read_text())
        self.assertNotIn(self.token, " ".join(handoff["argv"]))
        opened_path = Path(urllib.parse.unquote(urllib.parse.urlsplit(handoff["argv"][1]).path))
        self.assertTrue(opened_path.exists(), "browser handoff must survive the opener returning")
        self.assertEqual(opened_path, handoff_path)
        self.assertFalse(handoff_path.is_symlink())
        self.assertEqual(previous.read_text(), "untouched")
        self.assertEqual(stat.S_IMODE(handoff_path.stat().st_mode), 0o600)
        page = handoff_path.read_text()
        self.assertIn(self.origin + "/login?t=" + self.token, page)
        self.assertIn('http-equiv="refresh"', page)
        for query in ("", "?t=wrong", "?t=" + self.token + "&t=wrong"):
            with self.subTest(query=query):
                self.assertEqual(self.request("GET", "/login" + query).status, 401)
                self.assertEqual(handoff_path.read_text(), page)
        cookie = self.login()
        self.assertFalse(handoff_path.exists())
        self.assertEqual(self.request("GET", "/", cookie=cookie).status, 200)
        self.login()

    def test_web_open_uses_config_and_environment_precedence(self):
        self.start_server()
        (self.install / "config").write_text(f"AUTODREAM_WEB_PORT={self.port}\n")
        configured = self.run_command("open", "--print")
        self.assertEqual(configured.returncode, 0, configured.stderr)
        token = (self.install / "web-token").read_text().strip()
        self.assertEqual(configured.stdout.strip(), self.origin + "/login?t=" + token)
        (self.install / "config").write_text("AUTODREAM_WEB_PORT=0\n")
        overridden = self.run_command("open", "--print", env=dict(self.env, AUTODREAM_WEB_PORT=str(self.port)))
        self.assertEqual(overridden.returncode, 0, overridden.stderr)
        self.assertEqual(overridden.stdout, configured.stdout)
        (self.install / "config").write_text(f"AUTODREAM_WEB_PORT={self.port}\n")
        for name in ("autodream-web", "autodream-web.py", "lib-install-dir.sh", "portable.sh"):
            (self.install / name).symlink_to(REPO / "bin" / name)
        env = dict(self.env)
        env.pop("AUTODREAM_DIR")
        linked = subprocess.run(["/bin/bash", str(self.install / "autodream-web"),
                                 "open", "--print"], env=env, capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(linked.stdout, configured.stdout)

    def test_web_open_discovers_running_server_port_without_config(self):
        self.start_server()
        port_file = self.install / "web-port"
        self.assertEqual(port_file.read_text().strip(), str(self.port))
        self.assertEqual(stat.S_IMODE(port_file.stat().st_mode), 0o600)
        (self.install / "config").write_text("AUTODREAM_WEB_PORT=1\n")
        opened = self.run_command("open", "--print")
        self.assertEqual(opened.returncode, 0, opened.stderr)
        token = (self.install / "web-token").read_text().strip()
        self.assertEqual(opened.stdout.strip(), self.origin + "/login?t=" + token)

    def test_web_open_falls_back_to_service_started_before_web_port(self):
        self.start_server()
        (self.install / "web-port").unlink()
        module = self.load_module()
        module.PRE_RECORD_PORT = self.port
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            closed = probe.getsockname()[1]
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"AUTODREAM_DIR": str(self.install),
                                          "AUTODREAM_WEB_PORT": str(closed)}), \
                mock.patch.object(sys, "argv", ["autodream-web.py", "open", "--print"]), \
                contextlib.redirect_stdout(out):
            self.assertIsNone(module.main())
        self.assertEqual(out.getvalue().strip(), self.origin + "/login?t=" + self.token)

    def test_web_token_creation_is_exclusive_and_persistent(self):
        module = self.load_module()
        path = self.install / "web-token"
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            results = list(executor.map(lambda _: module.load_or_create_token(path), range(6)))
        self.assertEqual(len(set(results)), 1)
        self.start_server()
        self.env['AUTODREAM_WEB_PORT'] = str(self.port)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        path.chmod(0o644)
        self.assertEqual(self.run_command("open", "--print").returncode, 0)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        path.unlink()
        outside = self.root / "outside"
        outside.write_text("do not change")
        path.symlink_to(outside)
        self.assertNotEqual(self.run_command("open", "--print").returncode, 0)
        self.assertEqual(outside.read_text(), "do not change")

    def test_web_dream_dates_and_question_reader(self):
        dreams = self.root / "dreams"
        dreams.mkdir()
        self.env["DREAMS_DIR"] = str(dreams)
        for name in ("2026-11-14.md", "2026-11-13.md", "2026-11-14.md.stale-1",
                     "2026-02-30.md", "other.md"):
            (dreams / name).write_text("# Dream\n<!-- autodream:open-questions=2 -->\n")
        (dreams / "2026-11-13.md").write_text("## Open questions\nAn old uncertain report")
        self.start_server()
        cookie = self.login()
        dates = self.request("GET", "/api/dreams", cookie=cookie)
        self.assertEqual(dates.status, 200, "dream endpoints have not been implemented")
        self.assertEqual(json.loads(dates.text), {"dates": ["2026-11-14", "2026-11-13"]})
        dream = json.loads(self.request("GET", "/api/dreams/2026-11-14", cookie=cookie).text)
        self.assertEqual(dream["open_questions"], 2)
        self.assertIn("# Dream", dream["markdown"])
        old = json.loads(self.request("GET", "/api/dreams/2026-11-13", cookie=cookie).text)
        self.assertIsNone(old["open_questions"])
        for date in ("2026-02-30", "../web-token", "%2e%2e%2fweb-token", "2026-11-14.md"):
            self.assertEqual(self.request("GET", "/api/dreams/" + date, cookie=cookie).status, 400)
        self.assertEqual(self.request("GET", "/api/dreams/2026-11-12", cookie=cookie).status, 404)
        command = subprocess.run(["/bin/bash", str(REPO / "bin/report-format.sh"),
                                  "open-questions", str(dreams / "2026-11-14.md")],
                                 capture_output=True, text=True, timeout=3)
        self.assertEqual(command.stdout.strip(), "2")

    def test_web_lately_reads_artifacts_and_threads(self):
        recent_date = (date.today() - timedelta(days=1)).isoformat()
        day = self.install / "findings" / recent_date
        day.mkdir(parents=True)
        (day / "0123456789ab.json").write_text(json.dumps({
            "project": "-repo", "underlying_goal": "Private goal", "outcome": "not_achieved"}))
        (day / "0123456789ab.stats.json").write_text(json.dumps({
            "nested": False, "user_message_count": 1, "tool_call_count": 2, "duration_minutes": 3}))
        thread = {"id": "t-12345678", "kind": "idea", "repo": "/gone/repo",
                  "title": "Idea", "goal": "Private goal", "status": "open", "done_by": None,
                  "last_seen": recent_date, "sessions": [{"date": recent_date,
                  "hash": "0123456789ab", "outcome": "not_achieved"}]}
        (self.install / "threads.jsonl").write_text(json.dumps(thread) + "\n")
        self.start_server()
        cookie = self.login()
        response = self.request("GET", "/api/lately?days=7", cookie=cookie)
        self.assertEqual(response.status, 200, "Lately endpoint has not been implemented")
        data = json.loads(response.text)
        self.assertEqual(data["days"], 7)
        project = data["timeline"][0]["projects"][0]
        self.assertEqual(project["repo"], "/gone/repo")
        self.assertEqual(project["sessions"][0]["goal"], "Private goal")
        self.assertEqual(data["threads"], {"open": 0, "dropped": 0, "ideas": 1})
        thread["status"] = "done"
        (self.install / "threads.jsonl").write_text(json.dumps(thread) + "\n")
        data = json.loads(self.request("GET", "/api/lately", cookie=cookie).text)
        self.assertEqual(data["threads"]["ideas"], 0)
        for days in ("0", "-1", "no", "1&days=2", "366"):
            self.assertEqual(self.request("GET", "/api/lately?days=" + days, cookie=cookie).status, 400)

    def test_web_lately_project_rows_aggregate_outcomes_and_recent_goal(self):
        recent_date = (date.today() - timedelta(days=1)).isoformat()
        day = self.install / "findings" / recent_date
        day.mkdir(parents=True)
        common = Path(subprocess.run(["git", "-C", str(REPO), "rev-parse", "--git-common-dir"],
                                     check=True, capture_output=True, text=True).stdout.strip()).resolve()
        repo = common.parent
        worktree = REPO
        bucket = "-Users-fixture-git-project"
        for session_hash, goal, outcome, mtime in (
                ("0123456789ab", "Earlier goal", "partially_achieved", 10),
                ("111111111111", "Latest goal", "mostly_achieved", 20)):
            (day / (session_hash + ".json")).write_text(json.dumps({
                "project": bucket, "underlying_goal": goal, "outcome": outcome}))
            (day / (session_hash + ".stats.json")).write_text(json.dumps({
                "nested": False, "user_message_count": 1, "tool_call_count": 2,
                "duration_minutes": 3, "transcript_mtime": mtime}))
        (day / "pin-projects.tsv").write_text(bucket + "\t" + str(worktree) + "\n")
        (day / "session-cwds.tsv").write_text(
            "0123456789ab\t" + str(worktree) + "\n"
            "111111111111\t" + str(worktree) + "\n")
        self.start_server()
        cookie = self.login()
        response = self.request("GET", "/api/lately?days=7", cookie=cookie)
        self.assertEqual(response.status, 200)
        project = json.loads(response.text)["timeline"][0]["projects"][0]
        self.assertEqual(project["repo"], str(repo.resolve()))
        self.assertEqual(project["session_count"], 2)
        self.assertEqual(project["outcomes"], {
            "fully_or_mostly": 1, "partially": 1, "not_achieved": 0, "unclear": 0, "unmeasured": 0})
        self.assertEqual(project["latest_goal"], "Latest goal")
        self.assertEqual(project["sessions"][0]["goal"], "Latest goal")

    def test_web_subprocesses_are_bounded(self):
        module = self.load_module()
        result = module.run_bounded([sys.executable, "-c", "import sys; print(sys.stdin.read())"],
                                    input="literal $(touch unwanted)")
        self.assertEqual(result.stdout.strip(), "literal $(touch unwanted)")
        with self.assertRaises(subprocess.TimeoutExpired):
            module.run_bounded([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.05)


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WebTests))
    print(f"passed: {result.testsRun - len(result.failures) - len(result.errors)}   "
          f"failed: {len(result.failures) + len(result.errors)}")
    sys.exit(not result.wasSuccessful())
