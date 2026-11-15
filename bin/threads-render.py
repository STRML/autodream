#!/usr/bin/env python3
import argparse
import datetime
import json
import os
import re
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
        and isinstance(item.get("last_seen"), str)
        and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", item["last_seen"]) is not None
    )


def display_status(item, as_of, dropped_days):
    if item["status"] != "open":
        return item["status"]
    newest = max(item["sessions"], key=lambda row: row.get("date", ""), default={})
    outcome = newest.get("outcome", "") if isinstance(newest, dict) else ""
    if outcome not in {"not_achieved", "partially_achieved", "unclear_from_transcript"}:
        return "open"
    cutoff = as_of - datetime.timedelta(days=dropped_days)
    try:
        last_seen = datetime.date.fromisoformat(item["last_seen"])
    except ValueError:
        raise ValueError("thread has an invalid last_seen date")
    return "dropped" if last_seen < cutoff else "open"


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


def render(state_path, output_path, as_of_text):
    as_of = datetime.date.fromisoformat(as_of_text)
    dropped_days = int(os.environ.get("AUTODREAM_THREADS_DROPPED_DAYS", "7"), 10)
    if dropped_days < 1:
        raise ValueError("AUTODREAM_THREADS_DROPPED_DAYS must be positive")
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
    threads = []
    for item in state:
        if not valid_thread(item):
            raise ValueError("state contains an invalid thread")
        item = dict(item)
        item["display_status"] = display_status(item, as_of, dropped_days)
        threads.append(item)
    ids = [item["id"] for item in threads]
    if len(ids) != len(set(ids)):
        raise ValueError("state contains duplicate thread IDs")
    payload = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "as_of": as_of_text,
        "threads": threads,
    }
    json_text = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).replace("<", r"\u003c")
    template = template_path(Path(__file__).resolve().parent).read_text(encoding="utf-8")
    marker = "__THREADS_JSON__"
    if template.count(marker) != 1:
        raise ValueError("template must contain one data marker")
    page = template.replace(marker, json_text)
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
