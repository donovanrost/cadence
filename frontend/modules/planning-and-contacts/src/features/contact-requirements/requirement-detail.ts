import { record, oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
import type {
  RequirementDetail,
  ResultPage,
  Run,
  Version,
  Search,
  Opportunity,
  PageKey,
  PlanInput,
} from "./OpsContactRequirementShow.contracts";

const bytes = (s: string) => new TextEncoder().encode(s).length;
const text = (v: unknown, max = 512): v is string => typeof v === "string" && bytes(v) <= max;
export const identifier = (v: unknown): v is string =>
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  text(v, 240) && v.length > 0 && !/[\x00-\x20\x7f]/.test(v);
const integer = (v: unknown, max = Number.MAX_SAFE_INTEGER): v is number =>
  typeof v === "number" && Number.isSafeInteger(v) && v > 0 && v <= max;
const hash = (v: unknown) => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
const time = (v: unknown): v is string =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const run = (v: unknown): v is Run =>
  record(v) &&
  identifier(v.id) &&
  integer(v.version) &&
  oneOf(["running", "completed", "partial", "failed"], v.state) &&
  time(v.started_at);
const page = <T extends { readonly id: string }>(v: unknown, check: Guard<T>): v is ResultPage<T> =>
  record(v) &&
  integer(v.page, 1_000_000) &&
  typeof v.more === "boolean" &&
  arrayOf(v.entries, check) &&
  v.entries.length <= 25 &&
  (!v.more || v.entries.length === 25) &&
  new Set(v.entries.map((r) => r.id)).size === v.entries.length;

export function admitRequirementDetail(value: unknown): RequirementDetail | null {
  try {
    return validRequirementDetail(value) ? value : null;
  } catch {
    return null;
  }
}
function validRequirementDetail(value: unknown): value is RequirementDetail {
  try {
    if (!record(value) || bytes(JSON.stringify(value)) > 60_000 || value.contract_version !== 1)
      return false;
    const { context: c, requirement: r, query: q, selected_run: selected } = value;
    if (
      !record(c) ||
      !identifier(c.organization_id) ||
      !identifier(c.mission_id) ||
      !(c.actor_id === null || identifier(c.actor_id))
    )
      return false;
    if (
      !record(r) ||
      !identifier(r.id) ||
      !integer(r.version) ||
      !integer(r.current_version) ||
      r.version > r.current_version ||
      !hash(r.content_sha256)
    )
      return false;
    if (
      !oneOf(["active", "closed", "canceled"], r.lifecycle_state) ||
      !oneOf(["downlink", "uplink", "bidirectional", "tracking"], r.direction) ||
      !oneOf(["routine", "high", "critical"], r.priority)
    )
      return false;
    if (
      !text(r.intent) ||
      !text(r.outcome) ||
      !text(r.rationale, 4096) ||
      !time(r.earliest_start) ||
      !time(r.latest_end) ||
      Date.parse(r.earliest_start) >= Date.parse(r.latest_end)
    )
      return false;
    if (!record(q) || q.contact_requirement_id !== r.id || q.version !== r.version) return false;
    if (selected !== null && (!run(selected) || selected.version !== r.version)) return false;
    if (q.planning_run_id !== (selected?.id ?? null)) return false;
    const version = r.version,
      currentVersion = r.current_version;
    if (
      !page(
        value.versions,
        (v): v is Version =>
          record(v) &&
          identifier(v.id) &&
          integer(v.version) &&
          v.version <= version &&
          hash(v.content_sha256) &&
          time(v.created_at),
      )
    )
      return false;
    if (
      new Set(value.versions.entries.map((v) => v.version)).size !== value.versions.entries.length
    )
      return false;
    if (!page(value.runs, (v): v is Run => run(v) && v.version <= currentVersion)) return false;
    if (
      !page(
        value.searches,
        (s): s is Search =>
          record(s) &&
          identifier(s.id) &&
          text(s.route_key) &&
          text(s.provider) &&
          oneOf(
            [
              "succeeded_with_results",
              "succeeded_without_results",
              "not_ready",
              "excluded_by_requirement",
              "failed",
            ],
            s.outcome,
          ) &&
          typeof s.opportunity_count === "number" &&
          Number.isSafeInteger(s.opportunity_count) &&
          s.opportunity_count >= 0 &&
          hash(s.content_sha256),
      )
    )
      return false;
    if (
      !page(
        value.opportunities,
        (o): o is Opportunity =>
          record(o) &&
          identifier(o.id) &&
          o.run_id === selected?.id &&
          o.requirement_id === r.id &&
          o.version === r.version &&
          text(o.provider) &&
          text(o.station) &&
          time(o.starts_at) &&
          time(o.ends_at) &&
          time(o.expires_at) &&
          Date.parse(o.starts_at) < Date.parse(o.ends_at) &&
          oneOf(["available", "limited", "unavailable"], o.availability) &&
          typeof o.eligible === "boolean" &&
          typeof o.synthetic === "boolean" &&
          hash(o.content_sha256),
      )
    )
      return false;
    for (const [key, collection] of Object.entries({
      versions_page: value.versions,
      runs_page: value.runs,
      searches_page: value.searches,
      opportunities_page: value.opportunities,
    })) {
      if (!integer(q[key], 1_000_000) || q[key] !== collection.page) return false;
    }
    if (
      !selected &&
      (value.searches.entries.length ||
        value.opportunities.entries.length ||
        value.searches.more ||
        value.opportunities.more ||
        q.searches_page !== 1 ||
        q.opportunities_page !== 1)
    )
      return false;
    return true;
  } catch {
    return false;
  }
}

export function decision(d: RequirementDetail): PlanInput {
  return {
    contact_requirement_id: d.requirement.id,
    requirement_evidence: {
      contract_version: 1,
      organization_id: d.context.organization_id,
      mission_id: d.context.mission_id,
      requirement_id: d.requirement.id,
      requirement_version: d.requirement.version,
      content_sha256: d.requirement.content_sha256,
    },
  };
}
export const canPlan = (d: RequirementDetail) =>
  !!d.context.actor_id &&
  d.requirement.lifecycle_state === "active" &&
  d.requirement.version === d.requirement.current_version &&
  d.requirement.direction === "downlink";
export const canCreate = (d: RequirementDetail) =>
  canPlan(d) && !!d.selected_run && d.selected_run.state !== "running";
export const detailPath = (d: RequirementDetail) =>
  `/missions/${encodeURIComponent(d.context.mission_id)}/ops/requirements/${encodeURIComponent(d.requirement.id)}`;
export function detailHref(
  d: RequirementDetail,
  changes: Partial<RequirementDetail["query"]> = {},
) {
  const q = { ...d.query, ...changes },
    params = new URLSearchParams();
  for (const key of [
    "version",
    "planning_run_id",
    "versions_page",
    "runs_page",
    "searches_page",
    "opportunities_page",
  ] as const) {
    if (q[key] !== null) params.set(key, String(q[key]));
  }
  return detailPath(d) + "?" + params.toString();
}
export const pageHref = (d: RequirementDetail, key: PageKey, n: number) =>
  detailHref(d, { [key]: n });
export const reviewHref = (d: RequirementDetail, version: number, runId: string | null = null) =>
  detailHref(d, {
    version,
    planning_run_id: runId,
    versions_page: 1,
    runs_page: 1,
    searches_page: 1,
    opportunities_page: 1,
  });
