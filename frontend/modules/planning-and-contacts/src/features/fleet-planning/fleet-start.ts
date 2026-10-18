import { record as object, oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
import type {
  FleetStartModel,
  FleetStartWindow,
  FleetStartPolicy,
  FleetStartReview,
  FleetStartReceipt,
  FleetStartPage,
} from "./OpsFleetPlanningNew.contracts";
const id = (v: unknown): v is string =>
  typeof v === "string" &&
  v.length > 0 &&
  new TextEncoder().encode(v).length <= 240 &&
  !/\s/u.test(v) &&
  v.split("").every((c) => c.charCodeAt(0) > 31 && c.charCodeAt(0) !== 127) &&
  encodeURIComponent(v).length > 0;
const positive = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) > 0;
const nonnegative = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const hash = (v: unknown): v is string => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
export const windowValid = (v: unknown): v is FleetStartWindow =>
  object(v) &&
  time(v.horizon_start) &&
  time(v.horizon_end) &&
  Date.parse(v.horizon_start) < Date.parse(v.horizon_end) &&
  typeof v.include_recurring === "boolean";
const contextValid = (
  v: unknown,
  c?: FleetStartModel["context"],
): v is FleetStartModel["context"] =>
  object(v) &&
  id(v.organization_id) &&
  id(v.mission_id) &&
  (!c || (v.organization_id === c.organization_id && v.mission_id === c.mission_id));
function policy(v: unknown): v is FleetStartPolicy {
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
function snapshot(v: unknown): unknown {
  const text = JSON.stringify(v);
  if (new TextEncoder().encode(text).length > 60_000) throw Error("Oversized fleet evidence");
  return JSON.parse(text);
}
export function sameFleetEvidence(a: unknown, b: unknown): boolean {
  if (!object(a) || !object(b)) return false;
  const one = a,
    two = b;
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
    const value = snapshot(input);
    return validFleetStart(value, context) ? value : null;
  } catch {
    return null;
  }
}
function validFleetStart(v: unknown, context?: FleetStartModel["context"]): v is FleetStartModel {
  if (
    !object(v) ||
    v.contract_version !== 1 ||
    !contextValid(v.context, context) ||
    !windowValid(v.defaults) ||
    (v.policy !== null && !policy(v.policy))
  )
    return false;
  return true;
}
function page<T extends { id: string }>(
  v: unknown,
  count: number,
  mapper: Guard<T>,
): v is FleetStartPage<T> {
  return (
    object(v) &&
    positive(v.page) &&
    v.page <= 1_000_000 &&
    nonnegative(v.total) &&
    v.total <= count &&
    typeof v.more === "boolean" &&
    arrayOf(v.entries, mapper) &&
    v.entries.length === Math.max(0, Math.min(25, v.total - (v.page - 1) * 25)) &&
    v.more === v.total > v.page * 25 &&
    new Set(v.entries.map((r) => r.id)).size === v.entries.length
  );
}
type Reference = Pick<
  FleetStartReview["requirements"]["entries"][number],
  "id" | "version" | "content_sha256" | "spacecraft_id"
>;
function reference(v: unknown): v is Reference & Record<string, unknown> {
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
    const value = snapshot(input);
    return validFleetStartReview(value, model, window, pages) ? value : null;
  } catch {
    return null;
  }
}
function validFleetStartReview(
  v: unknown,
  model: FleetStartModel,
  window: FleetStartWindow,
  pages: { requirements_page: number; templates_page: number },
): v is FleetStartReview {
  if (!object(v)) return false;
  const e = v.evidence;
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
    return false;
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
    return false;
  if (
    !page(
      v.requirements,
      10_000,
      (r): r is FleetStartReview["requirements"]["entries"][number] =>
        reference(r) &&
        time(r.earliest_start) &&
        time(r.latest_end) &&
        Date.parse(r.earliest_start) < Date.parse(r.latest_end) &&
        Date.parse(r.earliest_start) < Date.parse(window.horizon_end) &&
        Date.parse(r.latest_end) > Date.parse(window.horizon_start) &&
        oneOf(["critical", "high", "routine"], r.priority) &&
        oneOf(
          ["any_contact", "minimum_duration", "minimum_data_volume", "contact_count"],
          r.success_measure,
        ),
    )
  )
    return false;
  if (
    !page(
      v.templates,
      1_000,
      (t): t is FleetStartReview["templates"]["entries"][number] =>
        reference(t) &&
        nonnegative(t.occurrence_count) &&
        t.occurrence_count <= 10_000 &&
        positive(t.maximum_occurrences) &&
        t.occurrence_count <= t.maximum_occurrences &&
        positive(t.maximum_lookback_seconds),
    )
  )
    return false;
  if (
    v.requirements.page !== pages.requirements_page ||
    v.templates.page !== pages.templates_page ||
    !nonnegative(v.occurrence_count) ||
    v.occurrence_count > 10_000 ||
    !nonnegative(v.eligible_occurrence_count) ||
    v.eligible_occurrence_count > v.occurrence_count
  )
    return false;
  if (!window.include_recurring && (v.templates.total !== 0 || v.occurrence_count !== 0))
    return false;
  return true;
}
export function fleetCompletion(v: unknown): unknown {
  if (!object(v)) throw Error("Unavailable receipt");
  const r = v;
  if (!id(r.receiptId) || !time(r.completedAt)) throw Error("Unavailable receipt");
  return r.result;
}
export function admitFleetStartReceipt(
  input: unknown,
  review: FleetStartReview,
): FleetStartReceipt | null {
  try {
    const value = snapshot(input);
    return validFleetStartReceipt(value, review) ? value : null;
  } catch {
    return null;
  }
}
function validFleetStartReceipt(r: unknown, review: FleetStartReview): r is FleetStartReceipt {
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
    return false;
  return true;
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
