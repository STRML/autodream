#!/usr/bin/env python3
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import pwd
import selectors
import socket
import urllib.request
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

REPO = Path(__file__).resolve().parents[1]


def find_chrome():
    home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    shells = sorted((home / 'Library/Caches/ms-playwright').glob(
        'chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell'))
    shells += sorted((home / '.cache/puppeteer/chrome-headless-shell').glob(
        '*/*/chrome-headless-shell'))
    configured = os.environ.get('CHROME_BIN')
    if configured:
        return configured if Path(configured).is_file() else None
    chrome = next((p for p in (
        shutil.which('chrome-headless-shell'), *map(str, shells),
        shutil.which('chromium'), shutil.which('chromium-browser'),
        shutil.which('google-chrome'),
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        if p and Path(p).is_file()), None)
    return chrome


class BrowserTests(unittest.TestCase):
    def run_browser(self, script, standalone=None, live_backend=False):
        app = REPO / 'web/app.js'
        self.assertTrue(app.is_file(), 'safe DOM renderer has not been implemented')
        chrome = find_chrome()
        if chrome is None:
            self.skipTest('no Chrome')
        with tempfile.TemporaryDirectory(prefix='browser.') as root:
            root = Path(root)
            (root / 'app.js').write_text(app.read_text())
            shared = REPO / 'web/threads.js'
            if shared.is_file():
                (root / 'threads.js').write_text(shared.read_text())
            (root / 'index.html').write_text('''<!doctype html><html><head><meta charset="utf-8"></head><body>
<nav><a href="#lately">Lately</a><a href="#dreams">Dreams</a></nav>
<p id="status"></p><main id="content"></main>
<script>Object.defineProperty(Element.prototype, 'innerHTML', {
set() { throw new Error('innerHTML must not be used'); }, configurable: true
});</script>
<script src="threads.js"></script><script src="app.js"></script><script src="checks.js"></script></body></html>''')
            if standalone is not None:
                (root / 'index.html').write_text(standalone.replace('</body>',
                    '<script src="checks.js"></script></body>'))
            (root / 'checks.js').write_text('''function check(value, message) {
if (!value) throw new Error(message);
}
(async function () { try {
''' + script + '''
document.body.dataset.result = 'PASS';
} catch (error) { document.body.dataset.result = 'FAIL: ' + error.message; }
})();
''')
            backend = None
            origin = None
            token = None
            def start_backend():
                nonlocal backend, origin, token
                install = root / 'backend'
                install.mkdir(exist_ok=True)
                lock = install / 'locks/run-2026-11-14.lock'
                lock.mkdir(parents=True, exist_ok=True)
                (lock / 'pid').write_text('-1')
                logs = install / 'logs'
                logs.mkdir(exist_ok=True)
                (logs / 'run-2026-11-14.log').write_text('<img src=x onerror="window.pwned=1">')
                backend = subprocess.Popen(['/bin/bash', str(REPO / 'bin/autodream-web'),
                    'serve', '--port', '0'], env=dict(os.environ, AUTODREAM_DIR=str(install),
                    AUTODREAM_CONFIG=str(install / 'no-config')), stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL, text=True)
                with selectors.DefaultSelector() as selector:
                    selector.register(backend.stdout, selectors.EVENT_READ)
                    if not selector.select(timeout=5):
                        raise RuntimeError('backend did not start')
                    origin = backend.stdout.readline().strip()
                token = (install / 'web-token').read_text().strip()
            def stop_backend():
                if backend is not None:
                    if backend.poll() is None:
                        backend.kill()
                    backend.wait(timeout=5)
                    backend.stdout.close()
            class Handler(SimpleHTTPRequestHandler):
                def do_GET(self):
                    if live_backend and self.path.startswith('/control/'):
                        if self.path == '/control/kill':
                            stop_backend()
                        elif self.path == '/control/restart':
                            start_backend()
                        self.send_response(200)
                        self.end_headers()
                        return
                    if live_backend and self.path == '/api/progress':
                        request = urllib.request.Request(origin + self.path,
                            headers={'Cookie': 'autodream_session=' + token})
                        try:
                            with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=3) as response:
                                data = response.read()
                        except OSError:
                            self.connection.shutdown(socket.SHUT_RDWR)
                            self.connection.close()
                            return
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(data)
                        return
                    super().do_GET()
            if live_backend:
                start_backend()
            handler = partial(Handler, directory=str(root))
            server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                result = subprocess.run([chrome, *(['--single-process'] if sys.platform == 'darwin' else []),
                    '--headless', '--disable-gpu',
                    '--no-first-run', '--no-default-browser-check',
                    '--user-data-dir=' + str(root / 'profile'), '--dump-dom',
                    '--virtual-time-budget=1500',
                    'http://127.0.0.1:' + str(server.server_port)],
                    capture_output=True, text=True, timeout=25)
                self.assertEqual(result.returncode, 0, result.stderr[-1000:])
                self.assertIn('data-result="PASS"', result.stdout, result.stdout)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)
                stop_backend()

    def test_web_open_handoff_signs_the_browser_in(self):
        chrome = find_chrome()
        if chrome is None:
            self.skipTest('no Chrome')
        with tempfile.TemporaryDirectory(prefix='handoff.') as root:
            root = Path(root)
            install = root / 'install'
            install.mkdir()
            env = dict(os.environ, AUTODREAM_DIR=str(install),
                       AUTODREAM_CONFIG=str(install / 'no-config'))
            backend = subprocess.Popen(['/bin/bash', str(REPO / 'bin/autodream-web'),
                'serve', '--port', '0'], env=env, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(backend.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=5), 'backend did not start')
                origin = backend.stdout.readline().strip()
                shim = root / 'shim'
                shim.mkdir()
                capture = root / 'opened'
                opener = shim / ('open' if sys.platform == 'darwin' else 'xdg-open')
                opener.write_text('#!/bin/sh\nprintf %s "$1" > ' + shlex.quote(str(capture)) + '\n')
                opener.chmod(0o755)
                opened = subprocess.run(['/bin/bash', str(REPO / 'bin/autodream-web'), 'open'],
                    env=dict(env, AUTODREAM_WEB_PORT=origin.rsplit(':', 1)[1],
                             PATH=str(shim) + os.pathsep + os.environ['PATH']),
                    capture_output=True, text=True, timeout=20)
                self.assertEqual(opened.returncode, 0, opened.stderr)
                handoff = capture.read_text()
                self.assertTrue(handoff.startswith('file://'), handoff)
                result = subprocess.run([chrome, *(['--single-process'] if sys.platform == 'darwin' else []),
                    '--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
                    '--user-data-dir=' + str(root / 'profile'), '--dump-dom',
                    '--virtual-time-budget=3000', handoff],
                    capture_output=True, text=True, timeout=25)
                self.assertEqual(result.returncode, 0, result.stderr[-1000:])
                self.assertNotIn('sign in', result.stdout, result.stdout[-1000:])
                self.assertIn('id="content"', result.stdout, result.stdout[-1000:])
            finally:
                if backend.poll() is None:
                    backend.kill()
                backend.wait(timeout=5)
                backend.stdout.close()

    def test_web_server_killed_shows_unreachable(self):
        self.run_browser('''await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once:true}));
const originalInterval = window.setInterval;
let poll;
window.setInterval = (callback, milliseconds) => {
  check(milliseconds === 5000, 'Progress must poll every five seconds');
  poll = callback;
  return 1;
};
window.clearInterval = () => { poll = undefined; };
let calls = 0;
const hostile = '<img src=x onerror="window.pwned=1">';
const realFetch = window.fetch;
window.fetch = (...args) => { calls++; return realFetch(...args); };
await fetch('/control/kill');
await loadView('progress');
check(document.getElementById('status').textContent === 'server not reachable', 'missing unreachable indicator');
check(poll, 'failed requests must still retry');
await fetch('/control/restart');
await poll();
check(document.getElementById('status').textContent === '', 'restart must reconnect');
const content = document.getElementById('content');
check(content.textContent.includes('stale'), 'stale ownership missing');
check(content.textContent.includes(hostile), 'last log line must be text');
check(!content.querySelector('img,script') && !window.pwned, 'log executed as markup');
check(!content.textContent.includes('phase'), 'phase must not be inferred');
const before = calls;
Object.defineProperty(document, 'hidden', {configurable:true,get:() => true});
await poll();
check(calls === before, 'hidden Progress must not poll');
window.setInterval = originalInterval;
''', live_backend=True)

    def test_web_stats_charts_keep_unmeasured_gaps(self):
        self.run_browser('''await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once:true}));
check(typeof renderStats === 'function', 'Stats charts are absent');
const nights = ['2026-11-10','2026-11-11','2026-11-12','2026-11-14'].map((date, i) => ({
  date,run:{l1_timed_out:i === 1 ? null : 0},sessions:{top_level:2,nested:3},
  activity:{user_messages:i === 1 ? null : i,tool_calls:2,duration_minutes:3},
  outcomes:{fully_achieved:i === 1 ? null : 1},finished_that_day:2,
  categories:i === 1 ? null : [{category:'<img src=x onerror="window.pwned=1">',severity:'all',sessions:2,findings:2},
    {category:'<img src=x onerror="window.pwned=1">',severity:'high',sessions:1,findings:1}]
}));
renderStats({nights});
const content = document.getElementById('content');
check(content.textContent.includes('Finished that day'), 'finished label missing');
check(content.textContent.includes('done threads whose last_seen is that day'), 'finished definition missing');
check(!content.textContent.includes('dropped_over_time'), 'invented historical status series');
check(content.querySelectorAll('svg').length > 0, 'inline SVG charts missing');
for (const svg of content.querySelectorAll('svg')) {
  check(svg.getAttribute('aria-label') && svg.getAttribute('role') === 'img', 'accessible chart label missing');
  check(svg.querySelector('title'), 'chart title missing');
}
const activity = Array.from(content.querySelectorAll('svg')).find(s => s.getAttribute('aria-label').includes('User messages'));
check(activity, 'activity chart missing');
check(activity.querySelectorAll('circle').length === 3, 'null must not plot as zero');
check(activity.querySelector('circle[data-value="0"]'), 'measured zero missing');
check(!activity.querySelector('path[d*="L"],polyline'), 'line crossed a null or absent night');
const category = Array.from(content.querySelectorAll('svg')).find(s => s.getAttribute('aria-label').includes('Category findings'));
check(category && Array.from(category.querySelectorAll('circle')).every(p => p.dataset.value === '2'),
  'category charts must use severity=all, without double counting');
check(!content.querySelector('img,script') && !window.pwned, 'category label became markup');
renderStats({nights:[]});
check(content.textContent.includes('No nightly statistics'), 'empty state missing');
''')

    def test_web_stats_collapses_nights_without_sidecars(self):
        self.run_browser('''await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once:true}));
const nights = ['2026-07-15','2026-07-16','2026-07-17','2026-07-25'].map((date, i) => ({
  date,run:{},sessions:{},activity:{},outcomes:{},categories:[],
  sessions_without_sidecar:i < 3 ? 40 : 0,degraded:i === 3 ? ['Could not read run-stats.txt.'] : []
}));
renderStats({nights});
const notices = Array.from(document.querySelectorAll('#content p.notice')).map(p => p.textContent);
check(notices.length === 2, 'expected one sidecar summary and one read failure, got ' + notices.length);
check(notices.some(n => n.includes('3 nights') && n.includes('2026-07-15') && n.includes('2026-07-17')),
  'sidecar summary missing: ' + notices.join(' | '));
check(notices.includes('2026-07-25: Could not read run-stats.txt.'), 'read failure must stay listed');
''')

    def test_web_hostile_markdown_and_goal_are_inert(self):
        hostile = '<img src=x onerror="window.pwned=1"><script>window.pwned=2</script>'
        markdown = '# Dream <repo> <repo_with_underscores>\n\n<!-- hidden-canary\ncomment -->\n\n' + hostile + '''

[bad](javascript:alert(1)) [encoded](javascript&#58;alert(1))
[local](file:///etc/passwd) [ok](https://example.invalid)

- **strong** and *emphasis*

> quote

```js
<repo> & text
```

| Key | Value |
| --- | --- |
| safe | <repo> |
'''
        self.run_browser('''const goal = ''' + json.dumps(hostile) + ''';
renderLately({days:7, timeline:[{date:'2026-11-14', projects:[{project:'<repo>',
repo:'<repo>', sessions:[{hash:'0123456789ab',goal,outcome:null,user_messages:null,
tool_calls:0,duration_minutes:null}]}]}], threads:{open:1,dropped:0,ideas:0},newest_dream:null});
const content = document.getElementById('content');
check(content.textContent.includes(goal), 'hostile goal must be literal text');
renderDream({date:'2026-11-14',markdown:''' + json.dumps(markdown) + ''',open_questions:2});
check(content.textContent.includes('<repo_with_underscores>'), 'HTML text must stay literal');
check(content.textContent.includes('<repo>'), 'HTML-shaped text must survive');
check(content.textContent.includes(goal), 'HTML must remain literal');
check(!content.textContent.includes('hidden-canary'), 'comments must be hidden');
check(!content.querySelector('script,img,iframe,svg'), 'injected element');
check(!window.pwned, 'script executed');
for (const element of content.querySelectorAll('*')) {
  for (const attribute of element.attributes) check(!/^on/i.test(attribute.name), 'event handler');
}
for (const a of content.querySelectorAll('a')) check(/^https?:$/.test(new URL(a.href).protocol), 'unsafe link');
check(content.querySelector('a[href="https://example.invalid/"]') ||
content.querySelector('a[href="https://example.invalid"]'), 'safe link missing');
for (const tag of ['h1','strong','em','ul','li','blockquote','pre','code','table','thead','tbody','tr','th','td'])
  check(content.querySelector(tag), 'missing allowed markdown ' + tag);
''')

    def test_web_degraded_summaries_and_dreams_display_every_warning(self):
        warnings = ['0123456789ab: nesting not measured',
                    '111111111111.json: project not measured',
                    'artifacts changed while reading; retry',
                    '<img src=x onerror="window.pwned=1">']
        self.run_browser('''const warnings = ''' + json.dumps(warnings) + ''';
renderLately({days:7,timeline:[{date:'2026-11-14',projects:[],
notices:['An existing notice'],degraded:warnings}],threads:null,newest_dream:null});
const content = document.getElementById('content');
for (const warning of [...warnings, 'An existing notice'])
  check(content.textContent.includes(warning), 'hidden warning: ' + warning);
check(!content.textContent.includes('No top-level sessions.'), 'dropped rows claimed complete');
check(!content.querySelector('img') && !window.pwned, 'warning became markup');
renderDream({date:'2026-11-14',markdown:'# Partial report',open_questions:null,
notices:['Dream notice'],degraded:['report changed while reading; retry',warnings[3]]});
for (const warning of ['report changed while reading; retry',warnings[3],'Dream notice'])
  check(content.textContent.includes(warning), 'hidden dream warning: ' + warning);
check(!content.querySelector('img') && !window.pwned, 'dream warning became markup');
''')

    def test_web_outcomes_distinguish_unmeasured_from_unclear_and_zero(self):
        self.run_browser('''renderLately({days:7,timeline:[{date:'2026-11-14',projects:[{
repo:'repo',session_count:4,outcomes:{fully_or_mostly:0,partially:0,not_achieved:0,
unclear:1,unmeasured:3},sessions:[]}]}],threads:null,newest_dream:null});
const content = document.getElementById('content');
const count = name => content.querySelector('[data-outcome="' + name + '"]')?.textContent;
check(count('unmeasured') === '○ 3', 'unknown outcomes disappeared');
check(count('unclear') === '? 1', 'unclear outcomes must stay distinct');
check(count('fully_or_mostly') === '✓ 0', 'measured zero must survive');
check(content.querySelector('.outcome-legend')?.textContent.includes('○ unmeasured'), 'glyph legend missing');
renderLately({days:7,timeline:[{date:'2026-11-14',projects:[{
repo:'repo',session_count:1,sessions:[]}]}],threads:null,newest_dream:null});
check(count('fully_or_mostly') === '✓ —', 'absent outcome counts must stay unmeasured');
check(!content.textContent.includes('✓ 0'), 'absent counts became zero');
''')

    def test_web_legacy_measurements_are_not_zero(self):
        self.run_browser('''renderLately({days:7,timeline:[{date:'2026-07-16',projects:[{
project:'-legacy',repo:'-legacy',sessions:[{hash:'0123456789ab',goal:null,outcome:null,
user_messages:null,tool_calls:0,duration_minutes:null}]}]}],threads:null,newest_dream:null});
const text = document.getElementById('content').textContent;
check(text.includes('—'), 'missing measurements must use an em dash');
check(text.includes('0'), 'measured zero must survive');
''')

    def test_web_lately_renders_project_rows_and_safe_session_details(self):
        hostile = '<img src=x onerror="window.pwned=1">'
        self.run_browser('''renderLately({days:7,timeline:[{date:'2026-11-14',notices:[],projects:[{
project:'~/git/cc-autodream',repo:'~/git/cc-autodream',session_count:4,
outcomes:{fully_or_mostly:2,partially:1,not_achieved:0,unclear:1},latest_goal:''' + json.dumps(hostile) + ''',
sessions:[{hash:'0123456789ab',goal:''' + json.dumps(hostile) + ''',outcome:'fully_achieved',
user_messages:null,tool_calls:0,duration_minutes:null},{hash:'111111111111',goal:'Second goal',
outcome:'unclear_from_transcript',user_messages:1,tool_calls:2,duration_minutes:3}]
}]}],threads:null,newest_dream:null});
const content = document.getElementById('content');
const table = content.querySelector('table.lately-table');
check(table, 'the night must render as a table');
check(Array.from(table.querySelectorAll('thead th')).map(th => th.textContent).join('|') ===
  'Repo|Sess|Time|Outcomes|Goal', 'table headers wrong');
const rows = content.querySelectorAll('tr.project-row');
check(rows.length === 1, 'one project row must render for the day');
const row = rows[0];
const repo = row.querySelector('.project-repo');
check(repo.textContent === 'cc-autodream' && repo.title === '~/git/cc-autodream', 'repo must show its short name');
check(row.querySelector('.project-sessions').firstChild.textContent === '4', 'session count missing');
check(row.querySelector('.project-sessions .cell-label').textContent === ' sessions', 'phone layout needs a visible label');
check(row.querySelector('.project-minutes').textContent === '—', 'a missing duration must not sum to a number');
check(row.textContent.includes('✓ 2') && row.textContent.includes('◐ 1') &&
row.textContent.includes('✗ 0') && row.textContent.includes('? 1'), 'outcome totals missing');
check(row.querySelector('.project-goal summary').textContent.includes(''' + json.dumps(hostile) + '''),
  'latest goal should remain visible as text in the project row');
check(row.querySelectorAll('details').length === 1, 'sessions must sit under one details element');
const details = row.querySelector('details');
check(!details.open, 'session details should start collapsed');
check(details.textContent.includes('Second goal'), 'project sessions missing from details');
check(!content.querySelector('img'), 'hostile goal became markup');
check(content.textContent.includes('—'), 'missing per-session values need an em dash');
check(!content.textContent.includes('Some measurements are unavailable'), 'partial data must not add a banner');
check(!window.pwned, 'hostile text executed');
renderLately({days:7,timeline:[{date:'2026-11-14',projects:[{repo:'/a/local-llm',session_count:2,
outcomes:{fully_or_mostly:2,partially:0,not_achieved:0,unclear:0,unmeasured:0},latest_goal:'Port',
sessions:[{hash:'a',goal:'Port',outcome:'fully_achieved',user_messages:3,tool_calls:9,duration_minutes:30},
{hash:'b',goal:null,outcome:'mostly_achieved',user_messages:1,tool_calls:2,duration_minutes:12.4}]}]}],
threads:null,newest_dream:null});
check(document.querySelector('.project-minutes').textContent === '42m', 'minutes must sum and round');
check(duration(2226) === '37h' && duration(90) === '1.5h' && duration(120) === '2h' && duration(null) === '—',
  'durations past an hour read in hours');
check(document.querySelector('.project-repo').textContent === 'local-llm', 'short repo name missing');
check(document.querySelector('.sessions li .metrics').textContent.startsWith('fully achieved'), 'outcome words must be visible');
check(Array.from(document.querySelectorAll('.sessions li .metrics')).map(m => m.textContent.split(' · ')[0]).join('|') ===
  'fully achieved|mostly achieved', 'fully and mostly must read differently');
check(shortRepoNames(['/a/frontend', '/b/frontend', '/c/api', '~']).join('|') === 'a/frontend|b/frontend|api|~',
  'colliding repo names must be lengthened until unique');
check(shortRepoNames(['/x/a/b', '/x/a/b']).join('|') === '/x/a/b|/x/a/b', 'identical paths fall back to the full path');
renderLately({days:7,timeline:[
  {date:'2026-11-15',projects:[{repo:'/a/frontend',session_count:1,sessions:[]}]},
  {date:'2026-11-14',projects:[{repo:'/b/frontend',session_count:1,sessions:[]}]}],threads:null,newest_dream:null});
check(Array.from(document.querySelectorAll('.project-repo')).map(c => c.textContent).join('|') === 'a/frontend|b/frontend',
  'repo names must be unique across nights, not only within one');
''')

    def test_web_thread_buttons_show_action_results(self):
        self.run_browser('''
const content = document.getElementById('content');
const hostile = '<img src=x onerror="window.pwned=1">';
let row = {id:'t-00000001',kind:'work',repo:'/repo',title:hostile,goal:hostile,
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[{date:'2026-11-01',hash:'a'}]};
let result = {ok:false,error:'busy',message:'busy, retry'};
let httpStatus = 409;
let pending;
let calls = [];
window.fetch = async function(path, options = {}) {
  calls.push({path, options});
  if (options.method === 'POST') {
    if (pending) await pending;
    return {ok:httpStatus === 200,status:httpStatus,json:async () => result};
  }
  return {ok:true,status:200,json:async () => ({threads:[row]})};
};
renderLately({days:7,timeline:[{date:'2026-11-01',projects:[{repo:'/repo',
  sessions:[{hash:'a',goal:'Goal'}]}]}],threads:null,newest_dream:null,thread_links:[row]});
const titleLink = content.querySelector('a[href="#threads/t-00000001"]');
check(titleLink && titleLink.textContent === hostile, 'Lately must link literal thread titles');
await loadView('threads', row.id);
check(content.querySelector('article').id === row.id, 'title deep link must select the thread');
check(content.textContent.includes(hostile), 'thread text missing');
check(content.querySelector('.meta').textContent.includes('1 session ·'), 'singular session label missing');
check(!content.querySelector('img,script'), 'thread text became markup');
let close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
check(close, 'Close action missing');
let release;
pending = new Promise(resolve => { release = resolve; });
let action = performThreadAction(row.id, 'close', close);
close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Working…');
check(close && close.disabled, 'button must be disabled during request');
release(); await action; pending = null;
close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
check(close && !close.disabled, 'busy button must be usable again');
check(content.textContent.includes('busy, retry'), 'failure missing beside action');
check(calls.filter(c => c.options.method === 'POST').every(c =>
  c.options.headers['X-Autodream'] === '1' && c.options.credentials === 'same-origin'), 'POST credential/header missing');
row = {...row,status:'closed_by_sam',display_status:'closed_by_sam'};
result = {ok:true,id:row.id,action:'close'}; httpStatus = 200;
await performThreadAction(row.id, 'close', close);
const done = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Done');
done.click();
check(content.querySelector('article').textContent.includes('closed_by_sam'), 'close must refetch state');
let reopen = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Reopen');
check(reopen, 'Reopen action missing');
row = {...row,status:'open',display_status:'open'};
result = {ok:true,id:row.id,action:'reopen'};
await performThreadAction(row.id, 'reopen', reopen);
Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Open').click();
check(content.querySelector('article').textContent.includes('open'), 'reopen must refetch state');
const resume = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Resume');
result = {ok:false,error:'cmux_unavailable',message:'cmux is unavailable',brief:'Resume brief <repo> & text'};
httpStatus = 503;
await performThreadAction(row.id, 'resume', resume);
check(content.querySelector('textarea').value === result.brief, 'copyable fallback brief missing');
check(!content.querySelector('img,script'), 'fallback became markup');
window.fetch = async function() { throw new TypeError('connection lost'); };
const retryResume = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Resume');
await performThreadAction(row.id, 'resume', retryResume);
check(content.textContent.includes('outcome is unknown'), 'timeout/network loss must require refresh');
check(content.textContent.includes('Refresh'), 'unknown outcome needs refresh guidance');
check(Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Refresh to check state')?.disabled,
  'unknown outcome must require refresh before another launch');
check(!window.pwned, 'hostile title executed');
''')

    def test_web_thread_action_state_survives_search_renders(self):
        self.run_browser('''
const content = document.getElementById('content');
let row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let response = {ok:false,error:'busy',message:'busy, retry'};
let httpStatus = 409;
let release;
let started;
let threadReads = 0;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    started();
    await new Promise(resolve => { release = resolve; });
    return {ok:httpStatus === 200,status:httpStatus,json:async () => response};
  }
  threadReads++;
  return {ok:true,status:200,json:async () => ({threads:[row]})};
};
await loadView('threads');
const search = content.querySelector('input[type=search]');
let ready = new Promise(resolve => { started = resolve; });
let close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
let action = performThreadAction(row.id, 'close', close);
await ready;
search.value = 'thread';
search.dispatchEvent(new Event('input'));
close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Working…');
check(close && close.disabled, 'a search render must preserve the in-flight action');
release();
await action;
close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
check(close && !close.disabled, 'ordinary failure must allow retry after rerender');
check(content.textContent.includes('busy, retry'), 'failure must survive a search render');

httpStatus = 200;
response = {ok:true,id:row.id,action:'close'};
row = {...row,status:'closed_by_sam',display_status:'closed_by_sam'};
ready = new Promise(resolve => { started = resolve; });
close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
action = performThreadAction(row.id, 'close', close);
await ready;
search.value = 'thread';
search.dispatchEvent(new Event('input'));
release();
await action;
check(threadReads === 2, 'successful action must refresh even after search replaces its button');
check(content.querySelector('.thread-counts').textContent.includes('Done (1)'),
  'successful action must render the refreshed status');
''')

    def test_web_thread_action_clears_pending_after_threads_reload(self):
        self.run_browser('''
const content = document.getElementById('content');
const row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let release;
let started;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    started();
    await new Promise(resolve => { release = resolve; });
    return {ok:false,status:409,json:async () => ({ok:false,error:'busy',message:'busy, retry'})};
  }
  return {ok:true,status:200,json:async () => ({threads:[row]})};
};
await loadView('threads');
const ready = new Promise(resolve => { started = resolve; });
const close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
const action = performThreadAction(row.id, 'close', close);
await ready;
await loadView('threads', row.id);
check(Array.from(content.querySelectorAll('button')).some(b => b.textContent === 'Working…'),
  'a reloaded threads view must show the pending action');
release();
await action;
const after = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
check(after && !after.disabled, 'pending state must clear on the reloaded view');
check(content.textContent.includes('busy, retry'), 'failure must show on the reloaded view');
''')

    def test_web_thread_action_refreshes_after_failed_threads_navigation(self):
        self.run_browser('''
const content = document.getElementById('content');
let row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let release;
let started;
let threadReads = 0;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    started();
    await new Promise(resolve => { release = resolve; });
    row = {...row,status:'closed_by_sam',display_status:'closed_by_sam'};
    return {ok:true,status:200,json:async () => ({ok:true,id:row.id,action:'close'})};
  }
  threadReads++;
  if (threadReads === 2) return {ok:false,status:500,json:async () => ({})};
  return {ok:true,status:200,json:async () => ({threads:[row]})};
};
await loadView('threads', row.id);
const ready = new Promise(resolve => { started = resolve; });
const close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
const action = performThreadAction(row.id, 'close', close);
await ready;
await loadView('threads');
release();
await action;
check(threadReads === 3, 'a successful action must refresh after a failed Threads navigation');
check(content.querySelector('.thread-counts').textContent.includes('Done (1)'),
  'the refreshed status must replace the stale card');
''')

    def test_web_thread_action_refresh_discarded_by_failed_navigation_stays_guarded(self):
        self.run_browser('''
const content = document.getElementById('content');
let row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let releaseRefresh;
let refreshStarted;
const refreshStart = new Promise(resolve => { refreshStarted = resolve; });
let threadReads = 0;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    row = {...row,status:'closed_by_sam',display_status:'closed_by_sam'};
    return {ok:true,status:200,json:async () => ({ok:true,id:row.id,action:'close'})};
  }
  threadReads++;
  if (threadReads === 2) {
    refreshStarted();
    await new Promise(resolve => { releaseRefresh = resolve; });
    return {ok:true,status:200,json:async () => ({threads:[row]})};
  }
  if (threadReads === 3) return {ok:false,status:500,json:async () => ({})};
  return {ok:true,status:200,json:async () => ({threads:[row]})};
};
await loadView('threads');
const close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
const action = performThreadAction(row.id, 'close', close);
await refreshStart;
await loadView('threads');
releaseRefresh();
await action;
check(content.textContent.includes('Action succeeded. Refresh'),
  'a discarded refresh must tell the user the card is stale');
check(!Array.from(content.querySelectorAll('.actions button')).some(b => !b.disabled),
  'a stale card must not offer another action');
await loadView('threads');
check(content.querySelector('.thread-counts').textContent.includes('Done (1)'),
  'a later Threads load must render the new status');
check(!content.textContent.includes('Action succeeded. Refresh'),
  'a later Threads load must clear the stale notice');
''')

    def test_web_thread_action_stays_guarded_after_failed_dreams_navigation(self):
        self.run_browser('''
const content = document.getElementById('content');
let row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let releaseRefresh;
let refreshStarted;
const refreshStart = new Promise(resolve => { refreshStarted = resolve; });
let threadReads = 0;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    row = {...row,status:'closed_by_sam',display_status:'closed_by_sam'};
    return {ok:true,status:200,json:async () => ({ok:true,id:row.id,action:'close'})};
  }
  if (path === '/api/dreams') return {ok:false,status:500,json:async () => ({})};
  threadReads++;
  if (threadReads === 2) {
    refreshStarted();
    await new Promise(resolve => { releaseRefresh = resolve; });
  }
  return {ok:true,status:200,json:async () => ({threads:[row]})};
};
await loadView('threads');
const close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
const action = performThreadAction(row.id, 'close', close);
await refreshStart;
await loadView('dreams');
releaseRefresh();
await action;
check(content.querySelector('.thread-view'), 'the failed Dreams load must leave the old cards visible');
check(!Array.from(content.querySelectorAll('.actions button')).some(b => !b.disabled),
  'a stale card left by a failed navigation must stay guarded');
''')

    def test_web_thread_action_clears_when_newer_load_renders_first(self):
        self.run_browser('''
const content = document.getElementById('content');
let row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let releaseRefresh;
let refreshStarted;
const refreshStart = new Promise(resolve => { refreshStarted = resolve; });
let threadReads = 0;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    row = {...row,status:'closed_by_sam',display_status:'closed_by_sam'};
    return {ok:true,status:200,json:async () => ({ok:true,id:row.id,action:'close'})};
  }
  threadReads++;
  const snapshot = {threads:[row]};
  if (threadReads === 2) {
    refreshStarted();
    await new Promise(resolve => { releaseRefresh = resolve; });
  }
  return {ok:true,status:200,json:async () => snapshot};
};
await loadView('threads');
const close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
const action = performThreadAction(row.id, 'close', close);
await refreshStart;
await loadView('threads');
releaseRefresh();
await action;
check(content.querySelector('.thread-counts').textContent.includes('Done (1)'), 'the newer load must render');
check(!content.textContent.includes('Action succeeded. Refresh'), 'a newer load must clear the guard');
Array.from(content.querySelectorAll('nav button')).find(b => b.textContent === 'Done').click();
const reopen = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Reopen');
check(reopen && !reopen.disabled, 'a fresh card must not stay guarded');
''')

    def test_web_thread_action_does_not_replace_newer_navigation(self):
        self.run_browser('''await new Promise(resolve => window.addEventListener('load', resolve, {once:true}));
const content = document.getElementById('content');
const row = {id:'t-00000001',kind:'work',repo:'/repo',title:'Thread',goal:'Goal',
  status:'dropped',display_status:'dropped',last_seen:'2026-11-01',sessions:[]};
let releasePost;
let postStarted;
let releaseDreams;
let refreshResolve;
let refreshStarted;
const refreshStart = new Promise(resolve => { refreshStarted = resolve; });
let threadReads = 0;
window.fetch = async function(path, options = {}) {
  if (options.method === 'POST') {
    postStarted();
    await new Promise(resolve => { releasePost = resolve; });
    return {ok:true,status:200,json:async () => ({ok:true,id:row.id,action:'close'})};
  }
  if (path === '/api/threads') {
    threadReads++;
    if (threadReads > 1) return new Promise(resolve => { refreshResolve = resolve; refreshStarted(); });
    return {ok:true,status:200,json:async () => ({threads:[row]})};
  }
  if (path === '/api/dreams')
    return new Promise(resolve => { releaseDreams = () => resolve({ok:true,status:200,json:async () => ({dates:[]})}); });
  throw new Error('unexpected fetch ' + path);
};
history.replaceState(null, '', '#threads');
await loadView('threads');
let started = new Promise(resolve => { postStarted = resolve; });
const close = Array.from(content.querySelectorAll('button')).find(b => b.textContent === 'Close');
const action = performThreadAction(row.id, 'close', close);
await started;
history.replaceState(null, '', '#dreams');
const dreams = loadView('dreams');
releasePost();
const actionStartedRefresh = await Promise.race([
  refreshStart.then(() => true), action.then(() => false)
]);
releaseDreams();
await dreams;
if (actionStartedRefresh) refreshResolve({ok:true,status:200,json:async () => ({threads:[row]})});
await action;
check(threadReads === 1, 'an action from the old view must not start a thread refresh');
check(content.querySelector('h1')?.textContent === 'Dreams', 'action refresh replaced the selected Dreams view');
check(location.hash === '#dreams', 'the URL must remain on the selected Dreams view');
check(document.querySelector('nav a[aria-current="page"]')?.hash === '#dreams',
  'navigation selection must stay on Dreams');
''')

    def test_web_lately_renders_when_optional_threads_fetch_rejects(self):
        self.run_browser('''await new Promise(resolve => window.addEventListener('load', resolve, {once:true}));
const lately = {days:7,timeline:[{date:'2026-11-14',projects:[{project:'/repo',repo:'/repo',
  sessions:[{hash:'a',goal:'Primary Lately data',outcome:'not_achieved',user_messages:1,
    tool_calls:2,duration_minutes:3}]}]}],threads:null,newest_dream:null};
window.fetch = async function(path) {
  if (path === '/api/lately?days=7') return {ok:true,status:200,json:async () => lately};
  if (path === '/api/threads') throw new TypeError('connection interrupted');
  throw new Error('unexpected fetch ' + path);
};
await loadView('lately');
const content = document.getElementById('content');
check(content.textContent.includes('Primary Lately data'), 'the primary Lately view must render');
check(document.getElementById('status').textContent === '', 'optional thread failure must not show a connection error');
''')

    def test_web_shared_threads_renderer_keeps_standalone_controls(self):
        with tempfile.TemporaryDirectory(prefix='standalone.') as directory:
            root = Path(directory)
            state = root / 'threads.jsonl'
            page = root / 'threads.html'
            rows = [
                dict(id='t-00000001', kind='work', repo='/repo/alpha', title='Alpha <repo>',
                     goal='Ship alpha __THREADS_JS__ __THREADS_CSS__ __THREADS_JSON__', status='open', last_seen='2020-01-01',
                     sessions=[dict(date='2020-01-01', hash='a', outcome='not_achieved')]),
                dict(id='t-00000002', kind='idea', repo='/repo/beta', title='Beta idea',
                     goal='Explore beta', status='open', last_seen='2026-11-15', sessions=[]),
                dict(id='t-00000003', kind='work', repo='/repo/alpha', title='Closed alpha',
                     goal='Done', status='closed_by_sam', last_seen='2026-11-15', sessions=[])]
            state.write_text(''.join(json.dumps(row) + '\n' for row in rows))
            result = subprocess.run([sys.executable, str(REPO / 'bin/threads-render.py'),
                str(state), str(page), '--as-of', '2026-11-15'],
                capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.run_browser('''const root = document.getElementById('thread-root');
check(root.querySelectorAll('article').length === 1, 'Dropped default missing');
check(root.querySelector('h2').textContent === 'Alpha <repo>', 'literal title missing');
check(root.textContent.includes('__THREADS_JS__ __THREADS_CSS__ __THREADS_JSON__'), 'data must not expand template markers');
check(!root.querySelector('repo,img,script'), 'title became HTML');
check(root.querySelector('.thread-counts').textContent.includes('Ideas (1)'), 'counts missing');
const search = root.querySelector('input');
search.value = 'absent'; search.dispatchEvent(new Event('input'));
check(!root.querySelector('article'), 'search must filter');
search.value = ''; search.dispatchEvent(new Event('input'));
const repo = root.querySelector('select');
repo.value = '/repo/beta'; repo.dispatchEvent(new Event('change'));
check(!root.querySelector('article'), 'repo must filter');
repo.value = ''; repo.dispatchEvent(new Event('change'));
Array.from(root.querySelectorAll('nav button')).find(b => b.textContent === 'Done').click();
check(root.querySelector('h2').textContent === 'Closed alpha', 'Done filter missing');
let copied;
Object.defineProperty(navigator, 'clipboard', {value:{writeText:async text => { copied = text; }}});
Array.from(root.querySelectorAll('button')).find(b => b.textContent === 'Copy reopen command').click();
await Promise.resolve();
check(copied === 'threads.sh reopen t-00000003', 'static callback must copy CLI command');
check(root.textContent.includes('Copied'), 'copy result missing');
''', standalone=page.read_text())


if __name__ == '__main__':
    if os.environ.get('CI') or find_chrome() is None:
        print('SKIP: CI browser checks are local only' if os.environ.get('CI') else 'SKIP: no Chrome')
        print('passed: 0   failed: 0')
        sys.exit(0)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BrowserTests))
    print(f'passed: {result.testsRun - len(result.failures) - len(result.errors)}   failed: {len(result.failures) + len(result.errors)}')
    sys.exit(not result.wasSuccessful())
