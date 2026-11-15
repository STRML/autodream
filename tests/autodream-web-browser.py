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

    def test_web_legacy_measurements_are_not_zero(self):
        self.run_browser('''renderLately({days:7,timeline:[{date:'2026-07-16',projects:[{
project:'-legacy',repo:'-legacy',sessions:[{hash:'0123456789ab',goal:null,outcome:null,
user_messages:null,tool_calls:0,duration_minutes:null}]}]}],threads:null,newest_dream:null});
const text = document.getElementById('content').textContent;
check(text.includes('not measured'), 'missing measurements must be labeled');
check(text.includes('0'), 'measured zero must survive');
''')


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BrowserTests))
    print(f'passed: {result.testsRun - len(result.failures) - len(result.errors)}   failed: {len(result.failures) + len(result.errors)}')
    sys.exit(not result.wasSuccessful())
