#!/usr/bin/env python3
"""Write a synthetic AUTODREAM_DIR for the README screenshots.

Usage: fixture.py <dir>   (creates <dir>/install and <dir>/dreams)

Every session, goal and count here is made up. The repos are public projects, and the
home directory is /Users/dev, so serve with HOME=/Users/dev for ~-relative names. The
folders do not exist, so Lately shows each repo as its ~ path; threads use that form too,
or one repo would show under two names. Dates
are relative to today because Lately shows the trailing seven days.

Retaking the README screenshots (1280x900 viewport), from the repo root:
  D=$(mktemp -d)
  python3 docs/screenshots/fixture.py "$D"
  HOME=/Users/dev AUTODREAM_DIR="$D/install" DREAMS_DIR="$D/dreams" \
    AUTODREAM_CONFIG="$D/install/no-config" bin/autodream-web serve --port 47911
  then set the cookie autodream_session=$(cat "$D/install/web-token") for
  http://127.0.0.1:47911 and load the page. lately.png has the first two goals expanded.
"""
from datetime import date, timedelta
import hashlib
import json
from pathlib import Path
import random
import sys

HOME = '/Users/dev'
REPOS = {
    'rgl': HOME + '/git/oss/react-grid-layout',
    'drag': HOME + '/git/oss/react-draggable',
    'resize': HOME + '/git/oss/react-resizable',
    'dream': HOME + '/git/oss/cc-autodream',
    'omp': HOME + '/git/forks/oh-my-pi',
    'mlx': HOME + '/git/oss/mlx-serve',
}

# (days ago, repo, goal, outcome, user messages, tool calls, minutes)
SESSIONS = [
    (0, 'rgl', 'Stop a compacted layout jumping when an item is dropped from outside the grid',
     'fully_achieved', 14, 96, 52),
    (0, 'rgl', 'Write the v2 migration guide for responsive breakpoints', 'mostly_achieved', 6, 31, 24),
    (0, 'drag', 'Release the 3px drag threshold behind dragConfig.threshold', 'fully_achieved', 9, 64, 41),
    (0, 'dream', 'Show each night in Lately as one compact table per repo', 'mostly_achieved', 22, 188, 134),
    (0, 'dream', 'Stop Stats repeating one notice per night with no stats sidecar', 'fully_achieved', 7, 52, 33),
    (0, 'mlx', 'Find why prefix-cache hits drop after a model swap', 'partially_achieved', 11, 120, 88),
    (1, 'omp', 'Rebase the fork onto upstream and rebuild the CLI', 'fully_achieved', 4, 45, 19),
    (1, 'omp', 'Keep the advisor seat from re-reading the whole transcript each turn',
     'not_achieved', 13, 77, 61),
    (1, 'rgl', 'Reproduce the resize handle drifting at 125% browser zoom', 'unclear_from_transcript',
     5, 22, 14),
    (1, 'resize', 'Add a lockAspectRatio test for every handle direction', 'fully_achieved', 3, 28, 12),
    (1, 'dream', 'Sign the browser in from the file:// handoff that autodream-web open writes',
     'fully_achieved', 10, 71, 46),
    (2, 'mlx', 'Benchmark the paged KV cache against the dense one at 32k context',
     'mostly_achieved', 8, 140, 96),
    (2, 'dream', 'Count sandbox-guard denies per session in the rollup', 'partially_achieved', 9, 83, 57),
    (2, 'drag', 'Drop the findDOMNode fallback for React 19', 'fully_achieved', 6, 39, 27),
    (3, 'rgl', 'Triage the open issues tagged needs-repro', 'mostly_achieved', 12, 58, 70),
    (3, 'omp', 'Port the skill-read detector to the omp stats script', 'fully_achieved', 5, 66, 38),
    (3, 'mlx', 'Cut first-token latency on a cold model load', 'not_achieved', 7, 91, 64),
    (4, 'dream', 'Rebuild a night whose report died during the aggregation step', 'fully_achieved',
     3, 18, 9),
    (4, 'resize', 'Ship the TypeScript definitions in the package', 'mostly_achieved', 8, 47, 35),
    (4, 'rgl', 'Measure render cost of 500 items with useCSSTransforms off', 'partially_achieved',
     6, 54, 43),
    (5, 'drag', 'Answer the bounds-with-transform issue with a runnable example', 'fully_achieved',
     2, 11, 8),
    (5, 'dream', 'Split the test suite into four CI shards', 'fully_achieved', 9, 102, 74),
    (6, 'mlx', 'Write the tensor-parallel launch notes for two hosts', 'mostly_achieved', 4, 26, 21),
    (6, 'omp', 'Find why one advisor child never writes its sidecar', 'unclear_from_transcript',
     6, 40, 31),
]

