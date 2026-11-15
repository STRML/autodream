'use strict';

function node(tag, value, className) {
  const element = document.createElement(tag);
  if (value !== undefined) element.textContent = value;
  if (className) element.className = className;
  return element;
}

function appendInline(parent, source, depth = 0) {
  if (depth > 20) {
    parent.append(document.createTextNode(source));
    return;
  }
  const pattern = /(?<html><[^>\n]*>)|`(?<code>[^`]+)`|\*\*(?<strong>.+?)\*\*|__(?<underStrong>.+?)__|\*(?<em>[^*]+)\*|_(?<underEm>[^_]+)_|\[(?<label>[^\]]+)\]\((?<url>[^\s)]+)\)/g;
  let offset = 0;
  for (const match of source.matchAll(pattern)) {
    parent.append(document.createTextNode(source.slice(offset, match.index)));
    const token = match.groups;
    if (token.html) parent.append(document.createTextNode(token.html));
    else if (token.code) parent.append(node('code', token.code));
    else if (token.strong || token.underStrong || token.em || token.underEm) {
      const child = node(token.strong || token.underStrong ? 'strong' : 'em');
      appendInline(child, token.strong || token.underStrong || token.em || token.underEm, depth + 1);
      parent.append(child);
    } else {
      let url;
      try { url = new URL(token.url); } catch (_) { url = null; }
      if (url && ['http:', 'https:'].includes(url.protocol)) {
        const link = node('a', token.label);
        link.href = url.href;
        link.rel = 'noreferrer noopener';
        parent.append(link);
      } else parent.append(document.createTextNode(match[0]));
    }
    offset = match.index + match[0].length;
  }
  parent.append(document.createTextNode(source.slice(offset)));
}

function tableCells(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(cell => cell.trim());
}

function renderMarkdown(markdown, depth = 0) {
  const fragment = document.createDocumentFragment();
  const lines = String(markdown).replace(/<!--[\s\S]*?(?:-->|$)/g, '').replace(/\r\n?/g, '\n').split('\n');
  let paragraph = [];
  const flush = () => {
    if (!paragraph.length) return;
    const p = node('p');
    paragraph.forEach((line, index) => {
      if (index) p.append(node('br'));
      appendInline(p, line);
    });
    fragment.append(p);
    paragraph = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim()) { flush(); continue; }
    const fence = line.match(/^\s*(`{3,}|~{3,})/);
    if (fence) {
      flush();
      const code = [];
      const end = new RegExp('^\\s*' + fence[1][0] + '{' + fence[1].length + ',}\\s*$');
      while (++i < lines.length && !end.test(lines[i])) code.push(lines[i]);
      const pre = node('pre');
      pre.append(node('code', code.join('\n')));
      fragment.append(pre);
      continue;
    }
    const heading = line.match(/^(#{1,6})\s+(.+)$/);
    if (heading) {
      flush();
      const h = node('h' + heading[1].length);
      appendInline(h, heading[2]);
      fragment.append(h);
      continue;
    }
    if (/^\s*(?:---+|\*\*\*+|___+)\s*$/.test(line)) {
      flush(); fragment.append(node('hr')); continue;
    }
    if (line.includes('|') && i + 1 < lines.length &&
        tableCells(lines[i + 1]).every(cell => /^:?-{3,}:?$/.test(cell))) {
      flush();
      const table = node('table');
      const head = node('thead');
      const body = node('tbody');
      const addRow = (parent, cells, tag) => {
        const row = node('tr');
        for (const cell of cells) {
          const item = node(tag);
          appendInline(item, cell);
          row.append(item);
        }
        parent.append(row);
      };
      addRow(head, tableCells(line), 'th');
      i++;
      while (i + 1 < lines.length && lines[i + 1].includes('|') && lines[i + 1].trim()) {
        addRow(body, tableCells(lines[++i]), 'td');
      }
      table.append(head, body);
      fragment.append(table);
      continue;
    }
    const list = line.match(/^\s*(?:([-+*])|([0-9]+)\.)\s+(.+)$/);
    if (list) {
      flush();
      const tag = list[2] ? 'ol' : 'ul';
      const group = node(tag);
      const pattern = tag === 'ol' ? /^\s*[0-9]+\.\s+(.+)$/ : /^\s*[-+*]\s+(.+)$/;
      do {
        const item = node('li');
        appendInline(item, lines[i].match(pattern)[1]);
        group.append(item);
        i++;
      } while (i < lines.length && pattern.test(lines[i]));
      i--;
      fragment.append(group);
      continue;
    }
    if (/^>\s?/.test(line) && depth < 20) {
      flush();
      const quote = [];
      do { quote.push(lines[i++].replace(/^>\s?/, '')); }
      while (i < lines.length && /^>\s?/.test(lines[i]));
      i--;
      const block = node('blockquote');
      block.append(renderMarkdown(quote.join('\n'), depth + 1));
      fragment.append(block);
      continue;
    }
    paragraph.push(line);
  }
  flush();
  return fragment;
}

