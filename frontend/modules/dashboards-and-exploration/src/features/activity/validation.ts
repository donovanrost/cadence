import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { ActivityState } from "./contracts";
const fail = (): never => {
  throw Error("Invalid dashboard activity state");
};
export function exact(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return fail();
  const r = value as Record<string, unknown>;
  if (Object.keys(r).length !== keys.length || keys.some((k) => !Object.hasOwn(r, k))) fail();
  return r;
}
function text(v: unknown, max = 512): string {
  return typeof v === "string" && new TextEncoder().encode(v).length <= max ? v : fail();
}
function id(v: unknown): string {
  const s = text(v, 256);
  return s && !/[\u0000-\u001f]/.test(s) ? s : fail();
}
function number(v: unknown, min = 1, max = Number.MAX_SAFE_INTEGER - 1): number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= min && v <= max ? v : fail();
}
function optional(v: unknown, read: (v: unknown) => unknown) {
  if (v !== null) read(v);
}
function timestamp(v: unknown) {
  if (
    v !== null &&
    (!/^\d{4}-\d{2}-\d{2}T/.test(text(v, 64)) || !Number.isFinite(Date.parse(v as string)))
  )
    fail();
}
function list(v: unknown): unknown[] {
  return Array.isArray(v) && v.length <= 25 ? v : fail();
}
const summaryKeys = [
  "version",
  "kind",
  "parent_version",
  "based_on_version",
  "schema_version",
  "summary",
  "actor_id",
  "saved_at",
];
function summary(v: unknown, latest: number, selected = false) {
  const s = exact(v, [
    ...summaryKeys,
    ...(selected ? ["name", "widget_count", "section_count"] : []),
  ]);
  const version = number(s.version, 1, latest);
  if (!["draft_save", "publish", "revert", "migration"].includes(s.kind as string)) fail();
  for (const key of ["parent_version", "based_on_version"])
    optional(s[key], (v) => number(v, 1, version - 1));
  number(s.schema_version);
  text(s.summary, 4096);
  optional(s.actor_id, id);
  timestamp(s.saved_at);
  if (selected) {
    text(s.name);
    number(s.widget_count, 0);
    number(s.section_count, 0);
  }
  return s;
}
export function readActivity(value: unknown, context: OpsPageContext): ActivityState {
  const s = exact(value, ["sequence", "phase", "model"]);
  number(s.sequence, 0, 1_000_000);
  if (!["ready", "review"].includes(s.phase as string)) fail();
  const m = exact(s.model, [
    "version",
    "organization_id",
    "mission_id",
    "dashboard_id",
    "name",
    "document_version",
    "revision",
    "published_version",
    "archived",
    "author",
    "query",
    "versions",
    "next_version",
    "selected",
    "events",
    "next_event",
  ]);
  if (
    m.version !== 1 ||
    id(m.organization_id) !== context.organizationId ||
    id(m.mission_id) !== context.missionId ||
    id(m.dashboard_id) !== context.resourceId
  )
    fail();
  text(m.name);
  const latest = number(m.document_version);
  number(m.revision);
  optional(m.published_version, (v) => number(v, 1, latest));
  if (typeof m.archived !== "boolean" || typeof m.author !== "boolean") fail();
  const q = exact(m.query, ["version", "before_version", "before_event", "issue_id"]);
  optional(q.version, (v) => number(v, 1, latest));
  optional(q.before_version, number);
  optional(q.before_event, id);
  optional(q.issue_id, id);
  const selected = summary(m.selected, latest, true);
  if (selected.version !== (q.version ?? latest)) fail();
  let previous = q.before_version === null ? latest + 1 : number(q.before_version);
  const versions = list(m.versions).map((v) => {
    const r = summary(v, latest);
    if (number(r.version) >= previous) fail();
    previous = r.version as number;
    return r;
  });
  if (
    m.next_version !== null &&
    (versions.length !== 25 || m.next_version !== versions.at(-1)?.version)
  )
    fail();
  const events = list(m.events).map((v) => {
    const e = exact(v, ["id", "event_type", "document_version", "actor_id", "occurred_at"]);
    id(e.id);
    if (
      ![
        "published",
        "archived",
        "restored",
        "reverted",
        "comparison_review_requested",
        "comparison_review_resolved",
        "health_snapshot_captured",
        "publish_readiness_checked",
      ].includes(e.event_type as string)
    )
      fail();
    optional(e.document_version, (v) => number(v, 1, latest));
    optional(e.actor_id, id);
    timestamp(e.occurred_at);
    return e;
  });
  if (new Set(events.map((e) => e.id)).size !== events.length) fail();
  if (m.next_event !== null && (events.length !== 25 || m.next_event !== events.at(-1)?.id)) fail();
  return s as unknown as ActivityState;
}
