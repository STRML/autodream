"use strict";

function isInView(thread, view) {
  if (view === "Dropped") return thread.display_status === "dropped";
  if (view === "Open") return thread.display_status === "open" && thread.kind !== "idea";
  if (view === "Ideas") return thread.kind === "idea" && thread.display_status !== "done" && thread.display_status !== "closed_by_sam";
  return thread.display_status === "done" || thread.display_status === "closed_by_sam";
}

function copyCommand(command, button, label) {
  if (!command) return;
  const copied = function () {
    button.textContent = "Copied";
    window.setTimeout(function () { button.textContent = label; }, 1200);
  };
  const fallback = function () {
    const input = document.createElement("textarea");
    input.value = command;
    document.body.appendChild(input);
    input.select();
    document.execCommand("copy");
    input.remove();
    copied();
  };
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(command).then(copied, fallback);
    return;
  }
  fallback();
}

function mountThreads(root, data, onAction, getActionState) {
  const viewNames = ["Dropped", "Open", "Ideas", "Done"];
  let activeView = "Dropped";
  const container = document.createElement("section");
  container.className = "thread-view";
  function element(tag, className, text) {
    const item = document.createElement(tag);
    if (className) item.className = className;
    if (text) item.textContent = text;
    return item;
  }
  const heading = element("h1", "", "Threads");
  const controls = element("div", "thread-controls");
  const generated = element("div", "thread-generated");
  const inputs = element("div", "controls");
  const searchLabel = element("label", "", "Search ");
  const search = element("input");
  search.type = "search";
  search.autocomplete = "off";
  searchLabel.appendChild(search);
  const repoLabel = element("label", "", "Repo ");
  const repo = element("select");
  repoLabel.appendChild(repo);
  inputs.append(searchLabel, repoLabel);
  const views = element("nav");
  views.setAttribute("aria-label", "Thread views");
  controls.append(generated, inputs, views);
  const counts = element("div", "thread-counts");
  counts.setAttribute("aria-live", "polite");
  const list = element("div", "thread-list");
  const empty = element("p", "thread-empty", "No threads in this view.");
  container.append(heading, controls, counts, list, empty);
  root.replaceChildren(container);

  function render() {
    const query = search.value.toLocaleLowerCase();
    const repoFilter = repo.value;
    const filtered = data.threads.filter(function (thread) {
      const text = [thread.title, thread.goal, thread.repo, thread.id].join(" ").toLocaleLowerCase();
      return isInView(thread, activeView) && (!query || text.includes(query)) && (!repoFilter || thread.repo === repoFilter);
    });
    counts.replaceChildren();
    viewNames.forEach(function (name) {
      const amount = data.threads.filter(function (thread) { return isInView(thread, name); }).length;
      const label = document.createElement("span");
      label.textContent = name + " (" + amount + ")";
      counts.appendChild(label);
    });
    list.replaceChildren();
    filtered.forEach(function (thread) {
      const card = document.createElement("article");
      card.id = thread.id;
      const title = document.createElement("h2");
      title.textContent = thread.title || thread.goal;
      const meta = document.createElement("p");
      meta.className = "meta";
      meta.textContent = [thread.repo || "No repository", thread.sessions.length + (thread.sessions.length === 1 ? " session" : " sessions"), thread.last_seen, thread.display_status].join(" · ");
      const goal = document.createElement("p");
      goal.className = "goal";
      goal.textContent = thread.goal;
      const actions = document.createElement("div");
      actions.className = "actions";
      if (/^t-[0-9a-f]{8}$/.test(thread.id)) {
        const finished = ["done", "closed_by_sam"].includes(thread.display_status);
        const names = finished ? ["resume", "reopen"] : ["resume", "close"];
        names.forEach(function (action) {
          const label = data.cli ? "Copy " + action + " command" : action[0].toUpperCase() + action.slice(1);
          const state = getActionState ? getActionState(thread.id) : null;
          const button = document.createElement("button");
          button.type = "button";
          button.textContent = state?.pending && state.action === action ? "Working…" :
            state?.requiresRefresh ? "Refresh to check state" : label;
          button.disabled = Boolean(state?.pending || state?.requiresRefresh);
          button.addEventListener("click", function () { onAction(thread.id, action, button); });
          actions.appendChild(button);
        });
        const result = document.createElement("p");
        result.className = "action-result";
        result.setAttribute("role", "status");
        const state = getActionState ? getActionState(thread.id) : null;
        if (state?.message) result.appendChild(element("span", "", state.message));
        if (state?.brief) {
          const brief = element("textarea");
          brief.value = state.brief;
          brief.readOnly = true;
          brief.setAttribute("aria-label", "Resume brief to copy");
          result.appendChild(brief);
        }
        actions.appendChild(result);
      }
      card.appendChild(title);
      card.appendChild(meta);
      card.appendChild(goal);
      card.appendChild(actions);
      list.appendChild(card);
    });
    empty.hidden = filtered.length !== 0;
  }

  viewNames.forEach(function (name, index) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = name;
    button.setAttribute("aria-pressed", String(index === 0));
    button.addEventListener("click", function () {
      activeView = name;
      Array.from(views.children).forEach(function (child) { child.setAttribute("aria-pressed", String(child === button)); });
      render();
    });
    views.appendChild(button);
  });
  function update(next) {
    if (next) data = next;
    generated.textContent = data.generated_at ? "Generated " + new Date(data.generated_at).toLocaleString() + " · as of " + data.as_of : "";
    const selection = repo.value;
    repo.replaceChildren();
    const all = document.createElement("option");
    all.value = "";
    all.textContent = "All repositories";
    repo.appendChild(all);
    Array.from(new Set(data.threads.map(function (thread) { return thread.repo; }).filter(Boolean))).sort().forEach(function (name) {
      const option = document.createElement("option");
      option.value = name;
      option.textContent = name;
      repo.appendChild(option);
    });
    repo.value = selection;
    if (!repo.value) repo.value = "";
    render();
  }
  function select(id) {
    const thread = data.threads.find(function (item) { return item.id === id; });
    if (!thread) return;
    activeView = viewNames.find(function (name) { return isInView(thread, name); });
    search.value = "";
    repo.value = "";
    Array.from(views.children).forEach(function (button) { button.setAttribute("aria-pressed", String(button.textContent === activeView)); });
    render();
    document.getElementById(id)?.scrollIntoView({block: "nearest"});
  }
  search.addEventListener("input", render);
  repo.addEventListener("change", render);
  update(data);
  return {element: container, update, select, render};
}
