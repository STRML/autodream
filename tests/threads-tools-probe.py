#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import subprocess
import tempfile
import threading
import sys
from http.server import BaseHTTPRequestHandler

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from loopback_http import LoopbackHTTPServer


class ReusableHTTPServer(LoopbackHTTPServer):
    allow_reuse_address = True


class Provider(BaseHTTPRequestHandler):
    calls = 0
    advertised_tools = []
    marker = None
    request_path = None

    def log_message(self, *_args):
        pass

    def do_POST(self):
        type(self).request_path = self.path
        size = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(size))
        type(self).advertised_tools.append(body.get("tools", []))
        call = type(self).calls
        type(self).calls += 1
        if not self.path.split("?", 1)[0].endswith("/messages"):
            self.send_error(404)
            return
        if body.get("stream"):
            return self.write_anthropic_stream(call)
        response = self.anthropic_response(call)
        encoded = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def write_anthropic_stream(self, call):
        response = self.anthropic_response(call)
        message = {
            "id": response["id"],
            "type": "message",
            "role": "assistant",
            "model": response["model"],
            "content": [],
            "stop_reason": None,
            "stop_sequence": None,
            "usage": response["usage"],
        }
        events = [("message_start", {"type": "message_start", "message": message})]
        for index, block in enumerate(response["content"]):
            if block["type"] == "tool_use":
                started = {"type": "tool_use", "id": block["id"], "name": block["name"], "input": {}}
                delta = {"type": "input_json_delta", "partial_json": json.dumps(block["input"])}
            else:
                started = {"type": "text", "text": ""}
                delta = {"type": "text_delta", "text": block["text"]}
            events.append(("content_block_start", {"type": "content_block_start", "index": index, "content_block": started}))
            events.append(("content_block_delta", {"type": "content_block_delta", "index": index, "delta": delta}))
            events.append(("content_block_stop", {"type": "content_block_stop", "index": index}))
        events.append(("message_delta", {"type": "message_delta", "delta": {"stop_reason": response["stop_reason"], "stop_sequence": None}, "usage": {"output_tokens": 2}}))
        events.append(("message_stop", {"type": "message_stop"}))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        for name, payload in events:
            self.wfile.write(("event: %s\ndata: %s\n\n" % (name, json.dumps(payload))).encode())
        self.wfile.flush()
        self.close_connection = True

    @classmethod
    def anthropic_response(cls, call):
        if call < 2:
            name = "Write" if call == 0 else "Bash"
            if call == 0:
                value = {"file_path": str(cls.marker), "content": "written"}
            else:
                value = {"command": "printf attempted > " + str(cls.marker)}
            content = [{"type": "tool_use", "id": "tool-" + str(call), "name": name, "input": value}]
            stop = "tool_use"
        else:
            content = [{"type": "text", "text": '{"hash":"probe","thread":"new","finished":false}'}]
            stop = "end_turn"
        return {
            "id": "msg_probe",
            "type": "message",
            "role": "assistant",
            "model": "claude-haiku-5-5",
            "content": content,
            "stop_reason": stop,
            "stop_sequence": None,
            "usage": {"input_tokens": 2, "output_tokens": 2},
        }

def assert_true(test, message):
    if not test:
        raise AssertionError(message)


def decode_argv(path):
    data = pathlib.Path(path).read_bytes()
    values = data.split(b"\0")
    assert_true(values[-1] == b"", "adapter argv is not NUL-terminated")
    return [value.decode() for value in values[:-1]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", choices=("claude", "omp"), required=True)
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parents[1]
    adapter = repo / "adapters" / args.engine / "adapter.sh"

    with tempfile.TemporaryDirectory(prefix="threads-probe-") as scratch:
        root = pathlib.Path(scratch)
        Provider.calls = 0
        Provider.advertised_tools = []
        Provider.marker = root / "tool-write-marker"
        server = ReusableHTTPServer(("127.0.0.1", 0), Provider)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = "http://127.0.0.1:%d" % server.server_port
            argv_path = root / "argv"
            adapter_env = os.environ.copy()
            adapter_env["CLAUDE_BIN" if args.engine == "claude" else "OMP_BIN"] = os.environ.get(
                "CLAUDE_BIN" if args.engine == "claude" else "OMP_BIN", args.engine
            )
            if args.engine == "omp":
                adapter_env["NO_ADVISOR_CFG"] = str(repo / "adapters" / "omp" / "l1-no-advisor.yml")
            model = "claude-haiku-5-5" if args.engine == "claude" else "anthropic/claude-haiku-5-5"
            with argv_path.open("wb") as output:
                built = subprocess.run([str(adapter), "threads-argv", model], env=adapter_env, stdout=output)
            assert_true(built.returncode == 0, "threads-argv must exist before probing the CLI")
            argv = decode_argv(argv_path)
            argv[0] = adapter_env["CLAUDE_BIN" if args.engine == "claude" else "OMP_BIN"]
            env = {
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "HOME": str(root),
                "TMPDIR": str(root),
                "NO_COLOR": "1",
                "CI": "1",
                "ANTHROPIC_BASE_URL": base_url,
                "ANTHROPIC_API_KEY": "loopback-dummy-key",
                "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1",
                "DISABLE_TELEMETRY": "1",
                "DISABLE_ERROR_REPORTING": "1",
                "CLAUDE_CONFIG_DIR": str(root / "claude-config"),
                "PI_CODING_AGENT_DIR": str(root / "omp-agent"),
            }
            pathlib.Path(env["CLAUDE_CONFIG_DIR"]).mkdir()
            pathlib.Path(env["PI_CODING_AGENT_DIR"]).mkdir()
            if args.engine == "claude":
                env["CLAUDE_CODE_DISABLE_NON_ESSENTIAL_TRAFFIC"] = "1"
            result = subprocess.run(
                argv,
                input="Return the JSONL assignment {\"hash\":\"probe\",\"thread\":\"new\",\"finished\":false}.",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=180,
            )
            assert_true(
                result.returncode == 0,
                "CLI exited %d: stdout=%r stderr=%r calls=%d tools=%r path=%r"
                % (result.returncode, result.stdout[-2000:], result.stderr[-2000:], Provider.calls, Provider.advertised_tools, Provider.request_path),
            )
            assert_true(not Provider.marker.exists(), "a provider tool request wrote the marker")
            assert_true(Provider.calls >= 3, "provider did not send both tool requests and the assignment")
            assert_true(
                all(tools == [] for tools in Provider.advertised_tools),
                "provider saw advertised tools: %r" % Provider.advertised_tools,
            )
            assert_true('{"hash":"probe","thread":"new","finished":false}' in result.stdout, "assignment was not returned: %r" % result.stdout)
            print("PASS %s tools probe: marker absent, tools empty, assignment received" % args.engine)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    main()
