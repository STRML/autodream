#!/usr/bin/env python3
from datetime import date, timedelta
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]


class DataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='data.')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.day = self.root / 'findings/2026-11-14'
        self.day.mkdir(parents=True)
        self.dreams = self.root / 'dreams'
        self.dreams.mkdir()
        path = REPO / 'bin/autodream_web_data.py'
        self.assertTrue(path.is_file(), 'artifact summaries have not been implemented')
        spec = importlib.util.spec_from_file_location('autodream_web_data', path)
        self.data = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.data)
        self.cache = self.data.NightCache(self.root, self.dreams)

    def finding(self, hash='0123456789ab', *, day=None, project='-repo', stats=None, **values):
        day = day or self.day
        day.mkdir(parents=True, exist_ok=True)
        record = dict(project=project, underlying_goal='Ship a feature',
                      notable_initiatives=['Fallback goal'], outcome='partially_achieved', findings=[])
        record.update(values)
        (day / (hash + '.json')).write_text(json.dumps(record))
        if stats is not False:
            sidecar = dict(nested=False, user_message_count=4, tool_call_count=3, duration_minutes=8)
            sidecar.update(stats or {})
            (day / (hash + '.stats.json')).write_text(json.dumps(sidecar))

    def sessions(self, summary):
        return [s for p in summary['projects'] for s in p['sessions']]

    def git(self, *args):
        return subprocess.run(['git', *map(str, args)], check=True, capture_output=True,
                              text=True, timeout=10).stdout.strip()

    def stats_night(self, date='2026-11-14'):
        self.assertTrue(callable(getattr(self.cache, 'stats', None)), 'nightly statistics are absent')
        return next(night for night in self.cache.stats()['nights'] if night['date'] == date)

    def test_web_stats_reads_unavailable_threads_once(self):
        for day in range(10, 15):
            (self.root / 'findings' / ('2026-11-' + str(day))).mkdir(exist_ok=True)
        with patch.object(self.cache, 'threads', return_value=None) as read:
            result = self.cache.stats()
        self.assertEqual(read.call_count, 1, 'failed thread lookups must not repeat per night')
        self.assertEqual(len(result['nights']), 5)
        self.assertTrue(all(night['finished_that_day'] is None for night in result['nights']))

    def test_web_stats_preserves_missing_measurements(self):
        self.finding(stats={'tool_call_count': 0, 'user_message_count': None})
        (self.day / 'run-stats.txt').write_text('l1_timed_out: 0\nl1_elapsed_seconds: unknown\n')
        night = self.stats_night()
        self.assertIsNone(night['run'].get('sessions_triaged'))
        self.assertIsNone(night['run'].get('l1_elapsed_seconds'))
        self.assertEqual(night['run']['l1_timed_out'], 0)
        self.assertEqual(night['activity']['tool_calls'], 0)
        self.assertIsNone(night['activity']['user_messages'])
        self.assertIsNone(night['categories'])
        (self.day / 'categories.tsv').write_text('category\tseverity\tsessions\tfindings\texample_hashes\nx\tall\tbad\t1\tx\n')
        self.assertIsNone(self.stats_night()['categories'])
        self.finding('111111111111', stats=False)
        night = self.stats_night()
        self.assertTrue(all(value is None for value in night['activity'].values()),
                        'a missing sidecar must not silently reduce activity')
        self.assertTrue(all(value is None for value in night['outcomes'].values()))
        self.finding('111111111111', stats={'nested': True, 'tool_call_count': 900})
        self.assertEqual(self.stats_night()['activity']['tool_calls'], 0, 'workers must not inflate activity')
        old = self.root / 'findings/2026-07-16'
        self.finding(day=old)
        self.assertTrue(all(value is None for value in self.stats_night('2026-07-16')['outcomes'].values()))
        self.finding('222222222222', outcome='unknown')
        self.assertTrue(all(value is None for value in self.stats_night()['outcomes'].values()))

    def worklist(self, *paths):
        import hashlib
        (self.day / 'sessions.txt').write_text(''.join(path + '\n' for path in paths))
        return [hashlib.sha1(path.encode()).hexdigest()[:12] for path in paths]

    def test_web_stats_ignore_sidecars_outside_the_worklist(self):
        done, = self.worklist('/sessions/done.jsonl')
        self.finding(done)
        stale = dict(nested=False, user_message_count=9, tool_call_count=9, duration_minutes=9)
        (self.day / '111111111111.stats.json').write_text(json.dumps(stale))
        night = self.stats_night()
        self.assertEqual(night['activity'], dict(user_messages=4, tool_calls=3, duration_minutes=8),
                         'a sidecar left by an earlier run must not erase a completed night')

    def test_web_stats_pending_nested_worker_leaves_totals_measured(self):
        top, worker = self.worklist('/sessions/top.jsonl', '/sessions/top/subagents/agent-1.jsonl')
        self.finding(top)
        (self.day / (worker + '.stats.json')).write_text(json.dumps(dict(nested=True, isSidechain=True)))
        night = self.stats_night()
        self.assertEqual(night['activity']['tool_calls'], 3)
        self.assertEqual(night['outcomes']['partially_achieved'], 1)

    def test_web_stats_pending_top_level_session_is_unmeasured(self):
        done, pending = self.worklist('/sessions/done.jsonl', '/sessions/pending.jsonl')
        self.finding(done)
        (self.day / (pending + '.stats.json')).write_text(json.dumps(dict(nested=False)))
        night = self.stats_night()
        self.assertTrue(all(value is None for value in night['activity'].values()))
        self.assertTrue(all(value is None for value in night['outcomes'].values()))

    def test_web_stats_missing_sidecar_is_unmeasured_not_unreadable(self):
        old, = self.worklist('/sessions/old.jsonl')
        self.finding(old, stats=False)
        night = self.stats_night()
        self.assertEqual(night['degraded'], [], 'a night from before sidecars existed is not a read failure')
        self.assertEqual(night['sessions_without_sidecar'], 1)
        self.worklist('/sessions/old.jsonl', '/sessions/pending.jsonl')
        night = self.stats_night()
        self.assertEqual(night['sessions_without_sidecar'], 2,
                         'a pending session with no sidecar is unmeasured for the same reason')
        self.assertEqual(night['degraded'], [])
        _, gated = self.worklist('/sessions/old.jsonl', '/sessions/gated.jsonl')
        self.finding(gated, stats=False, skipped='below_noise_gate')
        self.assertEqual(self.stats_night()['sessions_without_sidecar'], 1,
                         'a gated session is left out of Stats, so its sidecar is not missed')
        (self.day / (gated + '.json')).unlink()
        self.worklist('/sessions/old.jsonl')
        night = self.stats_night()
        self.assertTrue(all(value is None for value in night['activity'].values()))
        self.assertTrue(all(value is None for value in night['outcomes'].values()))
        key = ('2026-11-14', 'stats')
        self.assertIn(key, self.cache._nights, 'an unmeasured night must still be cached')

    def test_web_stats_unreadable_file_is_degraded_and_not_cached(self):
        self.finding()
        run_stats = self.day / 'run-stats.txt'
        run_stats.write_text('l1_timed_out: 2\n')
        run_stats.chmod(0)
        try:
            if os.access(run_stats, os.R_OK):
                self.skipTest('running as a user that ignores file modes')
            night = self.stats_night()
            self.assertIsNone(night['run']['l1_timed_out'])
            self.assertIn('Could not read run-stats.txt.', night['degraded'])
        finally:
            run_stats.chmod(0o644)
        night = self.stats_night()
        self.assertEqual(night['run']['l1_timed_out'], 2, 'a failed read must not be cached')
        self.assertEqual(night['degraded'], [])

    def test_web_stats_categories_do_not_double_count(self):
        categories = self.day / 'categories.tsv'
        categories.write_text('category\tseverity\tsessions\tfindings\texample_hashes\n'
            'buggy_code_shipped\tall\t2\t3\ta,b\n'
            'buggy_code_shipped\thigh\t1\t1\ta\n'
            'buggy_code_shipped\tmedium\t2\t2\ta,b\n')
        night = self.stats_night()
        rows = night['categories']
        self.assertEqual(next(row['sessions'] for row in rows if row['severity'] == 'all'), 2)
        self.assertEqual(next(row['sessions'] for row in rows if row['severity'] == 'high'), 1)
        self.assertEqual(sum(row['sessions'] for row in rows if row['severity'] == 'all'), 2)
        categories.write_text(categories.read_text().replace('all\t2\t3', 'all\t4\t5'))
        self.assertEqual(next(row['sessions'] for row in self.stats_night()['categories']
                              if row['severity'] == 'all'), 4, 'in-place changes must invalidate the cache')
        categories.unlink()
        self.assertIsNone(self.stats_night()['categories'])

    def test_web_finished_that_day_uses_last_seen(self):
        rows = [dict(id='t-' + str(i).zfill(8), kind='work', repo='/repo', goal='Goal',
                     title='Title', status=status, last_seen=day, sessions=[])
                for i, (status, day) in enumerate((('done', '2026-11-14'),
                    ('done', '2026-11-14'), ('done', '2026-11-13'),
                    ('closed_by_sam', '2026-11-14'), ('open', '2026-11-14')), 1)]
        state = self.root / 'threads.jsonl'
        state.write_text(''.join(json.dumps(row) + '\n' for row in rows))
        night = self.stats_night()
        self.assertEqual(night['finished_that_day'], 2)
        self.assertNotIn('dropped_over_time', night)
        rows[0]['status'] = 'open'
        state.write_text(''.join(json.dumps(row) + '\n' for row in rows))
        self.assertEqual(self.stats_night()['finished_that_day'], 1, 'thread changes must invalidate stats')
        state.write_text('{broken')
        self.assertIsNone(self.stats_night()['finished_that_day'])

    def test_web_lately_excludes_nested_and_folds_repos(self):
        common = Path(self.git('-C', REPO, 'rev-parse', '--git-common-dir')).resolve()
        main = common.parent
        worktree = REPO
        temporary = REPO / 'tests'
        (self.day / 'pin-projects.tsv').write_text('-repo\t' + str(worktree) + '\n')
        self.finding(underlying_goal=None)
        self.finding('111111111111', stats={'nested': True})
        self.finding('222222222222', stats={'isSidechain': True})
        self.finding('333333333333', stats=False)
        result = self.cache.summary('2026-11-14')
        self.assertEqual([s['hash'] for s in self.sessions(result)], ['0123456789ab'])
        self.assertEqual(result['projects'][0]['repo'], str(main.resolve()))
        self.assertEqual(self.sessions(result)[0]['goal'], 'Fallback goal')
        self.assertEqual(self.data.repo_for_project('-tmp', temporary, []), str(main.resolve()))
        self.assertEqual(self.data.repo_for_project('-Users-made-up', '', []), '/Users/made/up')
        self.assertEqual(self.data.repo_for_project('-gone', '', [{'repo': '/historical/repo'}]),
                         '/historical/repo')
        self.assertTrue(result['degraded'])
        self.finding('444444444444', project='-temporary')
        with (self.day / 'pin-projects.tsv').open('a') as stream:
            stream.write('-temporary\t' + str(temporary) + '\n')
        folded = self.cache.summary('2026-11-14')
        self.assertEqual(len(folded['projects']), 1, 'buckets for one repo must fold together')
        self.assertEqual(len(self.sessions(folded)), 2)
        historical = self.root / 'findings/2026-11-13'
        self.finding('aaaaaaaaaaaa', day=historical, project='-private-tmp')
        self.finding('bbbbbbbbbbbb', day=historical, project='-private-tmp')
        summary = self.data.build_night_summary('2026-11-13', {
            'findings_dir': historical, 'thread_references': {
                ('2026-11-13', 'aaaaaaaaaaaa'): [{'repo': '/repo/one'}],
                ('2026-11-13', 'bbbbbbbbbbbb'): [{'repo': '/repo/two'}]}})
        self.assertEqual({p['repo'] for p in summary['projects']}, {'/repo/one', '/repo/two'},
                         'session references must resolve shared temporary buckets independently')

    def test_web_projects_use_runner_cwds_and_decode_fallback_labels(self):
        common = Path(self.git('-C', REPO, 'rev-parse', '--git-common-dir')).resolve()
        main = common.parent
        worktree = REPO
        (self.day / 'pin-projects.tsv').write_text(
            '-Users-fixture-git-cc-autodream\t\n'
            '-home-fixture-projects-cc-autodream\t\n')
        self.finding(project='-Users-fixture-git-cc-autodream', transcript_mtime=10)
        self.finding('111111111111', project='-home-fixture-projects-cc-autodream',
                     underlying_goal='Most recent goal', transcript_mtime=20,
                     outcome='mostly_achieved')
        home = Path('/Users/fixture')
        home_bucket = '-Users-fixture'
        self.finding('222222222222', project=home_bucket, outcome='unclear_from_transcript')
        temp_bucket = '-private-tmp-adw22p'
        scratch_bucket = '-Users-fixture-scratchpad'
        with (self.day / 'pin-projects.tsv').open('a') as stream:
            stream.write(temp_bucket + '\t/tmp/adw22p\n')
            stream.write(scratch_bucket + '\t' + str(home / 'scratchpad') + '\n')
        self.finding('333333333333', project=temp_bucket)
        self.finding('444444444444', project=scratch_bucket)
        (self.day / 'session-cwds.tsv').write_text(
            '0123456789ab\t' + str(worktree) + '\n'
            '111111111111\t' + str(worktree) + '\n'
            '222222222222\t?\n'
            '333333333333\t/tmp/adw22p\n'
            '444444444444\t' + str(home / 'scratchpad') + '\n')
        with patch.dict(os.environ, {'HOME': str(home)}):
            summary = self.data.build_night_summary('2026-11-14', {
                'findings_dir': self.day, 'thread_references': {}})
        self.assertEqual({project['repo'] for project in summary['projects']},
                         {str(main.resolve()), '~'}, summary)
        repo = next(project for project in summary['projects']
                    if project['repo'] == str(main.resolve()))
        self.assertEqual(len(repo['sessions']), 2,
                         'Claude and OMP buckets for one cwd must fold into the same repo')
        self.assertEqual(repo['session_count'], 2)
        self.assertEqual(repo['outcomes'], {
            'fully_or_mostly': 1, 'partially': 1, 'not_achieved': 0, 'unclear': 0, 'unmeasured': 0})
        self.assertEqual(repo['latest_goal'], 'Most recent goal')
        fallback = next(project for project in summary['projects'] if project['repo'] == '~')
        self.assertEqual(fallback['sessions'][0]['outcome'], 'unclear_from_transcript')
        self.assertEqual(len(self.sessions(summary)), 3,
                         'temporary and scratchpad sessions must stay out of Lately')

    def test_web_lately_drops_gated_sessions_and_reads_every_goal_shape(self):
        self.finding('0123456789ab', underlying_goal=None, notable_initiatives='Initiative as a string',
                     stats={'transcript_mtime': 100})
        self.finding('111111111111', underlying_goal=None, notable_initiatives=None,
                     outcome='unclear_from_transcript', stats={'transcript_mtime': 300})
        self.finding('222222222222', skipped='below_noise_gate', underlying_goal=None,
                     notable_initiatives=None, outcome=None, stats={'transcript_mtime': 200})
        summary = self.cache.summary('2026-11-14')
        sessions = {s['hash']: s for s in self.sessions(summary)}
        self.assertNotIn('222222222222', sessions, 'a noise-gated session is left out, as in Stats')
        self.assertEqual(sessions['0123456789ab']['goal'], 'Initiative as a string')
        self.assertEqual(summary['projects'][0]['latest_goal'], 'Initiative as a string',
                         'the newest session with a goal names the project')
        self.assertEqual(summary['degraded'], [],
                         'a missing goal is not a missing measurement')

    def test_web_unmeasured_outcomes_are_counted_separately(self):
        for i, outcome in enumerate([None, 'invalid', [], 'fully_achieved', 'mostly_achieved',
                                     'partially_achieved', 'not_achieved', 'unclear_from_transcript']):
            self.finding(f'{i:012x}', outcome=outcome)
        summary = self.data.build_night_summary('2026-11-14', {'findings_dir': self.day})
        project = summary['projects'][0]
        self.assertEqual(project['session_count'], 8)
        self.assertEqual(project['outcomes'], {'fully_or_mostly': 2, 'partially': 1,
                         'not_achieved': 1, 'unclear': 1, 'unmeasured': 3})
        self.assertEqual(sum(project['outcomes'].values()), project['session_count'])

    def test_web_missing_session_values_do_not_create_night_notices(self):
        self.finding(underlying_goal=None, notable_initiatives=[], outcome='unknown',
                     stats={'tool_call_count': None})
        summary = self.cache.summary('2026-11-14')
        session = self.sessions(summary)[0]
        self.assertEqual(session['goal'], None)
        self.assertIsNone(session['outcome'])
        self.assertIsNone(session['tool_calls'])
        self.assertEqual(summary['notices'], [])

    def test_web_legacy_night_and_unreadable_file_notices_name_the_cause(self):
        old = self.root / 'findings/2026-07-16'
        self.finding(day=old)
        legacy = self.data.build_night_summary('2026-07-16', {'findings_dir': old})
        self.assertEqual(legacy['notices'], [
            'Outcomes were not measured before 2026-07-17.',
            'Goals were not measured before 2026-07-20.'])
        (self.day / '111111111111.json').write_text('{broken')
        broken = self.cache.summary('2026-11-14')
        self.assertTrue(any('111111111111.json' in notice for notice in broken['notices']))

    def test_web_legacy_measurements_are_not_zero(self):
        for date, goal, outcome in [('2026-07-16', None, None),
                                    ('2026-07-19', None, 'partially_achieved'),
                                    ('2026-11-14', None, 'partially_achieved')]:
            day = self.root / 'findings' / date
            self.finding(day=day, underlying_goal=None, notable_initiatives=[],
                         stats={'tool_call_count': None})
            session = self.sessions(self.cache.summary(date))[0]
            self.assertIs(session['goal'], goal)
            self.assertEqual(session['outcome'], outcome)
            self.assertIsNone(session['tool_calls'])
            self.assertEqual(session['user_messages'], 4)

    def test_web_cache_rebuilds_after_artifact_changes(self):
        self.finding()
        self.cache.summary('2026-11-14')
        stats = self.day / '0123456789ab.stats.json'
        with stats.open('a') as stream:
            stream.write(' ' * 10)
        self.finding(stats={'tool_call_count': 12})
        self.assertEqual(self.sessions(self.cache.summary('2026-11-14'))[0]['tool_calls'], 12)
        before = stats.stat()
        stats.write_text(stats.read_text().replace('12', '21'))
        os.utime(stats, ns=(before.st_atime_ns, before.st_mtime_ns + 1000000))
        self.assertEqual(stats.stat().st_size, before.st_size)
        self.assertEqual(self.sessions(self.cache.summary('2026-11-14'))[0]['tool_calls'], 21)
        self.finding('111111111111')
        self.assertEqual(len(self.sessions(self.cache.summary('2026-11-14'))), 2)
        (self.day / '111111111111.json').unlink()
        self.assertEqual(len(self.sessions(self.cache.summary('2026-11-14'))), 1)
        for name in ['categories.tsv', 'run-stats.txt', 'pin-projects.tsv', 'session-cwds.tsv']:
            before = self.cache.fingerprint('2026-11-14')
            (self.day / name).write_text('changed')
            self.assertNotEqual(self.cache.fingerprint('2026-11-14'), before)
        stats.write_text('{partial')
        self.assertTrue(self.cache.summary('2026-11-14')['degraded'])
        self.finding(stats={'tool_call_count': 0})
        self.assertEqual(self.sessions(self.cache.summary('2026-11-14'))[0]['tool_calls'], 0)
        report = self.dreams / '2026-11-14.md'
        report.write_text('# Dream\n<!-- autodream:open-questions=2 -->')
        self.assertEqual(self.data.read_open_questions(report), 2)
        before = self.cache.fingerprint('2026-11-14')
        report.write_text('# Changed dream\n<!-- autodream:open-questions=1 -->')
        self.assertNotEqual(self.cache.fingerprint('2026-11-14'), before)
        original = self.data.read_open_questions
        def change_report(path):
            count = original(path)
            path.write_text('# New report\n<!-- autodream:open-questions=0 -->')
            return count
        with patch.object(self.data, 'read_open_questions', side_effect=change_report):
            changed = self.cache.read_dream('2026-11-14')
            newest = self.cache.lately()['newest_dream']
            self.assertIn('report changed while reading; retry', newest.get('degraded', []))
        self.assertIsNone(changed['open_questions'], 'a changing report must degrade its measurement')
        self.assertTrue(changed['degraded'])
        self.assertEqual(self.cache.read_dream('2026-11-14')['open_questions'], 0)
        original_build = self.data.build_night_summary
        def change_stats(date, paths):
            summary = original_build(date, paths)
            self.finding(stats={'tool_call_count': 30})
            return summary
        with patch.object(self.data, 'build_night_summary', side_effect=change_stats):
            changed = self.cache.summary('2026-11-14')
        self.assertIn('artifacts changed while reading; retry', changed['degraded'])
        self.assertEqual(self.sessions(self.cache.summary('2026-11-14'))[0]['tool_calls'], 30)


    def test_web_demo_build_answers_every_view(self):
        out = self.root / 'site'
        result = subprocess.run([sys.executable, str(REPO / 'docs/demo/build.py'), str(out)],
                                capture_output=True, text=True, timeout=60,
                                env=dict(os.environ, TMPDIR=str(self.root)))
        self.assertEqual(result.returncode, 0, result.stderr)
        api = out / 'api'
        lately = json.loads((api / 'lately.json').read_text())
        self.assertEqual(len(lately['timeline']), 7)
        self.assertTrue(all(night['projects'] and not night['degraded'] for night in lately['timeline']))
        self.assertEqual(lately['newest_dream']['open_questions'], 2)
        threads_file = json.loads((api / 'threads.json').read_text())
        self.assertRegex(threads_file['as_of'], r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$',
                         'the age filter must count from the build day')
        threads = threads_file['threads']
        self.assertEqual({t['display_status'] for t in threads}, {'open', 'dropped', 'done', 'closed_by_sam'})
        self.assertTrue(any(t['kind'] == 'idea' for t in threads))
        dates = json.loads((api / 'dreams.json').read_text())['dates']
        self.assertEqual(len(dates), 7)
        self.assertTrue(all((api / 'dreams' / (day + '.json')).is_file() for day in dates))
        self.assertEqual(len(json.loads((api / 'stats.json').read_text())['nights']), 7)
        page = (out / 'index.html').read_text()
        self.assertLess(page.index('web/demo-fetch.js'), page.index('web/app.js'))
        self.assertNotIn('"/web/', page, 'paths must be relative for a Pages subpath')
        self.assertNotIn('/Users/', (api / 'lately.json').read_text().replace('/Users/dev', ''),
                         'no real home path may leak into the demo')

    def test_web_demo_moves_dates_to_the_visitors_today(self):
        node = shutil.which('node')
        if node is None:
            self.skipTest('no node')
        script = r"""
const vm = require('vm'), fs = require('fs');
const pad = n => String(n).padStart(2, '0');
const local = d => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
const today = new Date(); const built = new Date(today); built.setDate(today.getDate() - 3);
const requested = [];
const window = {DEMO_BUILT: local(built), fetch: async url => {
  requested.push(String(url));
  return new Response(JSON.stringify({day: local(built), at: local(built) + 'T01:02:03Z', hash: '0123456789ab'}));
}};
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {window, document: {baseURI: 'https://x.test/demo/'},
  location: {href: 'https://x.test/demo/', origin: 'https://x.test'}, URL, Response, Date, JSON, Promise});
(async () => {
  const body = await (await window.fetch('/api/lately?days=7')).json();
  const dream = await window.fetch('/api/dreams/' + local(today));
  const action = await (await window.fetch('/api/threads/t-00000001/resume', {method: 'POST'})).json();
  console.log(JSON.stringify({body, requested, action}));
})();
"""
        result = subprocess.run([node, '-e', script, str(REPO / 'docs/demo/demo-fetch.js')],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        today = date.today()
        built = today - timedelta(days=3)
        self.assertEqual(out['body']['day'], today.isoformat())
        self.assertEqual(out['body']['at'], today.isoformat() + 'T01:02:03Z')
        self.assertEqual(out['body']['hash'], '0123456789ab')
        self.assertTrue(out['requested'][0].endswith('/demo/api/lately.json'), out['requested'])
        self.assertTrue(out['requested'][1].endswith('/demo/api/dreams/' + built.isoformat() + '.json'),
                        out['requested'])
        self.assertFalse(out['action']['ok'])
        self.assertIn('demo', out['action']['message'])

if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(DataTests))
    print(f'passed: {result.testsRun - len(result.failures) - len(result.errors)}   failed: {len(result.failures) + len(result.errors)}')
    sys.exit(not result.wasSuccessful())
