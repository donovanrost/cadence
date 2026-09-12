import type {
  FleetStartModel,
  FleetStartWindow,
  FleetStartPolicy,
  FleetStartReview,
  FleetStartReceipt,
} from "./OpsFleetPlanningNew.contracts";
const object = (v: any) => v !== null && typeof v === "object" && !Array.isArray(v);
const id = (v: any) =>
  typeof v === "string" &&
  v.length > 0 &&
  new TextEncoder().encode(v).length <= 240 &&
  !/\s/u.test(v) &&
  v.split("").every((c) => c.charCodeAt(0) > 31 && c.charCodeAt(0) !== 127) &&
  encodeURIComponent(v).length > 0;
const positive = (v: any) => Number.isSafeInteger(v) && v > 0;
const nonnegative = (v: any) => Number.isSafeInteger(v) && v >= 0;
const hash = (v: any) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const time = (v: any) =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const windowValid = (v: any) =>
  object(v) &&
  time(v.horizon_start) &&
  time(v.horizon_end) &&
  Date.parse(v.horizon_start) < Date.parse(v.horizon_end) &&
  typeof v.include_recurring === "boolean";
const contextValid = (v: any, c?: FleetStartModel["context"]) =>
  object(v) &&
  id(v.organization_id) &&
  id(v.mission_id) &&
  (!c || (v.organization_id === c.organization_id && v.mission_id === c.mission_id));
function policy(v: any): v is FleetStartPolicy {
  return (
    object(v) &&
    id(v.id) &&
    positive(v.version) &&
    hash(v.content_sha256) &&
    positive(v.max_horizon_seconds) &&
    positive(v.requirement_concurrency) &&
    positive(v.provider_search_concurrency) &&
    (v.max_contacts === null || nonnegative(v.max_contacts)) &&
    (v.max_estimated_cost_micros === null || nonnegative(v.max_estimated_cost_micros)) &&
    (v.currency === null || (typeof v.currency === "string" && /^[A-Z]{3}$/.test(v.currency)))
  );
}
function snapshot(v: unknown): any {
  const text = JSON.stringify(v);
  if (new TextEncoder().encode(text).length > 60_000) throw Error("Oversized fleet evidence");
  return JSON.parse(text);
}
export function sameFleetEvidence(a: unknown, b: unknown): boolean {
  if (!object(a) || !object(b)) return false;
  const one = a as Record<string, unknown>,
    two = b as Record<string, unknown>;
  return (
    Object.keys(one).length === Object.keys(two).length &&
    Object.keys(one).every((k) => one[k] === two[k])
  );
}
export function admitFleetStart(
  input: unknown,
  context?: FleetStartModel["context"],
): FleetStartModel | null {
  try {
    const v = snapshot(input);
    if (
      !object(v) ||
      v.contract_version !== 1 ||
      !contextValid(v.context, context) ||
      !windowValid(v.defaults) ||
      (v.policy !== null && !policy(v.policy))
    )
      return null;
    return v;
  } catch {
    return null;
  }
}
function page(v: any, count: number, mapper: (row: any) => boolean): boolean {
  return (
    object(v) &&
    positive(v.page) &&
    v.page <= 1_000_000 &&
    nonnegative(v.total) &&
    v.total <= count &&
    typeof v.more === "boolean" &&
    Array.isArray(v.entries) &&
    v.entries.length === Math.max(0, Math.min(25, v.total - (v.page - 1) * 25)) &&
    v.more === v.total > v.page * 25 &&
    v.entries.every(mapper) &&
    new Set(v.entries.map((r: any) => r.id)).size === v.entries.length
  );
}
function reference(v: any) {
  return (
    object(v) && id(v.id) && positive(v.version) && hash(v.content_sha256) && id(v.spacecraft_id)
  );
}
export function admitFleetStartReview(
  input: unknown,
  model: FleetStartModel,
  window: FleetStartWindow,
  pages: { requirements_page: number; templates_page: number },
): FleetStartReview | null {
  try {
    const v = snapshot(input),
      e = v?.evidence;
    if (
      !object(v) ||
      v.contract_version !== 1 ||
      !contextValid(v.context, model.context) ||
      !windowValid(v.window) ||
      !sameFleetEvidence(v.window, window) ||
      !policy(v.policy) ||
      !model.policy ||
      !sameFleetEvidence(v.policy, model.policy)
    )
      return null;
    if (
      !object(e) ||
      e.contract_version !== 1 ||
      e.organization_id !== model.context.organization_id ||
      e.mission_id !== model.context.mission_id ||
      e.policy_id !== v.policy.id ||
      e.policy_version !== v.policy.version ||
      e.policy_sha256 !== v.policy.content_sha256 ||
      !hash(e.input_sha256) ||
      Object.keys(e).length !== 7
    )
      return null;
    if (
      !page(
        v.requirements,
        10_000,
        (r) =>
          reference(r) &&
          time(r.earliest_start) &&
          time(r.latest_end) &&
          Date.parse(r.earliest_start) < Date.parse(r.latest_end) &&
          Date.parse(r.earliest_start) < Date.parse(window.horizon_end) &&
          Date.parse(r.latest_end) > Date.parse(window.horizon_start) &&
          ["critical", "high", "routine"].includes(r.priority) &&
          ["any_contact", "minimum_duration", "minimum_data_volume", "contact_count"].includes(
            r.success_measure,
          ),
      )
    )
      return null;
    if (
      !page(
        v.templates,
        1_000,
        (t) =>
          reference(t) &&
          nonnegative(t.occurrence_count) &&
          t.occurrence_count <= 10_000 &&
          positive(t.maximum_occurrences) &&
          t.occurrence_count <= t.maximum_occurrences &&
          positive(t.maximum_lookback_seconds),
      )
    )
      return null;
    if (
      v.requirements.page !== pages.requirements_page ||
      v.templates.page !== pages.templates_page ||
      !nonnegative(v.occurrence_count) ||
      v.occurrence_count > 10_000 ||
      !nonnegative(v.eligible_occurrence_count) ||
      v.eligible_occurrence_count > v.occurrence_count
    )
      return null;
    if (!window.include_recurring && (v.templates.total !== 0 || v.occurrence_count !== 0))
      return null;
    return v;
  } catch {
    return null;
  }
}
export function fleetCompletion(v: unknown): unknown {
  if (!object(v)) throw Error("Unavailable receipt");
  const r = v as any;
  if (!id(r.receiptId) || !time(r.completedAt)) throw Error("Unavailable receipt");
  return r.result;
}
export function admitFleetStartReceipt(
  input: unknown,
  review: FleetStartReview,
): FleetStartReceipt | null {
  try {
    const r = snapshot(input);
    if (
      !object(r) ||
      r.contract_version !== 1 ||
      r.organization_id !== review.context.organization_id ||
      r.mission_id !== review.context.mission_id ||
      !id(r.fleetPlanningRunId) ||
      r.lifecycleState !== "queued" ||
      r.phase !== "queued" ||
      !positive(r.requirementCount) ||
      r.requirementCount > 10_000 ||
      !sameFleetEvidence(r.evidence, review.evidence)
    )
      return null;
    return r;
  } catch {
    return null;
  }
}
export function fleetWindow(draft: {
  horizon_start: string;
  horizon_end: string;
  include_recurring: boolean;
}): FleetStartWindow | null {
  try {
    const value = {
      horizon_start: new Date(draft.horizon_start + "Z").toISOString(),
      horizon_end: new Date(draft.horizon_end + "Z").toISOString(),
      include_recurring: draft.include_recurring,
    };
    return windowValid(value) ? value : null;
  } catch {
    return null;
  }
}
