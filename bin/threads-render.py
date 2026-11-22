#!/usr/bin/env python3
import argparse
import datetime
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path


def valid_thread(item):
    return (
        isinstance(item, dict)
        and isinstance(item.get("id"), str)
        and re.fullmatch(r"t-[0-9a-f]{8}", item["id"]) is not None
        and item.get("kind") in {"work", "idea"}
        and isinstance(item.get("repo"), str)
        and isinstance(item.get("title"), str)
        and isinstance(item.get("goal"), str)
        and isinstance(item.get("sessions"), list)
        and all(
            isinstance(row, dict)
            and isinstance(row.get("date"), str)
            and isinstance(row.get("hash"), str)
            for row in item["sessions"]
        )
        and item.get("status") in {"open", "done", "closed_by_sam"}
        and (item.get("done_by") is None or isinstance(item.get("done_by"), str))
        and (item.get("kept_open") is None
             or (isinstance(item["kept_open"], str)
                 and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", item["kept_open"]) is not None))
        and isinstance(item.get("last_seen"), str)
        and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", item["last_seen"]) is not None
    )


def template_path(renderer_dir):
    installed = os.environ.get("AUTODREAM_THREADS_TEMPLATE")
    options = ([Path(installed)] if installed else []) + [
        renderer_dir.parent / "templates" / "threads.html",
        renderer_dir / "threads-template.html",
    ]
    for path in options:
        if path.is_file():
            return path
    raise FileNotFoundError("threads.html template was not found")


def derive_display_status(state, as_of_text):
    renderer_dir = Path(__file__).resolve().parent
    portable_path = renderer_dir / "portable.sh"
    status_path = renderer_dir / "threads-status.jq"
    if not portable_path.is_file() or not status_path.is_file():
        raise ValueError("threads status dependencies were not found")
    dropped_days_text = os.environ.get("AUTODREAM_THREADS_DROPPED_DAYS", "7")
    if not re.fullmatch(r"[0-9]{1,9}", dropped_days_text) or int(dropped_days_text) < 1:
        raise ValueError("invalid AUTODREAM_THREADS_DROPPED_DAYS")
    script = (
        '. "$1" || exit 1; '
        'tmo 10 jq -c --arg mode render --arg as_of "$2" '
        '--arg previous_as_of "" --argjson dropped_days "$3" '
        '--arg status_filter "" --arg kind_filter "" --arg repo_filter "" '
        '--arg query "" --arg json 1 -f "$4" "$5"'
    )
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json") as state_file:
        json.dump(state, state_file, ensure_ascii=False)
        state_file.flush()
        result = subprocess.run(
            ["/bin/bash", "-c", script, "threads-status", str(portable_path), as_of_text,
             dropped_days_text, str(status_path), state_file.name],
            stdin=subprocess.DEVNULL, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
    if result.returncode:
        if result.returncode in {124, 137, 143}:
            raise ValueError("status calculation timed out after 10 seconds")
        raise ValueError("status calculation failed")
    try:
        annotated = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ValueError("status calculation returned invalid JSON") from error
    return annotated


def render(state_path, output_path, as_of_text):
    datetime.date.fromisoformat(as_of_text)
    if state_path == "-":
        state = json.load(sys.stdin)
        if not isinstance(state, list):
            raise ValueError("state must be a JSON array")
    elif Path(state_path).exists():
        state = []
        with open(state_path, encoding="utf-8") as stream:
            for line in stream:
                if not line.strip():
                    continue
                state.append(json.loads(line))
    else:
        state = []
    if any(not valid_thread(item) for item in state):
        raise ValueError("state contains an invalid thread")
    if any("display_status" not in item for item in state if isinstance(item, dict)):
        state = derive_display_status(state, as_of_text)
    threads = []
    for item in state:
        item = dict(item)
        threads.append(item)
    ids = [item["id"] for item in threads]
    if len(ids) != len(set(ids)):
        raise ValueError("state contains duplicate thread IDs")
    payload = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "as_of": as_of_text,
        "cli": shlex.quote(os.environ.get("AUTODREAM_THREADS_CLI", "threads.sh")),
        "threads": threads,
    }
    json_text = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).replace("<", r"\u003c")
    template = template_path(Path(__file__).resolve().parent).read_text(encoding="utf-8")
    marker = "__THREADS_JSON__"
    if template.count(marker) != 1:
        raise ValueError("template must contain one data marker")
    replacements = {marker: json_text}
    renderer_dir = Path(__file__).resolve().parent
    assets = renderer_dir.parent / "web"
    if not assets.is_dir():
        assets = renderer_dir / "web"
    for marker, name in (("__THREADS_JS__", "threads.js"), ("__THREADS_CSS__", "threads.css")):
        if template.count(marker) != 1:
            raise ValueError("template must contain one " + marker + " marker")
        replacements[marker] = (assets / name).read_text(encoding="utf-8")
    page = re.sub(r"__THREADS_(?:JSON|JS|CSS)__", lambda match: replacements[match[0]], template)
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=str(output.parent),
            prefix=".threads.html.", suffix=".tmp", delete=False,
        ) as stream:
            temp_path = Path(stream.name)
            stream.write(page)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(str(temp_path), str(output))
        temp_path = None
    finally:
        if temp_path is not None:
            try:
                temp_path.unlink()
            except FileNotFoundError:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("state")
    parser.add_argument("output")
    parser.add_argument("--as-of", required=True)
    args = parser.parse_args()
    render(args.state, args.output, args.as_of)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print("threads-render: %s" % error, file=sys.stderr)
        raise SystemExit(1)