function measured(value) {
  return value === null || value === undefined ? '—' : String(value).replaceAll('_', ' ');
}

function outcomeLabel(value) {
  return ({fully_achieved: '✓ fully achieved', mostly_achieved: '✓ mostly achieved',
    partially_achieved: '◐ partially achieved', not_achieved: '✗ not achieved',
    unclear_from_transcript: '? unclear'})[value] || '—';
}

function appendNotices(parent, data) {
  for (const notice of new Set([...(data.notices || []), ...(data.degraded || [])])) {
    parent.append(node('p', notice, 'notice'));
  }
}

function renderLately(data) {
  const content = document.getElementById('content');
  content.replaceChildren(node('h1', 'Lately'), node('p', 'Your last ' + data.days + ' days in AI.', 'intro'));
  const counts = data.threads;
  content.append(node('p', counts ? `${counts.open} open threads · ${counts.dropped} dropped · ${counts.ideas} ideas` :
    'Thread counts: not measured', 'summary'));
  if (data.newest_dream) {
    const newest = node('a', 'Newest dream: ' + data.newest_dream.date);
    newest.href = '#dreams/' + data.newest_dream.date;
    content.append(newest, node('p', 'Open questions: ' + measured(data.newest_dream.open_questions)));
    appendNotices(content, data.newest_dream);
  }
  if (!data.timeline.length) content.append(node('p', 'No recent session artifacts. Dreams keeps the report archive.'));
  for (const night of data.timeline) {
    const section = node('section');
    section.append(node('h2', night.date));
    appendNotices(section, night);
    if (!night.projects.length) section.append(node('p', night.degraded?.length ?
      'Session summary is incomplete.' : 'No top-level sessions.'));
    for (const project of night.projects) {
      const row = node('article', undefined, 'project-row');
      row.append(node('h3', project.repo || project.project));
      const outcomes = project.outcomes || {};
      row.append(node('p', `${project.session_count ?? project.sessions.length} sessions · ` +
        `✓ ${measured(outcomes.fully_or_mostly)} fully/mostly · ` +
        `◐ ${measured(outcomes.partially)} partially · ` +
        `✗ ${measured(outcomes.not_achieved)} not achieved · ` +
        `? ${measured(outcomes.unclear)} unclear · ` +
        `? ${measured(outcomes.unmeasured)} unmeasured`, 'project-outcomes'));
      const latestGoal = project.latest_goal ?? project.sessions[0]?.goal;
      row.append(node('p', measured(latestGoal), 'project-goal'));
      for (const thread of data.thread_links || []) {
        if (!/^t-[0-9a-f]{8}$/.test(thread.id) || !thread.sessions.some(source =>
          source.date === night.date && project.sessions.some(session => session.hash === source.hash))) continue;
        const link = node('a', thread.title);
        link.href = '#threads/' + thread.id;
        const threadLink = node('p');
        threadLink.append(link);
        row.append(threadLink);
      }
      const details = node('details');
      details.append(node('summary', `Sessions (${project.session_count ?? project.sessions.length})`));
      const list = node('ul', undefined, 'sessions');
      for (const session of project.sessions) {
        const item = node('li');
        item.append(node('p', measured(session.goal), 'goal'));
        item.append(node('p', outcomeLabel(session.outcome), 'outcome'));
        item.append(node('p', `${measured(session.user_messages)} user messages · ${measured(session.tool_calls)} tool calls · ${measured(session.duration_minutes)} minutes`, 'metrics'));
        list.append(item);
      }
      details.append(list);
      row.append(details);
      section.append(row);
    }
    content.append(section);
  }
}

