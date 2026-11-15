#!/usr/bin/env python3
import concurrent.futures
from datetime import date, timedelta
import http.client
import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
import stat
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request


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
        (self.install / "threads.jsonl").write_text(PRIVATE_GOAL)

    def run_command(self, *args, env=None):
        self.assertTrue(COMMAND.is_file(), "local web command has not been implemented")
        return subprocess.run(["/bin/bash", str(COMMAND), *args],
                              env=env or self.env, capture_output=True, text=True,
                              timeout=15)

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
            response = opener.open(request, timeout=3)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            result = Response(response)
        with (self.root / "http-transcript.txt").open("a") as transcript:
            transcript.write(f"{method} {path.split('?')[0]} -> {result.status}\n")
        return result

    def login(self):
        response = self.request("GET", "/login?t=" + self.token)
        self.assertEqual(response.status, 303)
        return response.headers["Set-Cookie"].split(";", 1)[0]

    def test_web_requires_cookie(self):
        self.start_server()
        for path in ("/", "/web/app.js", "/web/app.css", "/api/lately", "/threads.jsonl"):
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
        self.assertEqual(response.status, 303)
        self.assertEqual(response.headers["Location"], "/")
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

    def test_web_post_requires_session_origin_and_custom_header(self):
        self.start_server()
        cookie = self.login()
        path = "/api/threads/t-12345678/close"
        self.assertEqual(self.request("POST", path, origin=self.origin,
                                     headers={"X-Autodream": "1"}).status, 401)
        for origin, marker in ((None, "1"), ("http://evil.example", "1"),
                               (self.origin + "/", "1"), (self.origin, None),
                               (self.origin, "0")):
            headers = {} if marker is None else {"X-Autodream": marker}
            response = self.request("POST", path, cookie=cookie, origin=origin, headers=headers)
            self.assertEqual(response.status, 403)
        response = self.request("POST", path, cookie=cookie, origin=self.origin,
                                headers={"X-Autodream": "1"})
        self.assertEqual(response.status, 404)
        self.assertEqual((self.install / "threads.jsonl").read_text(), PRIVATE_GOAL)
        self.assertEqual(self.request("OPTIONS", path, host="evil.example").status, 421)

    def test_web_static_routes_are_fixed(self):
        self.start_server()
        cookie = self.login()
        for path, content_type in (("/", "text/html"), ("/web/app.js", "text/javascript"),
                                   ("/web/app.css", "text/css")):
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

    def test_web_open_uses_config_and_environment_precedence(self):
        (self.install / "config").write_text("AUTODREAM_WEB_PORT=12345\n")
        configured = self.run_command("open", "--print")
        self.assertEqual(configured.returncode, 0, configured.stderr)
        token = (self.install / "web-token").read_text().strip()
        self.assertEqual(configured.stdout.strip(), "http://127.0.0.1:12345/login?t=" + token)
        env = dict(self.env, AUTODREAM_WEB_PORT="23456")
        overridden = self.run_command("open", "--print", env=env)
        self.assertEqual(overridden.stdout.strip(), "http://127.0.0.1:23456/login?t=" + token)
        for name in ("autodream-web", "autodream-web.py", "lib-install-dir.sh", "portable.sh"):
            (self.install / name).symlink_to(REPO / "bin" / name)
        env = dict(self.env)
        env.pop("AUTODREAM_DIR")
        linked = subprocess.run(["/bin/bash", str(self.install / "autodream-web"),
                                 "open", "--print"], env=env, capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(linked.stdout, configured.stdout)

    def test_web_token_creation_is_exclusive_and_persistent(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            results = list(executor.map(lambda _: self.run_command("open", "--print"), range(6)))
        self.assertEqual([result.returncode for result in results], [0] * 6)
        self.assertEqual(len({result.stdout for result in results}), 1)
        path = self.install / "web-token"
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
