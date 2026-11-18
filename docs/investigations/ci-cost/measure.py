#!/usr/bin/env python3
"""Measure this repo's GitHub Actions wall time and runner minutes over a window.

    python3 docs/investigations/ci-cost/measure.py --since 2026-10-19 [--until 2026-11-17] [--cache DIR]

Reads runs and their jobs through `gh api`, caches each run's jobs as JSON under --cache (default
$TMPDIR/ci-measure) so a second call costs no API requests, and prints one table per workflow,
trigger and conclusion. Minutes are per job, rounded up to the minute as GitHub bills them.
The repo is public, so these minutes cost nothing; the macOS column is reported on its own because
a private repo would pay it at 10x.
"""
import argparse
import json
import math
import os
import statistics
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone

REPO = "STRML/autodream"


def gh(path):
    out = subprocess.run(["gh", "api", "-X", "GET", path], capture_output=True, text=True)
    if out.returncode:
        sys.exit("gh api %s failed: %s" % (path, out.stderr.strip()))
    return json.loads(out.stdout)


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def runs_in(since, until):
    runs, page = [], 1
    while True:
        batch = gh("repos/%s/actions/runs?per_page=100&page=%d&created=%s..%s" % (REPO, page, since, until))["workflow_runs"]
        runs += batch
        if len(batch) < 100:
            return [r for r in runs if r["status"] == "completed"]
        page += 1


def jobs_of(run_id, cache):
    path = os.path.join(cache, "jobs-%d.json" % run_id)
    if not os.path.exists(path):
        with open(path, "w") as f:
            json.dump(gh("repos/%s/actions/runs/%d/jobs?per_page=100" % (REPO, run_id)), f)
    with open(path) as f:
        return json.load(f)["jobs"]


def measure(run, jobs):
    ran = [j for j in jobs if j.get("started_at") and j.get("completed_at") and j["conclusion"] != "skipped"]
    if not ran:
        return None
    minutes = macos = 0
    for j in ran:
        m = math.ceil(max((ts(j["completed_at"]) - ts(j["started_at"])).total_seconds(), 1) / 60)
        minutes += m
        if any("macos" in label for label in j.get("labels", [])):
            macos += m
    wall = (max(ts(j["completed_at"]) for j in ran) - ts(run["created_at"])).total_seconds()
    return {"wall": wall, "minutes": minutes, "macos": macos}


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True)
    ap.add_argument("--until", default=datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    ap.add_argument("--cache", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "ci-measure"))
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    groups = defaultdict(list)
    for run in runs_in(a.since, a.until):
        m = measure(run, jobs_of(run["id"], a.cache))
        if m:
            groups[(run["name"], run["event"], run["conclusion"])].append(m)
    print("window %s..%s\n" % (a.since, a.until))
    print("| workflow | trigger | conclusion | runs | wall p50 | wall p90 | runner min | of which macOS |")
    print("|---|---|---|---:|---:|---:|---:|---:|")
    total = mac = 0
    for (wf, ev, c), ms in sorted(groups.items()):
        w = [m["wall"] for m in ms]
        mins = sum(m["minutes"] for m in ms)
        mm = sum(m["macos"] for m in ms)
        total += mins
        mac += mm
        print("| %s | %s | %s | %d | %.1fm | %.1fm | %d | %d |" % (
            wf, ev, c, len(ms), statistics.median(w) / 60, pct(w, 0.9) / 60, mins, mm))
    print("\nrunner minutes: %d (macOS %d; a private repo would bill %d Linux-equivalent)" % (total, mac, total + 9 * mac))


if __name__ == "__main__":
    main()