function renderDream(data) {
  const content = document.getElementById('content');
  const back = node('a', 'All dreams');
  back.href = '#dreams';
  const article = node('article');
  article.append(renderMarkdown(data.markdown));
  content.replaceChildren(back, node('p', data.date + ' · Open questions: ' + measured(data.open_questions), 'summary'));
  appendNotices(content, data);
  content.append(article);
}

let threadRenderer;
const threadActionStates = new Map();
let currentView = 'lately';
let threadFetches = 0;
function drawThreads(data, seq, selectedId) {
  for (const [id, state] of threadActionStates) {
    if (state.settledAt !== undefined && seq > state.settledAt) threadActionStates.delete(id);
  }
  const content = document.getElementById('content');
  if (threadRenderer && content.contains(threadRenderer.element)) threadRenderer.update(data);
  else threadRenderer = mountThreads(content, data, performThreadAction,
    id => threadActionStates.get(id));
  if (selectedId && /^t-[0-9a-f]{8}$/.test(selectedId)) threadRenderer.select(selectedId);
}

async function refreshThreads() {
  const request = viewRequest;
  const seq = ++threadFetches;
  const response = await fetch('/api/threads', {credentials: 'same-origin'});
  if (!response.ok) return;
  const data = await response.json();
  if (request === viewRequest && currentView === 'threads') drawThreads(data, seq);
}

async function performThreadAction(id, action) {
  const existing = threadActionStates.get(id);
  if (existing?.pending || existing?.requiresRefresh) return;
  threadActionStates.set(id, {action, pending: true, requiresRefresh: false});
  threadRenderer?.render();
  try {
    const response = await fetch('/api/threads/' + encodeURIComponent(id) + '/' + action, {
      method: 'POST', credentials: 'same-origin', headers: {'X-Autodream': '1'}
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      threadActionStates.set(id, {
        action, pending: false, requiresRefresh: data.error === 'timeout',
        message: data.message || 'Action failed', brief: data.brief || ''
      });
      return;
    }
    threadActionStates.set(id, {
      action, pending: false, requiresRefresh: true, settledAt: threadFetches,
      message: 'Action succeeded. Refresh to read the updated threads.'
    });
    if (currentView === 'threads') {
      try { await refreshThreads(); } catch (_) {}
    }
  } catch (_) {
    threadActionStates.set(id, {
      action, pending: false, requiresRefresh: true,
      message: 'The outcome is unknown. Refresh before trying again.'
    });
  } finally {
    const state = threadActionStates.get(id);
    if (state?.pending) threadActionStates.set(id, {...state, pending: false});
    if (threadRenderer && document.getElementById('content').contains(threadRenderer.element)) threadRenderer.render();
  }
}

function svgNode(tag, attributes = {}, value) {
  const element = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [key, val] of Object.entries(attributes)) element.setAttribute(key, String(val));
  if (value !== undefined) element.textContent = value;
  return element;
}

function drawSeries(svg, points, label) {
  svg.replaceChildren(svgNode('title', {}, label));
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', label);
  svg.setAttribute('viewBox', '0 0 640 180');
  const available = points.filter(p => typeof p.value === 'number' && Number.isFinite(p.value));
  if (!available.length) {
    svg.append(svgNode('text', {x: 16, y: 80}, 'Not measured'));
    return;
  }
  const first = Date.parse(points[0].date);
  const last = Date.parse(points[points.length - 1].date);
  const max = Math.max(1, ...available.map(p => p.value));
  svg.append(svgNode('path', {d: 'M 48 12 V 144 H 624', class: 'chart-axis'}));
  svg.append(svgNode('text', {x: 4, y: 20}, measured(max)), svgNode('text', {x: 24, y: 144}, '0'));
  svg.append(svgNode('text', {x: 48, y: 174}, points[0].date),
    svgNode('text', {x: 624, y: 174, 'text-anchor': 'end'}, points[points.length - 1].date));
  let previous;
  for (const point of points) {
    if (typeof point.value !== 'number' || !Number.isFinite(point.value)) { previous = undefined; continue; }
    const time = Date.parse(point.date);
    const x = first === last ? 336 : 48 + (time - first) / (last - first) * 576;
    const y = 144 - point.value / max * 124;
    if (previous && time - previous.time === 86400000) {
      svg.append(svgNode('path', {d: `M ${previous.x} ${previous.y} L ${x} ${y}`, class: 'chart-line'}));
    }
    const dot = svgNode('circle', {cx: x, cy: y, r: 3, 'data-value': point.value, 'data-date': point.date});
    dot.append(svgNode('title', {}, point.date + ': ' + point.value));
    svg.append(dot);
    previous = {time, x, y};
  }
}

