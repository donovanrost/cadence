export type Context = {
  organization_id: string;
  mission_id: string;
  actor_id: string;
  installation_id: string;
};
export type Query = Record<string, string | number | null>;
export type Base = Record<string, unknown> & {
  contract_version: 1;
  surface: "manage" | "activity";
  context: Context;
  mission_name: string;
  query: Query;
  links: { self: string; manage: string; activity: string; applications: string };
};
export type Page<T> = {
  items: T[];
  total_count: number;
  page: number;
  page_size: 25;
  previous_href: string | null;
  next_href: string | null;
};
export const fields = ["red_low", "yellow_low", "yellow_high", "red_high"] as const;
export type Thresholds = Partial<Record<(typeof fields)[number], number>>;
export type Definition = {
  id: string;
  point_id: string;
  limit_set_name: string;
  version: number;
  thresholds: Thresholds;
};
export type DefinitionRow = Definition & { href: string };
export type Active = {
  definition_id: string;
  version: number;
  event_id: string;
  active_from: string;
  active_to: string | null;
};
export type Activation = {
  id: string;
  definition_id: string;
  version: number;
  event_type: string;
  active_from: string;
  active_to: string | null;
  observed_at: string;
  scope_type: string | null;
  scope_ref: string | null;
  realm: string | null;
};
export type Selection =
  | null
  | { available: false; id: string }
  | {
      available: true;
      id: string;
      current: Definition;
      inspected: Definition;
      active: Active | null;
      history: Page<DefinitionRow>;
      activations: Page<Activation>;
    };
