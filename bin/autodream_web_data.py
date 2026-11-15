"""Read-only artifact summaries for the local web server."""
import copy
from datetime import date as calendar_date, timedelta
import json
import math
import os
from pathlib import Path
import re
import subprocess
import threading

BIN = Path(__file__).resolve().parent
DATE = re.compile(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
FINDING = re.compile(r'^[0-9a-f]{12}\.json$')
OUTCOMES = {'fully_achieved', 'mostly_achieved', 'partially_achieved',
            'not_achieved', 'unclear_from_transcript'}


def valid_date(value):
    if not DATE.fullmatch(value):
        return False
    try:
        calendar_date.fromisoformat(value)
        return True
    except ValueError:
        return False


def fingerprint_files(paths):
    result = []
    for path in sorted(set(paths)):
        try:
            info = path.stat()
            result.append((str(path), info.st_mtime_ns, info.st_size))
        except OSError:
            result.append((str(path), None, None))
    return tuple(result)


def read_object(path, degraded, unreadable):
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
        if isinstance(value, dict):
            return value
    except (OSError, ValueError):
        pass
    degraded.append(path.name)
    unreadable.add(path.name)
    return {}


def read_open_questions(report_path):
    try:
        result = subprocess.run(['/bin/bash', str(BIN / 'report-format.sh'),
                                 'open-questions', str(report_path)],
                                capture_output=True, text=True, timeout=2, shell=False)
        value = result.stdout.strip()
        if result.returncode == 0 and re.fullmatch(r'[0-9]+', value):
            return int(value)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return None


def display_path(path, home):
    path = Path(path).resolve()
    if home:
        try:
            relative = path.relative_to(Path(home).resolve())
            return '~' if not relative.parts else '~/' + relative.as_posix()
        except (OSError, ValueError):
            pass
    return str(path)


def decoded_project(project, home):
    if not project.startswith('-'):
        return project
    decoded = '/' + project.lstrip('-').replace('-', '/')
    return display_path(decoded, home)


def cwd_excluded(cwd):
    if not cwd or not Path(cwd).is_absolute():
        return False
    lexical = Path(cwd)
    path = Path(cwd).resolve()
    excluded = {Path('/tmp').resolve(), Path('/private/tmp').resolve()}
    if os.environ.get('TMPDIR'):
        excluded.add(Path(os.environ['TMPDIR']).resolve())
    if any(path == root or root in path.parents for root in excluded):
        return True
    return 'scratchpad' in lexical.parts or 'scratchpad' in path.parts


def cwd_allowed(cwd):
    if not cwd or not Path(cwd).is_absolute() or cwd_excluded(cwd):
        return False
    try:
        Path(cwd).resolve(strict=True)
    except OSError:
        return False
    return True


def repo_for_project(project, cwd, thread_references, home=None):
    home = home if home is not None else os.environ.get('HOME', '')
    if cwd_allowed(cwd):
        try:
            result = subprocess.run(['git', '-C', str(cwd), 'rev-parse', '--git-common-dir'],
                                    capture_output=True, text=True, timeout=2, shell=False)
            if result.returncode == 0 and result.stdout.strip():
                common = Path(result.stdout.strip())
                if not common.is_absolute():
                    common = Path(cwd) / common
                common = common.resolve(strict=True)
                bare = subprocess.run(['git', '-C', str(cwd), 'rev-parse',
                                       '--is-bare-repository'], capture_output=True,
                                      text=True, timeout=2, shell=False)
                if bare.returncode == 0:
                    return str(common if bare.stdout.strip() == 'true' else common.parent)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            pass
    repos = {ref['repo'] for ref in thread_references
             if isinstance(ref, dict) and isinstance(ref.get('repo'), str) and ref['repo']}
    if len(repos) == 1:
        return repos.pop()
    if cwd and Path(cwd).is_absolute():
        return display_path(cwd, home)
    return decoded_project(project, home)


def measurement(value):
    if type(value) is int and value >= 0:
        return value
    if type(value) is float and math.isfinite(value) and value >= 0:
        return value
    return None


def text(value):
    return value if isinstance(value, str) and value.strip() else None


def build_night_summary(date, paths):
    directory = Path(paths['findings_dir'])
    degraded = []
    unreadable = set()
    mappings = {}
    session_cwds = {}
    mapping_file = directory / 'pin-projects.tsv'
    if mapping_file.exists():
        try:
            for row in mapping_file.read_text(encoding='utf-8').splitlines():
                project, cwd = row.split('\t')
                mappings.setdefault(project, set()).add(cwd)
        except (OSError, ValueError):
            degraded.append('pin-projects.tsv')
            unreadable.add('pin-projects.tsv')
    session_cwds_file = directory / 'session-cwds.tsv'
    if session_cwds_file.exists():
        try:
            for row in session_cwds_file.read_text(encoding='utf-8').splitlines():
                session_hash, cwd = row.split('\t')
                session_cwds[session_hash] = cwd
        except (OSError, ValueError):
            degraded.append('session-cwds.tsv')
            unreadable.add('session-cwds.tsv')
    projects = {}
    references = paths.get('thread_references', {})
    for path in sorted(directory.glob('*.json')):
        if not FINDING.fullmatch(path.name):
            continue
        finding = read_object(path, degraded, unreadable)
        stats_path = path.with_name(path.stem + '.stats.json')
        stats = read_object(stats_path, degraded, unreadable)
        provenance = [stats[key] for key in ('nested', 'isSidechain') if key in stats]
        if any(value is True for value in provenance):
            continue
        if not provenance or any(type(value) is not bool for value in provenance):
            degraded.append(path.stem + ': nesting not measured')
            continue
        project = text(finding.get('project'))
        if not project:
            degraded.append(path.name + ': project not measured')
            continue
        if path.stem in session_cwds:
            cwd = session_cwds[path.stem] if session_cwds[path.stem] != '?' else ''
        else:
            project_cwds = mappings.get(project, set())
            cwd = next(iter(project_cwds)) if len(project_cwds) == 1 else ''
        if cwd_excluded(cwd) or (not references.get((date, path.stem)) and
                                  not cwd and cwd_excluded(
                                      decoded_project(project, os.environ.get('HOME', '')))):
            continue
        initiatives = finding.get('notable_initiatives')
        fallback = text(initiatives[0]) if isinstance(initiatives, list) and initiatives else None
        goal = (text(finding.get('underlying_goal')) or fallback) if date >= '2026-07-20' else None
        outcome = finding.get('outcome')
        if date < '2026-07-17' or not isinstance(outcome, str) or outcome not in OUTCOMES:
            outcome = None
        session = dict(hash=path.stem, goal=goal, outcome=outcome,
                       user_messages=measurement(stats.get('user_message_count')),
                       tool_calls=measurement(stats.get('tool_call_count')),
                       duration_minutes=measurement(stats.get('duration_minutes')))
        session['_transcript_mtime'] = measurement(stats.get('transcript_mtime'))
        if any(value is None for key, value in session.items() if not key.startswith('_')):
            degraded.append(path.stem + ': measurements unavailable')
        session_refs = references.get((date, path.stem), [])
        ref_repos = tuple(sorted({ref['repo'] for ref in session_refs
                                  if isinstance(ref.get('repo'), str) and ref['repo']}))
        group = projects.setdefault((project, ref_repos, cwd),
                                    dict(project=project, sessions=[], references=session_refs,
                                         cwd=cwd))
        group['sessions'].append(session)
    rows = {}
    for _, group in sorted(projects.items()):
        project = group['project']
        cwd = group.pop('cwd')
        repo = repo_for_project(project, cwd, group.pop('references'))
        group['repo'] = repo
        if repo in rows:
            rows[repo]['sessions'].extend(group['sessions'])
        else:
            rows[repo] = group
    outcome_groups = {
        'fully_or_mostly': {'fully_achieved', 'mostly_achieved'},
        'partially': {'partially_achieved'},
        'not_achieved': {'not_achieved'},
        'unclear': {'unclear_from_transcript'},
        'unmeasured': {None},
    }
    for group in rows.values():
        sessions = group['sessions']
        sessions.sort(key=lambda session: (session['_transcript_mtime'] or -1, session['hash']),
                      reverse=True)
        group['session_count'] = len(sessions)
        group['outcomes'] = {name: sum(session['outcome'] in outcomes for session in sessions)
                             for name, outcomes in outcome_groups.items()}
        group['latest_goal'] = sessions[0]['goal'] if sessions else None
        for session in sessions:
            session.pop('_transcript_mtime', None)
    notices = []
    if date < '2026-07-17':
        notices.append('Outcomes were not measured before 2026-07-17.')
    if date < '2026-07-20':
        notices.append('Goals were not measured before 2026-07-20.')
    notices.extend('Could not read ' + name + '.' for name in sorted(unreadable))
    return dict(date=date, projects=sorted(rows.values(), key=lambda group: group['repo']),
                degraded=sorted(set(degraded)), notices=notices)


class NightCache:
    def __init__(self, autodream_dir, dreams_dir):
        self.root = Path(autodream_dir)
        self.dreams = Path(dreams_dir)
        self._nights = {}
        self._threads_key = None
        self._threads = None
        self._lock = threading.RLock()

    def fingerprint(self, date):
        directory = self.root / 'findings' / date
        paths = [directory / name for name in ('pin-projects.tsv', 'session-cwds.tsv',
                                                'categories.tsv', 'run-stats.txt')]
        paths.append(self.dreams / (date + '.md'))
        paths.extend(path for path in directory.glob('*.json')
                     if FINDING.fullmatch(path.name) or re.fullmatch(r'[0-9a-f]{12}\.stats\.json', path.name))
        return fingerprint_files(paths)

    def threads(self):
        with self._lock:
            key = (calendar_date.today().isoformat(),
                   fingerprint_files([self.root / 'threads.jsonl']))
            if key == self._threads_key:
                return self._threads
            try:
                result = subprocess.run(['/bin/bash', str(BIN / 'threads.sh'), 'list', '--json'],
                    env=dict(os.environ, AUTODREAM_DIR=str(self.root),
                             AUTODREAM_CONFIG=str(self.root / 'config'),
                             AUTODREAM_THREADS_STATE=str(self.root / 'threads.jsonl')),
                    capture_output=True, text=True, timeout=10, shell=False)
                rows = json.loads(result.stdout)
                if result.returncode or not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
                    return None
                after = (calendar_date.today().isoformat(),
                         fingerprint_files([self.root / 'threads.jsonl']))
                if after != key:
                    return None
                self._threads_key, self._threads = key, rows
                return rows
            except (OSError, ValueError, subprocess.TimeoutExpired):
                return None

    def summary(self, date):
        if not valid_date(date):
            raise ValueError('invalid dream date')
        with self._lock:
            threads = self.threads()
            key = (self.fingerprint(date), self._threads_key, threads is None)
            cached = self._nights.get(date)
            if cached and cached[0] == key:
                return copy.deepcopy(cached[1])
            references = {}
            for thread in threads or []:
                for session in thread.get('sessions', []):
                    references.setdefault((session.get('date'), session.get('hash')), []).append(thread)
            summary = build_night_summary(date, dict(findings_dir=self.root / 'findings' / date,
                                                    thread_references=references))
            if threads is None:
                summary['degraded'].append('threads unavailable')
            after = self.fingerprint(date)
            thread_after = fingerprint_files([self.root / 'threads.jsonl'])
            if after != key[0] or (threads is not None and thread_after != self._threads_key[1]):
                summary['degraded'].append('artifacts changed while reading; retry')
            elif not summary['degraded']:
                self._nights[date] = (key, copy.deepcopy(summary))
            return summary

    def dream_dates(self):
        return {'dates': sorted((path.stem for path in self.dreams.glob('*.md')
                                 if valid_date(path.stem) and path.is_file()), reverse=True)}

    def read_dream(self, date):
        if not valid_date(date):
            raise ValueError('invalid dream date')
        path = self.dreams / (date + '.md')
        before = fingerprint_files([path])
        markdown = path.read_text(encoding='utf-8')
        questions = read_open_questions(path)
        result = dict(date=date, markdown=markdown, open_questions=questions)
        if fingerprint_files([path]) != before:
            result.update(open_questions=None, degraded=['report changed while reading; retry'])
        return result

    def lately(self, days=7):
        if type(days) is not int or not 1 <= days <= 365:
            raise ValueError('days must be between 1 and 365')
        today = calendar_date.today()
        cutoff = (today - timedelta(days=days - 1)).isoformat()
        timeline = [self.summary(path.name) for path in sorted((self.root / 'findings').glob('*'), reverse=True)
                    if path.is_dir() and valid_date(path.name) and cutoff <= path.name <= today.isoformat()]
        threads = self.threads()
        counts = None if threads is None else dict(
            open=sum(t.get('status') == 'open' and t.get('kind') != 'idea' for t in threads),
            dropped=sum(t.get('status') == 'dropped' for t in threads),
            ideas=sum(t.get('kind') == 'idea' and t.get('status') in ('open', 'dropped') for t in threads))
        dates = self.dream_dates()['dates']
        newest = None
        if dates:
            dream = self.read_dream(dates[0])
            newest = dict(date=dates[0], open_questions=dream['open_questions'],
                          degraded=dream.get('degraded', []))
        return dict(days=days, timeline=timeline, threads=counts, newest_dream=newest)
