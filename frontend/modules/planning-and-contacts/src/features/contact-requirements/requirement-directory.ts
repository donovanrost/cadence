import { arrayOf, oneOf, record, type Snapshot } from "@cadence/plugin-sdk/admission";
export { record } from "@cadence/plugin-sdk/admission";
export type RequirementDirectory = Snapshot<{
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  query: { page: number; state: "all" | "active" | "closed" | "canceled" };
  requirements: { page: number; more: boolean; entries: RequirementRow[] };
}>;
export type RequirementRow = Snapshot<{
  id: string;
  version: number;
  state: "active" | "closed" | "canceled";
  priority: "routine" | "high" | "critical";
  direction: "downlink" | "uplink" | "bidirectional" | "tracking";
  intent: string;
  earliest_start: string;
  latest_end: string;
  success_measure: "any_contact" | "minimum_duration" | "minimum_data_volume" | "contact_count";
  minimum_duration_seconds: number | null;
  minimum_data_volume_bytes: number | null;
  contact_count: number | null;
  minimum_separation_seconds: number | null;
}>;
export const requirementDataEqual = (a: unknown, b: unknown) =>
  JSON.stringify(a, canonical) === JSON.stringify(b, canonical);
function canonical(_key: string, value: unknown) {
  return record(value)
    ? Object.fromEntries(
        Object.keys(value)
          .sort()
          .map((k) => [k, value[k]]),
      )
    : value;
}
export const safeText = (v: unknown, max = 512): v is string =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  Array.from(v).every((c) => {
    const n = c.codePointAt(0);
    if (n === undefined) return false;
    return (n >= 32 || [9, 10, 13].includes(n)) && n !== 127 && !(n >= 0xd800 && n <= 0xdfff);
  });
export const safeId = (v: unknown): v is string =>
  safeText(v, 240) && v.length > 0 && !/\s/.test(v);
export const natural = (v: unknown): v is number =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
export const positive = (v: unknown): v is number => natural(v) && v > 0;
export const validTime = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
export const requirementSegment = (v: string) =>
  encodeURIComponent(v).replace(
    /[!'()*]/g,
    (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase(),
  );
export const requirementDirectoryHref = (
  d: RequirementDirectory,
  page = d.query.page,
  state = d.query.state,
) =>
  `/missions/${requirementSegment(d.context.mission_id)}/ops/requirements?page=${page}&state=${state}`;
function row(r: unknown): r is RequirementRow {
  return (
    record(r) &&
    safeId(r.id) &&
    positive(r.version) &&
    oneOf(["active", "closed", "canceled"], r.state) &&
    oneOf(["routine", "high", "critical"], r.priority) &&
    oneOf(["downlink", "uplink", "bidirectional", "tracking"], r.direction) &&
    safeText(r.intent) &&
    validTime(r.earliest_start) &&
    validTime(r.latest_end) &&
    Date.parse(r.earliest_start) < Date.parse(r.latest_end) &&
    oneOf(
      ["any_contact", "minimum_duration", "minimum_data_volume", "contact_count"],
      r.success_measure,
    ) &&
    [
      "minimum_duration_seconds",
      "minimum_data_volume_bytes",
      "contact_count",
      "minimum_separation_seconds",
    ].every((k) => r[k] === null || natural(r[k])) &&
    (r.success_measure !== "minimum_duration" || positive(r.minimum_duration_seconds)) &&
    (r.success_measure !== "minimum_data_volume" || positive(r.minimum_data_volume_bytes)) &&
    (r.success_measure !== "contact_count" ||
      (positive(r.contact_count) && natural(r.minimum_separation_seconds)))
  );
}
export function admitRequirementDirectory(
  value: unknown,
  context?: RequirementDirectory["context"],
  query?: RequirementDirectory["query"],
): RequirementDirectory | null {
  try {
    const serialized = JSON.stringify(value);
    if (new TextEncoder().encode(serialized).length > 131072) return null;
    const v: unknown = JSON.parse(serialized);
    return validDirectory(v, context, query) ? v : null;
  } catch {
    return null;
  }
}

function validDirectory(
  v: unknown,
  context?: RequirementDirectory["context"],
  query?: RequirementDirectory["query"],
): v is RequirementDirectory {
  if (
    !record(v) ||
    v.contract_version !== 1 ||
    !record(v.context) ||
    !safeId(v.context.organization_id) ||
    !safeId(v.context.mission_id) ||
    (context && !requirementDataEqual(context, v.context)) ||
    !record(v.query) ||
    Object.keys(v.query).length !== 2 ||
    !positive(v.query.page) ||
    v.query.page > 1000000 ||
    !oneOf(["all", "active", "closed", "canceled"], v.query.state) ||
    (query && !requirementDataEqual(query, v.query)) ||
    !record(v.requirements)
  )
    return false;
  const p = v.requirements;
  const state = v.query.state;
  if (
    p.page !== v.query.page ||
    typeof p.more !== "boolean" ||
    !arrayOf(p.entries, row) ||
    p.entries.length > 25 ||
    (p.more && p.entries.length !== 25) ||
    new Set(p.entries.map((r) => r.id)).size !== p.entries.length ||
    (v.query.state !== "all" && p.entries.some((r) => r.state !== state))
  )
    return false;
  return true;
}