function appendChart(parent, nights, label, valueFor) {
  const section = node('section', undefined, 'stats-series');
  section.append(node('h3', label));
  const points = nights.map(night => ({date: night.date, value: valueFor(night)}));
  const svg = svgNode('svg');
  drawSeries(svg, points, label);
  section.append(svg);
  const details = node('details');
  details.append(node('summary', 'Values by night'));
  const table = node('table');
  const head = node('tr');
  head.append(node('th', 'Date'), node('th', label));
  const thead = node('thead');
  thead.append(head);
  const tbody = node('tbody');
  for (const point of points) {
    const row = node('tr');
    row.append(node('td', point.date), node('td', point.value == null ? 'Not measured' : measured(point.value)));
    tbody.append(row);
  }
  table.append(thead, tbody);
  details.append(table);
  section.append(details);
  parent.append(section);
}

function renderStats(data) {
  const content = document.getElementById('content');
  content.replaceChildren(node('h1', 'Stats'), node('p', 'Nightly activity and pipeline health. Gaps mean not measured.', 'intro'));
  const nights = [...data.nights].sort((a, b) => a.date.localeCompare(b.date));
  if (!nights.length) { content.append(node('p', 'No nightly statistics yet.')); return; }
  for (const night of nights) {
    for (const notice of night.degraded || []) content.append(node('p', night.date + ': ' + notice, 'notice'));
  }
  content.append(node('h2', 'Activity'), node('p', 'Activity and outcomes cover top-level sessions.', 'metrics'));
  for (const [key, label] of [['user_messages', 'User messages'], ['tool_calls', 'Tool calls'], ['duration_minutes', 'Duration (minutes)']]) {
    appendChart(content, nights, label, n => n.activity?.[key]);
  }
  for (const [key, label] of [['top_level', 'Top-level sessions'], ['nested', 'Nested sessions']]) {
    appendChart(content, nights, label, n => n.sessions?.[key]);
  }
  content.append(node('h2', 'Outcomes'));
  for (const key of ['fully_achieved', 'mostly_achieved', 'partially_achieved', 'not_achieved', 'unclear_from_transcript']) {
    appendChart(content, nights, measured(key), n => n.outcomes?.[key]);
  }
  content.append(node('h2', 'Category findings'));
  const categories = [...new Set(nights.flatMap(n => (n.categories || []).filter(c => c.severity === 'all').map(c => c.category)))].sort();
  if (!categories.length) content.append(node('p', 'No measured category findings.'));
  for (const category of categories) {
    appendChart(content, nights, 'Category findings: ' + measured(category), n => {
      if (!n.categories) return null;
      const rows = n.categories.filter(c => c.category === category);
      return rows.length ? rows.find(c => c.severity === 'all')?.findings ?? null : 0;
    });
  }
  content.append(node('h2', 'Pipeline health'));
  for (const [key, label] of [['l1_elapsed_seconds', 'L1 elapsed (seconds)'], ['l1_timed_out', 'L1 timeouts'],
    ['l1_missing_after_retries', 'Missing after retries'], ['l1_findings_with_error', 'Findings with errors'],
    ['stats_sidecars_unparseable', 'Unreadable sidecars'], ['network_down_seconds', 'L1 network wait (seconds)'],
    ['network_down_seconds_l2', 'L2 network wait (seconds)'], ['l1_served_mismatch', 'Served model mismatches'],
    ['l1_chunks_elided', 'Chunks elided'], ['overlap_events', 'Overlap events']]) {
    appendChart(content, nights, label, n => n.run?.[key]);
  }
  content.append(node('h2', 'Finished that day'),
    node('p', 'Current done threads whose last_seen is that day. This count changes when threads are reopened.', 'metrics'));
  appendChart(content, nights, 'Finished that day', n => n.finished_that_day);
}

