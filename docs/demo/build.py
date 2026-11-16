#!/usr/bin/env python3
"""Build the static dashboard demo for GitHub Pages.

Usage: build.py <out-dir>

Writes the synthetic install from docs/screenshots/fixture.py, answers every dashboard API
route with the real data layer (bin/autodream_web_data.py), and saves each answer as JSON.
The page is web/index.html with web/*.js and web/*.css unchanged, plus demo-fetch.js, which
serves those files in place of the local server. Thread actions answer with a demo notice.
Every date is relative to the build day, so the Pages workflow rebuilds daily.
"""
from datetime import date
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
HOME = '/Users/dev'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, allow_nan=False))


def build(out):
    out = Path(out)
    if out.exists():
        sys.exit(f'{out} exists; pass a new directory')
    fixture = load('fixture', REPO / 'docs/screenshots/fixture.py')
    web_data = load('autodream_web_data', REPO / 'bin/autodream_web_data.py')
    with tempfile.TemporaryDirectory(prefix='autodream-demo.') as scratch:
        fixture.main(scratch)
        install, dreams = Path(scratch) / 'install', Path(scratch) / 'dreams'
        os.environ.update(HOME=HOME, AUTODREAM_DIR=str(install),
                          AUTODREAM_CONFIG=str(install / 'no-config'))
        cache = web_data.NightCache(install, dreams)
        api = out / 'api'
        threads = cache.threads()
        if threads is None:
            sys.exit('threads.sh list failed; is jq installed?')
        write_json(api / 'lately.json', cache.lately(7))
        write_json(api / 'stats.json', cache.stats())
        write_json(api / 'progress.json', cache.progress(time.time()))
        write_json(api / 'threads.json', dict(as_of=date.today().isoformat(),
                                               threads=[dict(row, display_status=row['status'])
                                                        for row in threads]))
        dates = cache.dream_dates()
        write_json(api / 'dreams.json', dates)
        for day in dates['dates']:
            write_json(api / 'dreams' / (day + '.json'), cache.read_dream(day))
    (out / 'web').mkdir()
    for name in ('app.js', 'app.css', 'threads.js', 'threads.css'):
        shutil.copy(REPO / 'web' / name, out / 'web' / name)
    shutil.copy(Path(__file__).with_name('demo-fetch.js'), out / 'web' / 'demo-fetch.js')
    page = (REPO / 'web/index.html').read_text()
    page = page.replace('href="/web/', 'href="web/').replace('src="/web/', 'src="web/')
    page = page.replace('<script src="web/threads.js"',
                        '<script src="web/demo-fetch.js"></script>\n  <script src="web/threads.js"', 1)
    page = page.replace('<body>', '<body>\n  <p class="demo-banner">Demo with made-up data. '
                        'autodream runs on your own Mac; see '
                        '<a href="https://github.com/STRML/autodream">github.com/STRML/autodream</a>.</p>', 1)
    page = page.replace('</head>', '  <style>.demo-banner { max-width: none; margin: 0 -5vw; '
                        'padding: .55rem 5vw; text-align: center; font-size: .85rem; color: var(--muted); '
                        'border-bottom: 1px solid var(--rule); }</style>\n</head>', 1)
    (out / 'index.html').write_text(page)
    (out / '.nojekyll').write_text('')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(sys.argv[1])
