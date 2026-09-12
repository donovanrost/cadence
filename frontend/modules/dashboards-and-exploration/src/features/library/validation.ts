import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { LibraryState, LibraryReceipt } from "./contracts";
import { parseWidgetJson } from "./widget-json";
const fail = (): never => {
  throw Error("Invalid dashboard library contract");
};
export function exact(v: unknown, keys: string[]): Record<string, unknown> {
  if (!v || typeof v !== "object" || Array.isArray(v)) return fail();
  const r = v as Record<string, unknown>;
  if (Object.keys(r).length !== keys.length || keys.some((k) => !Object.hasOwn(r, k))) fail();
  return r;
}
function text(v: unknown, max = 512): string {
  return typeof v === "string" && new TextEncoder().encode(v).length <= max ? v : fail();
}
export function id(v: unknown): string {
  const s = text(v, 256);
  return s && !/[\u0000-\u001f]/.test(s) ? s : fail();
}
function number(v: unknown, min = 1, max = Number.MAX_SAFE_INTEGER - 1): number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= min && v <= max ? v : fail();
}
function optional(v: unknown, read: (v: unknown) => unknown) {
  if (v !== null) read(v);
}
function list(v: unknown, max = 25): unknown[] {
  return Array.isArray(v) && v.length <= max ? v : fail();
}
function unique(values: unknown[]) {
  if (new Set(values).size !== values.length) fail();
}
function item(v: unknown) {
  const r = exact(v, ["id", "name", "description", "latest_version"]);
  id(r.id);
  text(r.name);
  text(r.description, 4096);
  number(r.latest_version);
  return r;
}
function dashboard(v: unknown, pins = false) {
  const r = exact(v, ["id", "name", "version", ...(pins ? ["pins"] : [])]);
  id(r.id);
  text(r.name);
  optional(r.version, number);
  if (pins) {
    const values = list(r.pins, 1024).map((v) => {
      const p = exact(v, ["id", "version"]);
      id(p.id);
      number(p.version);
      return p;
    });
    unique(values.map((p) => p.id));
    if (!values.length) fail();
  }
  return r;
}
function next(v: unknown, rows: Record<string, unknown>[], key: string) {
  if (v !== null && (rows.length !== 25 || v !== rows.at(-1)?.[key])) fail();
}
export function readLibrary(value: unknown, context: OpsPageContext): LibraryState {
  const s = exact(value, ["sequence", "phase", "model"]);
  number(s.sequence, 0, 1000000);
  if (!["ready", "review"].includes(s.phase as string) || context.resourceId !== undefined) fail();
  const m = exact(s.model, [
    "version",
    "organization_id",
    "mission_id",
    "query",
    "items",
    "next_item",
    "selected",
    "dashboards",
    "next_dashboard",
    "target",
  ]);
  if (
    m.version !== 1 ||
    id(m.organization_id) !== context.organizationId ||
    id(m.mission_id) !== context.missionId
  )
    fail();
  const q = exact(m.query, [
    "q",
    "after",
    "item_id",
    "version",
    "before_version",
    "consumer_after",
    "dashboard_query",
    "dashboard_after",
    "target_id",
  ]);
  for (const key of ["q", "dashboard_query"]) text(q[key], 120);
  for (const key of ["after", "item_id", "consumer_after", "dashboard_after", "target_id"])
    optional(q[key], id);
  for (const key of ["version", "before_version"]) optional(q[key], number);
  const items = list(m.items).map(item);
  unique(items.map((i) => i.id));
  next(m.next_item, items, "id");
  const dashboards = list(m.dashboards).map((v) => dashboard(v));
  unique(dashboards.map((d) => d.id));
  next(m.next_dashboard, dashboards, "id");
  if (q.target_id === null) {
    if (m.target !== null) fail();
  } else {
    const target = dashboard(m.target);
    if (target.id !== q.target_id) fail();
    number(target.version);
  }
  if (q.item_id === null) {
    if (
      m.selected !== null ||
      q.version !== null ||
      q.before_version !== null ||
      q.consumer_after !== null
    )
      fail();
  } else {
    const selected = exact(m.selected, [
      "item",
      "version",
      "widget_json",
      "versions",
      "next_version",
      "consumers",
    ]);
    const identity = item(selected.item);
    if (identity.id !== q.item_id) fail();
    const latest = number(identity.latest_version);
    number(selected.version, 1, latest);
    if (selected.version !== (q.version ?? latest)) fail();
    parseWidgetJson(selected.widget_json);
    let previous = q.before_version === null ? latest + 1 : number(q.before_version);
    const versions = list(selected.versions).map((v) => {
      const r = exact(v, ["version", "summary", "actor_id", "saved_at"]);
      const n = number(r.version, 1, latest);
      if (n >= previous) fail();
      previous = n;
      text(r.summary, 4096);
      optional(r.actor_id, id);
      optional(r.saved_at, (v) => {
        if (!Number.isFinite(Date.parse(text(v, 64)))) fail();
      });
      return r;
    });
    next(selected.next_version, versions, "version");
    const consumers = exact(selected.consumers, ["total", "next", "rows"]);
    const rows = list(consumers.rows).map((v) => dashboard(v, true));
    number(consumers.total, rows.length);
    unique(rows.map((r) => r.id));
    next(consumers.next, rows, "id");
  }
  return s as unknown as LibraryState;
}
export function readReceipt(value: unknown): LibraryReceipt {
  const r = exact(value, [
    "version",
    "event",
    "item_id",
    "library_version",
    "dashboard_id",
    "document_version",
    "placement_id",
  ]);
  if (
    r.version !== 1 ||
    !["create_item", "add_version", "add_to_draft"].includes(r.event as string)
  )
    fail();
  id(r.item_id);
  number(r.library_version);
  if (r.event === "add_to_draft") {
    id(r.dashboard_id);
    number(r.document_version);
    id(r.placement_id);
  } else if (r.dashboard_id !== null || r.document_version !== null || r.placement_id !== null)
    fail();
  return r as unknown as LibraryReceipt;
}