function renderProgress(data) {
  const content = document.getElementById('content');
  content.replaceChildren(node('h1', 'Progress'), node('p', 'Run ownership, refreshed every 5 seconds.', 'intro'));
  if (!data.runs.length) content.append(node('p', 'No run locks.'));
  for (const run of data.runs) {
    const section = node('section', undefined, 'run-row');
    section.append(node('h2', run.date + ' · ' + run.state));
    section.append(node('p', 'PID ' + measured(run.pid) + ' · Started ' + measured(run.started_at) +
      ' · Elapsed ' + measured(run.elapsed_seconds) + ' seconds', 'metrics'));
    section.append(node('h3', 'Last log line'), node('pre', run.last_log_line ?? 'No log line available.', 'last-log-line'));
    content.append(section);
  }
}

let progressTimer;
let progressPending = false;
async function pollProgress() {
  if (document.hidden || currentView !== 'progress' || progressPending) return;
  progressPending = true;
  try { await loadView('progress'); }
  finally { progressPending = false; }
}

let viewRequest = 0;
async function loadView(view, date) {
  const request = ++viewRequest;
  currentView = view;
  if (view === 'progress' && !progressTimer) progressTimer = window.setInterval(pollProgress, 5000);
  if (view !== 'progress' && progressTimer) {
    window.clearInterval(progressTimer);
    progressTimer = undefined;
  }
  const status = document.getElementById('status');
  status.textContent = 'Loading…';
  for (const link of document.querySelectorAll('nav a')) {
    if (link.hash === '#' + view) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
  try {
    const path = view === 'stats' ? '/api/stats' : view === 'progress' ? '/api/progress' : view === 'threads' ? '/api/threads' : view === 'dreams' ? '/api/dreams' + (date ? '/' + encodeURIComponent(date) : '') : '/api/lately?days=7';
    const seq = view === 'threads' ? ++threadFetches : 0;
    const response = await fetch(path, {credentials: 'same-origin'});
    if (!response.ok) throw new Error(response.status === 401 ? 'Run autodream-web open to sign in.' : 'Could not read this view. Reload to retry.');
    const data = await response.json();
    if (view === 'lately') {
      try {
        const threads = await fetch('/api/threads', {credentials: 'same-origin'});
        if (threads.ok) data.thread_links = (await threads.json()).threads;
      } catch (_) {}
    }
    if (request !== viewRequest) return;
    if (view === 'stats') renderStats(data);
    else if (view === 'progress') renderProgress(data);
    else if (view === 'threads') drawThreads(data, seq, date);
    else if (view !== 'dreams') renderLately(data);
    else if (date) renderDream(data);
    else {
      const content = document.getElementById('content');
      content.replaceChildren(node('h1', 'Dreams'), node('p', 'The nightly report archive.', 'intro'));
      const list = node('ul', undefined, 'dreams');
      for (const day of data.dates) {
        const link = node('a', day);
        link.href = '#dreams/' + day;
        const item = node('li');
        item.append(link);
        list.append(item);
      }
      content.append(list);
      if (!data.dates.length) content.append(node('p', 'No dreams yet. Reports appear here after a completed nightly run.'));
    }
    status.textContent = '';
  } catch (error) {
    if (request === viewRequest) status.textContent = error instanceof TypeError ? 'server not reachable' : error.message;
  }
}

function navigate() {
  const [view, date] = location.hash.slice(1).split('/');
  loadView(['dreams', 'threads', 'progress', 'stats'].includes(view) ? view : 'lately', date);
}
window.addEventListener('hashchange', navigate);
document.addEventListener('DOMContentLoaded', () => {
  const nav = document.querySelector('header nav') || document.querySelector('nav');
  for (const view of ['progress', 'stats']) {
    if (nav && !nav.querySelector('a[href="#' + view + '"]')) {
      const link = node('a', view === 'progress' ? 'Progress' : 'Stats');
      link.href = '#' + view;
      nav.append(link);
    }
  }
  navigate();
});
document.addEventListener('visibilitychange', pollProgress);
