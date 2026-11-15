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
async function renderThreads(data, selectedId) {
  const request = viewRequest;
  if (!data) {
    const response = await fetch('/api/threads', {credentials: 'same-origin'});
    if (!response.ok) throw new Error('Could not read threads. Refresh to retry.');
    data = await response.json();
    if (request !== viewRequest) return false;
  }
  const content = document.getElementById('content');
  if (threadRenderer && content.contains(threadRenderer.element)) threadRenderer.update(data);
  else threadRenderer = mountThreads(content, data, performThreadAction,
    id => threadActionStates.get(id));
  if (selectedId && /^t-[0-9a-f]{8}$/.test(selectedId)) threadRenderer.select(selectedId);
  return true;
}

function clearSettledActions(request) {
  for (const [id, state] of threadActionStates) {
    if (state.settledAt !== undefined && request > state.settledAt) threadActionStates.delete(id);
  }
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
    const settledAt = viewRequest;
    let rendered = false;
    if (currentView === 'threads') {
      try { rendered = await renderThreads(); } catch (_) { rendered = false; }
    }
    if (rendered || currentView !== 'threads') threadActionStates.delete(id);
    else threadActionStates.set(id, {
      action, pending: false, requiresRefresh: true, settledAt,
      message: 'Action succeeded. Refresh to read the updated threads.'
    });
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

let viewRequest = 0;
async function loadView(view, date) {
  const request = ++viewRequest;
  currentView = view;
  const status = document.getElementById('status');
  status.textContent = 'Loading…';
  for (const link of document.querySelectorAll('nav a')) {
    if (link.hash === '#' + view) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
  try {
    const path = view === 'threads' ? '/api/threads' : view === 'dreams' ? '/api/dreams' + (date ? '/' + encodeURIComponent(date) : '') : '/api/lately?days=7';
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
    if (view === 'threads') {
      clearSettledActions(request);
      await renderThreads(data, date);
    }
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
    if (request === viewRequest) status.textContent = error instanceof TypeError ? 'Could not connect. Reload to retry.' : error.message;
  }
}

function navigate() {
  const [view, date] = location.hash.slice(1).split('/');
  loadView(['dreams', 'threads'].includes(view) ? view : 'lately', date);
}
window.addEventListener('hashchange', navigate);
document.addEventListener('DOMContentLoaded', navigate);
