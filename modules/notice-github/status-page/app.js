// Status page for the notice-github module (issue #140).
//
// Fetches the state.json that the notice-github Lambda commits and renders one
// card per service. Zero dependencies, zero build step -- drop these files on
// GitHub Pages pointed at the repo the Lambda writes to.
//
// Contract (must match the Lambda producer):
//   { schema_version, generated_at, services: { <ecs-service-name>: {
//       cluster, app_name, url, status, updated_at } } }

"use strict";

const STATE_URL = "state.json";
const SUPPORTED_SCHEMA = 1;
// A service whose last update is older than this is flagged as stale -- the
// Lambda writes on every lifecycle event, so silence well past the idle window
// usually means the notifier, not the service, is wedged.
const STALE_AFTER_MS = 24 * 60 * 60 * 1000;
const REFRESH_MS = 60 * 1000;

// status enum (from the Lambda) -> display label + css modifier
const STATUS_META = {
  start: { label: "Starting", cls: "starting" },
  active: { label: "Active", cls: "active" },
  inactive: { label: "Idle", cls: "idle" },
  stop: { label: "Stopped", cls: "stopped" },
  unknown: { label: "Unknown", cls: "unknown" },
};

function meta(status) {
  return STATUS_META[status] || STATUS_META.unknown;
}

function parseTime(iso) {
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : ms;
}

function relativeTime(iso) {
  const ms = parseTime(iso);
  if (ms === null) return "unknown";
  const delta = Date.now() - ms;
  const sec = Math.round(delta / 1000);
  if (sec < 60) return "just now";
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} min ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr} hr ago`;
  const day = Math.round(hr / 24);
  return `${day} day${day === 1 ? "" : "s"} ago`;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function showBanner(message, kind) {
  const banner = document.getElementById("banner");
  banner.textContent = message;
  banner.className = `banner ${kind || ""}`.trim();
  banner.hidden = false;
}

function renderCard(name, svc) {
  const m = meta(svc.status);
  const card = el("article", `card ${m.cls}`);

  const head = el("div", "card-head");
  const badge = el("span", `badge ${m.cls}`, m.label);
  const title = el("h2", "card-title", svc.app_name || name);
  head.append(badge, title);

  const dl = el("dl", "meta");
  const rows = [
    ["Service", name],
    ["Cluster", svc.cluster || "—"],
    ["Updated", relativeTime(svc.updated_at)],
  ];
  for (const [k, v] of rows) {
    dl.append(el("dt", null, k), el("dd", null, v));
  }

  card.append(head, dl);

  // Only link http(s) URLs -- guards the href sink against a javascript:/data:
  // URL even though state.json is a trusted source (defense in depth).
  if (svc.url && /^https?:\/\//i.test(svc.url)) {
    const link = el("a", "card-link", "Open app ↗");
    link.href = svc.url;
    link.rel = "noopener noreferrer";
    card.append(link);
  }

  const ms = parseTime(svc.updated_at);
  if (ms !== null && Date.now() - ms > STALE_AFTER_MS) {
    card.append(el("p", "stale", "⚠ status may be stale"));
  }

  return card;
}

function render(state) {
  const grid = document.getElementById("services");
  grid.replaceChildren();

  if (
    typeof state.schema_version === "number" &&
    state.schema_version > SUPPORTED_SCHEMA
  ) {
    showBanner(
      `state.json is schema v${state.schema_version}; this page understands v${SUPPORTED_SCHEMA}. Some fields may not render.`,
      "warn",
    );
  }

  const services = state.services || {};
  const names = Object.keys(services).sort();

  if (names.length === 0) {
    grid.append(el("p", "loading", "No services reporting yet."));
  } else {
    for (const name of names) {
      grid.append(renderCard(name, services[name]));
    }
  }

  const gen = document.getElementById("generated");
  gen.textContent = state.generated_at
    ? `Generated ${relativeTime(state.generated_at)}`
    : "";
}

// Auto-refresh and the manual button can call load() concurrently; guard so a
// slower older response can't overwrite a newer one.
let latestRequestId = 0;

async function load() {
  const requestId = ++latestRequestId;
  try {
    const res = await fetch(STATE_URL, { cache: "no-store" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const state = await res.json();
    if (requestId !== latestRequestId) return;
    document.getElementById("banner").hidden = true;
    render(state);
  } catch (err) {
    if (requestId !== latestRequestId) return;
    showBanner(`Could not load status: ${err.message}`, "error");
  }
}

document.getElementById("refresh").addEventListener("click", load);
load();
setInterval(load, REFRESH_MS);
