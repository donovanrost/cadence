export const filterKeys = ["category", "kind", "severity", "spacecraft_id", "from", "to"] as const;
export const queryKeys = [
  ...filterKeys,
  "event_id",
  "source_dashboard_id",
  "before_at",
  "before_id",
] as const;
export const referenceKeys = [
  "spacecraft_id",
  "source_endpoint_ref",
  "scheduled_contact_id",
  "realized_contact_id",
  "path_id",
  "capability_instance_id",
  "activation_id",
  "correlation_key",
] as const;
export type TimelineQuery = Record<(typeof queryKeys)[number], string>;
export type TimelineEvent = {
  id: string;
  occurred_at: string;
  category: string;
  kind: string;
  severity: string | null;
  status: string | null;
  title: string;
  summary: string | null;
  source: { kind: string; id: string };
  subject: { kind: string | null; id: string | null };
  references: Record<(typeof referenceKeys)[number], string | null>;
};
export type TimelineModel = {
  version: 1;
  context: { organization_id: string; mission_id: string };
  mission_name: string;
  observed_at: string;
  query: TimelineQuery;
  errors: string[];
  limit: 100;
  events: TimelineEvent[];
  next_cursor: { at: string; id: string } | null;
  selected_status: "none" | "ready" | "unavailable";
  selected: TimelineEvent | null;
  source_dashboard_id: string | null;
};
const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);
const text = (value: unknown, maximum = 8192): value is string =>
  typeof value === "string" && new TextEncoder().encode(value).length <= maximum;
const optional = (value: unknown): value is string | null => value === null || text(value);
const identity = (value: unknown): value is string =>
  text(value, 512) && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value);
const time = (value: unknown): value is string =>
  text(value, 40) &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value) &&
  Number.isFinite(Date.parse(value));
function event(value: unknown): value is TimelineEvent {
  return (
    record(value) &&
    identity(value.id) &&
    time(value.occurred_at) &&
    typeof value.category === "string" &&
    ["operations", "health", "runtime", "transport"].includes(value.category) &&
    text(value.kind, 120) &&
    (value.severity === null ||
      (typeof value.severity === "string" &&
        ["info", "warning", "error", "critical"].includes(value.severity))) &&
    optional(value.status) &&
    text(value.title) &&
    optional(value.summary) &&
    record(value.source) &&
    text(value.source.kind, 120) &&
    text(value.source.id, 512) &&
    record(value.subject) &&
    optional(value.subject.kind) &&
    optional(value.subject.id) &&
    record(value.references) &&
    referenceKeys.every((key) => optional((value.references as Record<string, unknown>)[key]))
  );
}
export function readTimeline(
  value: unknown,
  organizationId: unknown,
  missionId: unknown,
): TimelineModel {
  assertTimeline(value, organizationId, missionId);
  return value;
}
function assertTimeline(
  value: unknown,
  organizationId: unknown,
  missionId: unknown,
): asserts value is TimelineModel {
  if (
    !identity(organizationId) ||
    !identity(missionId) ||
    !record(value) ||
    value.version !== 1 ||
    !record(value.context) ||
    value.context.organization_id !== organizationId ||
    value.context.mission_id !== missionId ||
    !text(value.mission_name) ||
    !time(value.observed_at) ||
    value.limit !== 100 ||
    !record(value.query) ||
    !queryKeys.every((key) => text((value.query as Record<string, unknown>)[key], 512)) ||
    !Array.isArray(value.errors) ||
    value.errors.length > 8 ||
    !value.errors.every(
      (key: unknown) =>
        typeof key === "string" && [...filterKeys, "time_range", "cursor"].includes(key),
    ) ||
    !(
      value.next_cursor === null ||
      (record(value.next_cursor) && time(value.next_cursor.at) && identity(value.next_cursor.id))
    ) ||
    !Array.isArray(value.events) ||
    value.events.length > 100 ||
    !value.events.every(event) ||
    new Set(value.events.map((row) => row.id)).size !== value.events.length ||
    !(
      typeof value.selected_status === "string" &&
      ["none", "ready", "unavailable"].includes(value.selected_status)
    ) ||
    !(value.selected === null || event(value.selected)) ||
    (value.selected_status === "ready") !== (value.selected !== null) ||
    (value.selected_status === "none") !== (value.query.event_id === "") ||
    (value.selected !== null && value.selected.id !== value.query.event_id) ||
    !(value.source_dashboard_id === null || identity(value.source_dashboard_id)) ||
    (value.source_dashboard_id !== null &&
      value.source_dashboard_id !== value.query.source_dashboard_id)
  )
    throw Error("Invalid timeline evidence");
}
export function timelineHref(missionId: string, query: Partial<TimelineQuery>): string {
  if (!identity(missionId)) throw Error("Invalid mission identity");
  const params = new URLSearchParams();
  for (const key of queryKeys) {
    const value = query[key];
    if (value === undefined || value === "") continue;
    if (!text(value, 512)) throw Error("Invalid timeline query");
    params.set(key, value);
  }
  return `/missions/${encodeURIComponent(missionId)}/ops/timeline${params.size ? "?" + params.toString() : ""}`;
}
export const dashboardHref = (missionId: string, dashboardId: string) => {
  if (!identity(missionId) || !identity(dashboardId)) throw Error("Invalid dashboard identity");
  return `/missions/${encodeURIComponent(missionId)}/ops/dashboards/${encodeURIComponent(dashboardId)}`;
};