THREADS = [
    ('mlx', 'Prefix-cache hit rate after a model swap', 'partially_achieved', 'open'),
    ('omp', 'Advisor seat re-reads the transcript every turn', 'not_achieved', 'open'),
    ('dream', 'Lately as a compact table', 'mostly_achieved', 'done'),
]


def session_path(day, index):
    return HOME + '/.claude/projects/-Users-dev/' + day + '-' + str(index) + '.jsonl'


def main(root):
    root = Path(root)
    install, dreams = root / 'install', root / 'dreams'
    dreams.mkdir(parents=True, exist_ok=True)
    rng = random.Random(7)
    today = date.today()
    hashes = {}
    by_day = {}
    for index, row in enumerate(SESSIONS):
        by_day.setdefault(row[0], []).append((index, row))
    for ago, rows in by_day.items():
        day = (today - timedelta(days=ago)).isoformat()
        directory = install / 'findings' / day
        directory.mkdir(parents=True, exist_ok=True)
        paths, cwds = [], []
        for position, (index, (_, repo, goal, outcome, messages, tools, minutes)) in enumerate(rows):
            path = session_path(day, index)
            digest = hashlib.sha1(path.encode()).hexdigest()[:12]
            hashes[(repo, goal)] = (day, digest, path)
            paths.append(path)
            cwds.append(digest + '\t' + REPOS[repo])
            (directory / (digest + '.json')).write_text(json.dumps(dict(
                project='-Users-dev-' + REPOS[repo].rsplit('/', 1)[1], session_path=path,
                underlying_goal=goal, notable_initiatives=[goal], outcome=outcome, findings=[])))
            (directory / (digest + '.stats.json')).write_text(json.dumps(dict(
                nested=False, isSidechain=False, user_message_count=messages,
                tool_call_count=tools, duration_minutes=minutes,
                transcript_mtime=1_800_000_000 - ago * 86_400 - position * 600)))
        (directory / 'sessions.txt').write_text('\n'.join(paths) + '\n')
        (directory / 'session-cwds.tsv').write_text('\n'.join(cwds) + '\n')
        (directory / 'run-stats.txt').write_text('\n'.join([
            'sessions_found_raw: ' + str(len(rows) + rng.randint(4, 12)),
            'sessions_triaged: ' + str(len(rows)),
            'sessions_top_level: ' + str(len(rows)),
            'sessions_nested: ' + str(rng.randint(2, 14)),
            'gated: ' + str(rng.randint(1, 6)),
            'l1_rounds_used: 1', 'l1_missing_after_retries: 0', 'l1_findings_with_error: 0',
            'l1_elapsed_seconds: ' + str(rng.randint(180, 640)),
            'l1_cost_usd_estimate: ' + format(rng.uniform(0.8, 3.5), '.2f'),
            'overlap_measured: yes', 'overlap_events: ' + str(rng.randint(0, 4)),
        ]) + '\n')
        (directory / 'categories.tsv').write_text(
            'category\tseverity\tsessions\tfindings\texample_hashes\n'
            'tool_loop\tall\t' + str(rng.randint(1, 3)) + '\t' + str(rng.randint(2, 5)) + '\t\n'
            'sandbox_friction\tall\t' + str(rng.randint(1, 4)) + '\t' + str(rng.randint(2, 6)) + '\t\n'
            'missed_skill\tall\t1\t1\t\n')
        (dreams / (day + '.md')).write_text(
            '# Autodream — ' + day + '\n\n## Top patterns\n\n### Retries that never changed the input\n'
            '- **Severity**: medium\n\n## Open questions\n\nAUTODREAM_QUESTIONS_BEGIN\n'
            '1. **Turn on chunked triage for long sessions?**\nAUTODREAM_QUESTIONS_END\n\n'
            '<!-- autodream:open-questions=' + ('2' if ago == 0 else '0') + ' -->\n')
    rows = []
    for number, (repo, title, outcome, status) in enumerate(THREADS):
        members = [value for (key_repo, _), value in hashes.items() if key_repo == repo][:2]
        row = dict(id='t-%08x' % (0xa11ce000 + number), kind='work', repo='~' + REPOS[repo][len(HOME):], title=title,
                   goal=title, status=status,
                   sessions=[dict(date=day, hash=digest, session_path=path, outcome=outcome)
                             for day, digest, path in members],
                   last_seen=max(day for day, _, _ in members))
        if status == 'done':
            row['done_by'] = 'linker'
        rows.append(json.dumps(row))
    (install / 'threads.jsonl').write_text('\n'.join(rows) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