export const record = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
export const text = (v: unknown, max = 240): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
export const id = (v: unknown): v is string => text(v) && v.length > 0 && !/[/?#\s]/.test(v);
export const name = (v: unknown): v is string => text(v) && v.trim().length > 0;
export const integer = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
export const stamp = (v: unknown): v is string => text(v, 64) && Number.isFinite(Date.parse(v));
export const nullable = (v: unknown, test: (v: unknown) => boolean) => v === null || test(v);
const numbers = ["page", "history_page", "activation_page", "points_page", "spacecraft_page"];
const strings = [
  "q",
  "points_q",
  "spacecraft_q",
  "spacecraft",
  "definition",
  "point",
  "set",
  "severity",
];
export function localLink(v: unknown, base: string): v is string {
  if (
    !text(v, 8192) ||
    !v.startsWith(base + "?") ||
    /[\\#]/.test(v) ||
    v.split("").some((c) => c.charCodeAt(0) <= 32)
  )
    return false;
  const q = new URLSearchParams(v.slice(base.length + 1));
  return (
    new Set(q.keys()).size === [...q.keys()].length &&
    [...q].every(([k, x]) =>
      numbers.includes(k) || k === "version"
        ? /^[1-9][0-9]{0,5}$/.test(x) && Number(x) <= 100000
        : strings.includes(k) && text(x),
    )
  );
}
export function href(base: string, query: Query) {
  return (
    base +
    "?" +
    new URLSearchParams(
      Object.fromEntries(
        Object.entries(query)
          .filter(([, v]) => v !== null && v !== "")
          .map(([k, v]) => [k, String(v)]),
      ),
    )
  );
}
export function page<T>(
  v: unknown,
  row: (v: unknown) => v is T,
  base: string,
  link: (v: unknown) => boolean = (v) => localLink(v, base),
): v is Page<T> {
  return (
    record(v) &&
    Array.isArray(v.items) &&
    v.items.every(row) &&
    v.items.length <= 25 &&
    integer(v.total_count) &&
    integer(v.page) &&
    v.page >= 1 &&
    v.page <= Math.max(1, Math.ceil(v.total_count / 25)) &&
    v.page_size === 25 &&
    v.items.length === Math.min(25, Math.max(0, v.total_count - (v.page - 1) * 25)) &&
    (v.previous_href === null ? v.page === 1 : v.page > 1 && link(v.previous_href)) &&
    (v.next_href === null
      ? v.page * 25 >= v.total_count
      : v.page * 25 < v.total_count && link(v.next_href))
  );
}
export function thresholds(v: unknown): v is Thresholds {
  return (
    record(v) &&
    Object.keys(v).every((k) => fields.includes(k as (typeof fields)[number])) &&
    Object.values(v).every(
      (x) => typeof x === "number" && Number.isFinite(x) && Math.abs(x) <= Number.MAX_SAFE_INTEGER,
    )
  );
}
export function definition(v: unknown): v is Definition {
  return (
    record(v) &&
    id(v.id) &&
    name(v.point_id) &&
    name(v.limit_set_name) &&
    integer(v.version) &&
    v.version > 0 &&
    thresholds(v.thresholds)
  );
}
export function active(v: unknown): v is Active {
  return (
    record(v) &&
    id(v.definition_id) &&
    id(v.event_id) &&
    integer(v.version) &&
    v.version > 0 &&
    stamp(v.active_from) &&
    nullable(v.active_to, stamp)
  );
}
export function definitionLink(v: unknown, base: string, id: string, version: number) {
  if (!localLink(v, base)) return false;
  const q = new URLSearchParams(v.slice(base.length + 1));
  return q.get("definition") === id && q.get("version") === String(version);
}
export function definitionRow(v: unknown, base: string): v is DefinitionRow {
  return definition(v) && "href" in v && definitionLink(v.href, base, v.id, v.version);
}
function activation(v: unknown): v is Activation {
  return (
    record(v) &&
    id(v.id) &&
    id(v.definition_id) &&
    integer(v.version) &&
    v.version > 0 &&
    ["registered", "activated", "superseded", "disabled", "retired", "unknown"].includes(
      v.event_type as string,
    ) &&
    stamp(v.active_from) &&
    stamp(v.observed_at) &&
    nullable(v.active_to, stamp) &&
    [v.scope_type, v.scope_ref, v.realm].every((x) => nullable(x, text))
  );
}
export function selection(v: unknown, b: Base): v is Selection {
  if (v === null) return b.query.definition === "";
  if (!record(v) || v.id !== b.query.definition || !id(v.id) || typeof v.available !== "boolean")
    return false;
  if (!v.available) return true;
  if (
    !definition(v.current) ||
    !definition(v.inspected) ||
    v.current.id !== v.id ||
    v.inspected.id !== v.id ||
    v.current.point_id !== v.inspected.point_id ||
    v.current.limit_set_name !== v.inspected.limit_set_name ||
    v.inspected.version !== (b.query.version ?? v.current.version) ||
    v.inspected.version > v.current.version ||
    !nullable(v.active, active) ||
    !page(v.history, (x): x is DefinitionRow => definitionRow(x, b.links.self), b.links.self) ||
    !page(v.activations, activation, b.links.self)
  )
    return false;
  const c = v.current;
  return (
    v.history.items.every(
      (d, i, a) =>
        d.id === c.id &&
        d.point_id === c.point_id &&
        d.version <= c.version &&
        (i === 0 || a[i - 1].version > d.version),
    ) && new Set(v.activations.items.map((x) => x.id)).size === v.activations.items.length
  );
}
export function base(v: unknown, surface: Base["surface"], expected?: unknown): v is Base {
  if (
    !record(v) ||
    v.contract_version !== 1 ||
    v.surface !== surface ||
    !record(v.context) ||
    ![
      v.context.organization_id,
      v.context.mission_id,
      v.context.actor_id,
      v.context.installation_id,
    ].every(id) ||
    !text(v.mission_name) ||
    !record(v.query) ||
    !record(v.links)
  )
    return false;
  if (
    expected !== undefined &&
    (!record(expected) ||
      expected.scope !== "mission" ||
      expected.organizationId !== v.context.organization_id ||
      expected.missionId !== v.context.mission_id)
  )
    return false;
  const q = v.query,
    root = `/missions/${String(v.context.mission_id)}/applications/limits`;
  return (
    numbers.every((k) => integer(q[k]) && (q[k] as number) > 0 && (q[k] as number) <= 100000) &&
    strings.every((k) => text(q[k])) &&
    (q.version === null || (integer(q.version) && q.version > 0 && q.version <= 100000)) &&
    ["", "red", "yellow", "blue", "green"].includes(q.severity as string) &&
    v.links.self === `${root}/${surface}` &&
    v.links.manage === `${root}/manage` &&
    v.links.activity === `${root}/activity` &&
    v.links.applications === `/missions/${String(v.context.mission_id)}/applications`
  );
}
export const envelope = (v: unknown) =>
  Object.entries(v as Thresholds)
    .map(([k, x]) => `${k.replaceAll("_", " ")}: ${x}`)
    .join(" · ") || "No thresholds";
