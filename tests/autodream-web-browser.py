#!/usr/bin/env python3
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import pwd
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

REPO = Path(__file__).resolve().parents[1]


class BrowserTests(unittest.TestCase):
    def run_browser(self, script):
        app = REPO / 'web/app.js'
        self.assertTrue(app.is_file(), 'safe DOM renderer has not been implemented')
        home = Path(pwd.getpwuid(os.getuid()).pw_dir)
        shells = sorted((home / 'Library/Caches/ms-playwright').glob(
            'chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell'))
        shells += sorted((home / '.cache/puppeteer/chrome-headless-shell').glob(
            '*/*/chrome-headless-shell'))
        chrome = os.environ.get('CHROME_BIN') or next((p for p in (
            shutil.which('chrome-headless-shell'), *map(str, shells),
            shutil.which('chromium'), shutil.which('chromium-browser'),
            shutil.which('google-chrome'),
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
            if p and Path(p).is_file()), None)
        self.assertIsNotNone(chrome, 'Chrome/Chromium is required for real DOM tests')
        with tempfile.TemporaryDirectory(prefix='browser.') as root:
            root = Path(root)
            (root / 'app.js').write_text(app.read_text())
            (root / 'index.html').write_text('''<!doctype html><html><head><meta charset="utf-8"></head><body>
<nav><a href="#lately">Lately</a><a href="#dreams">Dreams</a></nav>
<p id="status"></p><main id="content"></main>
<script>Object.defineProperty(Element.prototype, 'innerHTML', {
set() { throw new Error('innerHTML must not be used'); }, configurable: true
});</script>
<script src="app.js"></script><script src="checks.js"></script></body></html>''')
            (root / 'checks.js').write_text('''function check(value, message) {
if (!value) throw new Error(message);
}
try {
''' + script + '''
document.body.dataset.result = 'PASS';
} catch (error) { document.body.dataset.result = 'FAIL: ' + error.message; }
''')
            handler = partial(SimpleHTTPRequestHandler, directory=str(root))
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
check(content.textContent.includes('? 3 unmeasured'), 'unknown outcomes disappeared');
check(content.textContent.includes('? 1 unclear'), 'unclear outcomes must stay distinct');
check(content.textContent.includes('✓ 0'), 'measured zero must survive');
renderLately({days:7,timeline:[{date:'2026-11-14',projects:[{
repo:'repo',session_count:1,sessions:[]}]}],threads:null,newest_dream:null});
check(content.textContent.includes('✓ —'), 'absent outcome counts must stay unmeasured');
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
const rows = content.querySelectorAll('.project-row');
check(rows.length === 1, 'one project row must render for the day');
const row = rows[0];
check(row.querySelector('.project-outcomes').textContent.includes('4 sessions'), 'session count missing');
check(row.textContent.includes('✓ 2') && row.textContent.includes('◐ 1') &&
row.textContent.includes('✗ 0') && row.textContent.includes('? 1'), 'outcome totals missing');
check(row.querySelector('.project-goal').textContent.includes(''' + json.dumps(hostile) + '''),
  'latest goal should remain visible as text in the project row');
check(row.querySelectorAll('details').length === 1, 'sessions must sit under one details element');
const details = row.querySelector('details');
check(!details.open, 'session details should start collapsed');
check(details.textContent.includes('Second goal'), 'project sessions missing from details');
check(!content.querySelector('img'), 'hostile goal became markup');
check(content.textContent.includes('—'), 'missing per-session values need an em dash');
check(!content.textContent.includes('Some measurements are unavailable'), 'partial data must not add a banner');
check(!window.pwned, 'hostile text executed');
''')


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BrowserTests))
    print(f'passed: {result.testsRun - len(result.failures) - len(result.errors)}   failed: {len(result.failures) + len(result.errors)}')
    sys.exit(not result.wasSuccessful())
