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
  }
  if (!data.timeline.length) content.append(node('p', 'No recent session artifacts. Dreams keeps the report archive.'));
  for (const night of data.timeline) {
    const section = node('section');
    section.append(node('h2', night.date));
    for (const notice of night.notices || []) section.append(node('p', notice, 'notice'));
    if (!night.projects.length) section.append(node('p', 'No top-level sessions.'));
    for (const project of night.projects) {
      const row = node('article', undefined, 'project-row');
      row.append(node('h3', project.repo || project.project));
      const outcomes = project.outcomes || {};
      row.append(node('p', `${project.session_count ?? project.sessions.length} sessions · ` +
        `✓ ${outcomes.fully_or_mostly ?? 0} fully/mostly · ` +
        `◐ ${outcomes.partially ?? 0} partially · ` +
        `✗ ${outcomes.not_achieved ?? 0} not achieved · ` +
        `? ${outcomes.unclear ?? 0} unclear`, 'project-outcomes'));
      const latestGoal = project.latest_goal ?? project.sessions[0]?.goal;
      row.append(node('p', measured(latestGoal), 'project-goal'));
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
  content.replaceChildren(back, node('p', data.date + ' · Open questions: ' + measured(data.open_questions), 'summary'), article);
}

let viewRequest = 0;
async function loadView(view, date) {
  const request = ++viewRequest;
  const status = document.getElementById('status');
  status.textContent = 'Loading…';
  for (const link of document.querySelectorAll('nav a')) {
    if (link.hash === '#' + view) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
  try {
    const path = view === 'dreams' ? '/api/dreams' + (date ? '/' + encodeURIComponent(date) : '') : '/api/lately?days=7';
    const response = await fetch(path, {credentials: 'same-origin'});
    if (!response.ok) throw new Error(response.status === 401 ? 'Run autodream-web open to sign in.' : 'Could not read this view. Reload to retry.');
    const data = await response.json();
    if (request !== viewRequest) return;
    if (view !== 'dreams') renderLately(data);
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
  loadView(view === 'dreams' ? view : 'lately', date);
}
window.addEventListener('hashchange', navigate);
document.addEventListener('DOMContentLoaded', navigate);
