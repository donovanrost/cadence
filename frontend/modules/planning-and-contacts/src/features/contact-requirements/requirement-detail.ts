import type {
  RequirementDetail,
  ResultPage,
  Run,
  PageKey,
  PlanInput,
} from "./OpsContactRequirementShow.contracts";

const record = (v: unknown): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const bytes = (s: string) => new TextEncoder().encode(s).length;
const text = (v: unknown, max = 512): v is string => typeof v === "string" && bytes(v) <= max;
export const identifier = (v: unknown): v is string =>
  text(v, 240) && v.length > 0 && !/[\x00-\x20\x7f]/.test(v);
const integer = (v: unknown, max = Number.MAX_SAFE_INTEGER): v is number =>
  Number.isSafeInteger(v) && (v as number) > 0 && (v as number) <= max;
const hash = (v: unknown) => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
const time = (v: unknown): v is string =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const run = (v: unknown): v is Run =>
  record(v) &&
  identifier(v.id) &&
  integer(v.version) &&
  ["running", "completed", "partial", "failed"].includes(v.state) &&
  time(v.started_at);
const page = <T>(v: unknown, check: (r: any) => boolean): v is ResultPage<T> =>
  record(v) &&
  integer(v.page, 1_000_000) &&
  typeof v.more === "boolean" &&
  Array.isArray(v.entries) &&
  v.entries.length <= 25 &&
  (!v.more || v.entries.length === 25) &&
  v.entries.every(check) &&
  new Set(v.entries.map((r) => r.id)).size === v.entries.length;

export function admitRequirementDetail(value: unknown): RequirementDetail | null {
  try {
    if (!record(value) || bytes(JSON.stringify(value)) > 60_000 || value.contract_version !== 1)
      return null;
    const { context: c, requirement: r, query: q, selected_run: selected } = value;
    if (
      !record(c) ||
      !identifier(c.organization_id) ||
      !identifier(c.mission_id) ||
      !(c.actor_id === null || identifier(c.actor_id))
    )
      return null;
    if (
      !record(r) ||
      !identifier(r.id) ||
      !integer(r.version) ||
      !integer(r.current_version) ||
      r.version > r.current_version ||
      !hash(r.content_sha256)
    )
      return null;
    if (
      !["active", "closed", "canceled"].includes(r.lifecycle_state) ||
      !["downlink", "uplink", "bidirectional", "tracking"].includes(r.direction) ||
      !["routine", "high", "critical"].includes(r.priority)
    )
      return null;
    if (
      !text(r.intent) ||
      !text(r.outcome) ||
      !text(r.rationale, 4096) ||
      !time(r.earliest_start) ||
      !time(r.latest_end) ||
      Date.parse(r.earliest_start) >= Date.parse(r.latest_end)
    )
      return null;
    if (!record(q) || q.contact_requirement_id !== r.id || q.version !== r.version) return null;
    if (selected !== null && (!run(selected) || selected.version !== r.version)) return null;
    if (q.planning_run_id !== (selected?.id ?? null)) return null;
    if (
      !page(
        value.versions,
        (v) =>
          record(v) &&
          identifier(v.id) &&
          integer(v.version) &&
          v.version <= r.version &&
          hash(v.content_sha256) &&
          time(v.created_at),
      )
    )
      return null;
    if (
      new Set(value.versions.entries.map((v: any) => v.version)).size !==
      value.versions.entries.length
    )
      return null;
    if (!page(value.runs, (v) => run(v) && v.version <= r.current_version)) return null;
    if (
      !page(
        value.searches,
        (s) =>
          record(s) &&
          identifier(s.id) &&
          text(s.route_key) &&
          text(s.provider) &&
          [
            "succeeded_with_results",
            "succeeded_without_results",
            "not_ready",
            "excluded_by_requirement",
            "failed",
          ].includes(s.outcome) &&
          Number.isSafeInteger(s.opportunity_count) &&
          s.opportunity_count >= 0 &&
          hash(s.content_sha256),
      )
    )
      return null;
    if (
      !page(
        value.opportunities,
        (o) =>
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
          ["available", "limited", "unavailable"].includes(o.availability) &&
          typeof o.eligible === "boolean" &&
          typeof o.synthetic === "boolean" &&
          hash(o.content_sha256),
      )
    )
      return null;
    for (const [key, collection] of Object.entries({
      versions_page: value.versions,
      runs_page: value.runs,
      searches_page: value.searches,
      opportunities_page: value.opportunities,
    })) {
      if (!integer(q[key], 1_000_000) || q[key] !== collection.page) return null;
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
      return null;
    return value as RequirementDetail;
  } catch {
    return null;
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
