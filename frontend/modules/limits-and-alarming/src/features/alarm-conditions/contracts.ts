import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { id, integer, page, record, stamp, text, type Page } from "../../shared/contracts";
import { state, type State } from "../../shared/states";
export const severityStates = {
  critical: "red",
  warning: "yellow",
  info: "blue",
  nominal: "green",
} as const;
export type Severity = keyof typeof severityStates;
export type AlarmQuery = {
  severity: "all" | Severity;
  state: "all" | "active" | "nominal";
  spacecraft_id: string;
  query: string;
  page: number;
  spacecraft_page: number;
  spacecraft_query: string;
};
export type AlarmDocument = {
  version: 1;
  organization_id: string;
  mission_id: string;
  mission_name: string;
  loaded_at: string;
  query: AlarmQuery;
  links: { self: string; definitions: string; posture: string };
  counts: Record<Severity, number>;
  states: Page<State>;
  spacecraft: Page<{ id: string; label: string }>;
  spacecraft_filter: string;
};
const keys = [
  "severity",
  "state",
  "spacecraft_id",
  "query",
  "page",
  "spacecraft_page",
  "spacecraft_query",
];
export function query(v: unknown): v is AlarmQuery {
  return (
    record(v) &&
    Object.keys(v).length === 7 &&
    ["all", ...Object.keys(severityStates)].includes(v.severity as string) &&
    ["all", "active", "nominal"].includes(v.state as string) &&
    id(v.spacecraft_id) &&
    text(v.query) &&
    text(v.spacecraft_query) &&
    [v.page, v.spacecraft_page].every((x) => integer(x) && x > 0 && x <= 100000)
  );
}
export function alarmHref(base: string, q: AlarmQuery) {
  return (
    base +
    "?" +
    new URLSearchParams(
      Object.fromEntries(
        Object.entries(q)
          .filter(([, v]) => v !== "")
          .map(([k, v]) => [k, String(v)]),
      ),
    )
  );
}
function link(v: unknown, base: string) {
  if (
    !text(v, 8192) ||
    !v.startsWith(base + "?") ||
    /[\\#]/.test(v) ||
    v.split("").some((c) => c.charCodeAt(0) <= 32)
  )
    return false;
  const q = new URLSearchParams(v.slice(base.length + 1));
  if (
    new Set(q.keys()).size !== [...q.keys()].length ||
    [...q.keys()].some((k) => !keys.includes(k))
  )
    return false;
  const obj = Object.fromEntries(q);
  return query({
    ...obj,
    query: obj.query || "",
    spacecraft_query: obj.spacecraft_query || "",
    page: Number(obj.page),
    spacecraft_page: Number(obj.spacecraft_page),
  });
}
function paging<T>(p: Page<T>, q: AlarmQuery, field: "page" | "spacecraft_page") {
  return (
    p.page === Math.min(q[field], Math.max(1, Math.ceil(p.total_count / 25))) &&
    [p.previous_href, p.next_href].every((href, i) => {
      if (href === null) return true;
      const actual = new URLSearchParams(href.split("?")[1]);
      const expected = { ...q, [field]: p.page + (i === 0 ? -1 : 1) };
      return keys.every((k) => (actual.get(k) || "") === String(expected[k as keyof AlarmQuery]));
    })
  );
}
export function admitAlarmDocument(v: unknown, expected: OpsPageContext): AlarmDocument | null {
  if (
    !record(v) ||
    v.version !== 1 ||
    !id(v.organization_id) ||
    !id(v.mission_id) ||
    v.organization_id !== expected.organizationId ||
    v.mission_id !== expected.missionId ||
    expected.resourceId !== undefined ||
    !text(v.mission_name) ||
    !stamp(v.loaded_at) ||
    !query(v.query) ||
    !record(v.links) ||
    !record(v.counts) ||
    Object.keys(v.counts).length !== 4 ||
    !Object.keys(severityStates).every((k) => integer((v.counts as Record<string, unknown>)[k])) ||
    !text(v.spacecraft_filter)
  )
    return null;
  const root = `/missions/${v.mission_id}`;
  if (
    v.links.self !== root + "/ops/alarms" ||
    v.links.definitions !== root + "/applications/limits/manage" ||
    v.links.posture !== root + "/applications/limits/activity"
  )
    return null;
  const base = v.links.self,
    posture = v.links.posture,
    mission = v.mission_id;
  if (
    !page(
      v.states,
      (x): x is State => state(x, posture, mission),
      base,
      (x) => link(x, base),
    ) ||
    !page(
      v.spacecraft,
      (x): x is { id: string; label: string } => record(x) && id(x.id) && text(x.label),
      base,
      (x) => link(x, base),
    )
  )
    return null;
  if (
    !paging(v.states, v.query, "page") ||
    !paging(v.spacecraft, v.query, "spacecraft_page") ||
    new Set(v.states.items.map((x) => x.id)).size !== v.states.items.length ||
    new Set(v.spacecraft.items.map((x) => x.id)).size !== v.spacecraft.items.length
  )
    return null;
  const q = v.query;
  const count =
    q.severity === "all"
      ? Object.values(v.counts).reduce<number>((a, x) => a + Number(x), 0)
      : v.counts[q.severity];
  if (
    v.states.total_count !== count ||
    v.states.items.some(
      (x) =>
        (q.severity !== "all" && x.severity !== severityStates[q.severity]) ||
        (q.state !== "all" && x.violation !== (q.state === "active")) ||
        (q.spacecraft_id !== "all" &&
          x.spacecraft_id !== (q.spacecraft_id === "mission" ? null : q.spacecraft_id)),
    )
  )
    return null;
  return v as AlarmDocument;
}

export function legacyAlarmHref(mission: unknown, params: unknown): string | null {
  if (!id(mission) || !record(params) || Object.keys(params).some((k) => !keys.includes(k)))
    return null;
  const input: Record<string, unknown> = {
    severity: "all",
    state: "all",
    spacecraft_id: "all",
    query: "",
    page: 1,
    spacecraft_page: 1,
    spacecraft_query: "",
    ...params,
  };
  for (const k of ["page", "spacecraft_page"]) {
    if (typeof input[k] === "string") {
      if (!/^[1-9][0-9]{0,5}$/.test(input[k] as string)) return null;
      input[k] = Number(input[k]);
    }
  }
  for (const k of ["severity", "state", "spacecraft_id"]) if (input[k] === "") input[k] = "all";
  return query(input) ? alarmHref(`/missions/${mission}/ops/alarms`, input) : null;
}
