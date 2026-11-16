"use strict";

function isInView(thread, view) {
  if (view === "Dropped") return thread.display_status === "dropped";
  if (view === "Open") return thread.display_status === "open" && thread.kind !== "idea";
  if (view === "Ideas") return thread.kind === "idea" && thread.display_status !== "done" && thread.display_status !== "closed_by_sam";
  return thread.display_status === "done" || thread.display_status === "closed_by_sam";
}

const moveTargets = [
  {view: "Open", action: "move-open", target: "open"},
  {view: "Ideas", action: "move-idea", target: "idea"},
  {view: "Done", action: "move-done", target: "done"}
];

function threadCommand(cli, id, action) {
  const move = moveTargets.find(function (item) { return item.action === action; });
  return move ? cli + " move " + id + " " + move.target : cli + " " + action + " " + id;
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
  const list = element("div", "thread-list");
  const empty = element("p", "thread-empty", "No threads in this view.");
  container.append(heading, controls, list, empty);
  root.replaceChildren(container);

  function render() {
    const query = search.value.toLocaleLowerCase();
    const repoFilter = repo.value;
    const filtered = data.threads.filter(function (thread) {
      const text = [thread.title, thread.goal, thread.repo, thread.id].join(" ").toLocaleLowerCase();
      return isInView(thread, activeView) && (!query || text.includes(query)) && (!repoFilter || thread.repo === repoFilter);
    });
    Array.from(views.children).forEach(function (tab) {
      const name = tab.dataset.view;
      const amount = data.threads.filter(function (thread) { return isInView(thread, name); }).length;
      tab.replaceChildren(document.createTextNode(name + " "), element("span", "count", String(amount)));
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
        const state = getActionState ? getActionState(thread.id) : null;
        const actionButton = function (action, label) {
          const button = document.createElement("button");
          button.type = "button";
          button.textContent = state?.pending && state.action === action ? "Working…" :
            state?.requiresRefresh ? "Refresh to check state" : label;
          button.disabled = Boolean(state?.pending || state?.requiresRefresh);
          button.addEventListener("click", function () { onAction(thread.id, action, button); });
          return button;
        };
        actions.appendChild(actionButton("resume", data.cli ? "Copy resume command" : "Resume"));
        const current = viewNames.find(function (name) { return isInView(thread, name); });
        const moveLabel = element("span", "move-label", "Move to");
        moveLabel.id = "move-to-" + thread.id;
        const move = element("div", "move-to");
        move.setAttribute("role", "group");
        move.setAttribute("aria-labelledby", moveLabel.id);
        moveTargets.filter(function (item) { return item.view !== current; }).forEach(function (item) {
          move.appendChild(actionButton(item.action, data.cli ? "Copy move " + item.target + " command" : item.view));
        });
        actions.append(moveLabel, move);
        const result = document.createElement("p");
        result.className = "action-result";
        result.setAttribute("role", "status");
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
    button.dataset.view = name;
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
    Array.from(views.children).forEach(function (button) { button.setAttribute("aria-pressed", String(button.dataset.view === activeView)); });
    render();
    document.getElementById(id)?.scrollIntoView({block: "nearest"});
  }
  search.addEventListener("input", render);
  repo.addEventListener("change", render);
  update(data);
  return {element: container, update, select, render};
}
