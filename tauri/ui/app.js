const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const accents = { claude: "var(--claude)", codex: "var(--neutral)", grok: "var(--neutral)" };
const providers = document.getElementById("providers");

function used(w, now) {
  return w.resetsAt && new Date(w.resetsAt) <= now ? 0 : w.usedPercent;
}

function duration(ms) {
  const minutes = Math.ceil(ms / 60000);
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

function resetText(w, now) {
  if (!w.resetsAt) return "";
  const at = new Date(w.resetsAt);
  const ms = at - now;
  if (ms <= 0) return "reset";
  if (ms < 86400000) return `resets in ${duration(ms)}`;
  return "resets " + at.toLocaleString([], { weekday: "short", hour: "2-digit", minute: "2-digit" });
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function row(w, now) {
  const percent = used(w, now);
  const node = el("div", percent >= 80 ? "row hot" : "row");
  const labels = el("div", "labels");
  const name = el("span", "", w.label);
  const right = el("span");
  right.append(el("span", "percent", `${Math.round(percent)}%`), el("span", "muted", resetText(w, now) ? "  " + resetText(w, now) : ""));
  labels.append(name, right);
  const bar = el("div", "bar");
  const fill = el("span");
  fill.style.width = `${Math.min(100, Math.max(0, percent))}%`;
  bar.append(fill);
  node.append(labels, bar);
  return node;
}

function card(s, now) {
  const node = el("section", "card");
  node.style.setProperty("--accent", accents[s.provider]);
  const header = el("header");
  header.append(el("h2", "", s.name));
  if (s.snapshot && s.snapshot.plan) header.append(el("span", "muted", s.snapshot.plan));
  node.append(header);
  if (s.snapshot && !s.loggedOut) {
    s.snapshot.windows.slice(0, 4).forEach((w) => node.append(row(w, now)));
  }
  if (s.message) node.append(el("div", "note", s.message));
  else if (!s.snapshot) node.append(el("div", "note", "Loading"));
  else node.append(el("div", "note", "Updated " + new Date(s.snapshot.fetchedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })));
  return node;
}

function render(statuses) {
  const now = new Date();
  providers.replaceChildren(...statuses.map((s) => card(s, now)));
}

async function loadSettings() {
  const s = await invoke("settings");
  document.getElementById("minutes").value = s.refreshMinutes;
  document.getElementById("autostart").checked = s.autostart;
  document.getElementById("cookie-state").textContent = s.grokCookie ? "saved" : "not set";
}

document.getElementById("refresh").addEventListener("click", () => invoke("refresh"));
document.getElementById("minutes").addEventListener("change", async (e) => {
  await invoke("set_refresh_minutes", { minutes: Number(e.target.value) || 5 });
  loadSettings();
});
document.getElementById("autostart").addEventListener("change", async (e) => {
  await invoke("set_autostart", { on: e.target.checked }).catch(() => {});
  loadSettings();
});
document.getElementById("save-cookie").addEventListener("click", async () => {
  const input = document.getElementById("cookie");
  await invoke("set_grok_cookie", { value: input.value });
  input.value = "";
  loadSettings();
});

listen("statuses", (event) => render(event.payload));
invoke("statuses").then(render);
loadSettings();
setInterval(() => invoke("statuses").then(render), 60000);
