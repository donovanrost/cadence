import type {
  FleetRunModel,
  FleetRunReceipt,
  RunContext,
  RunQuery,
} from "./OpsFleetPlanningRun.contracts";
import { admitFleetStart, sameFleetEvidence } from "./fleet-start";
const object = (v: any) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v: any, max = 240) =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  v.split("").every((c) => c.charCodeAt(0) > 31 && c.charCodeAt(0) !== 127) &&
  encodeURIComponent(v).length >= 0;
const id = (v: any) =>
  text(v) && v.length > 0 && !/\s/u.test(v) && encodeURIComponent(v).length > 0;
const hash = (v: any) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const positive = (v: any) => Number.isSafeInteger(v) && v > 0;
const nonnegative = (v: any) => Number.isSafeInteger(v) && v >= 0;
const time = (v: any) =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const optional = (v: any, check: (v: any) => boolean) => v === null || check(v);
const range = (a: any, b: any) => time(a) && time(b) && Date.parse(a) < Date.parse(b);
const states = ["queued", "running", "completed", "partial", "failed", "canceled"];
const phases = [
  "queued",
  "materializing",
  "searching",
  "optimizing",
  "materializing_plan",
  "finished",
];
export const runQueryKeys = [
  "requirements_page",
  "decisions_page",
  "resources_page",
  "automation_page",
  "commitments_page",
] as const;
function page(v: any, expected: number, row: (v: any) => boolean, key = "id") {
  return (
    object(v) &&
    v.page === expected &&
    typeof v.more === "boolean" &&
    Array.isArray(v.entries) &&
    v.entries.length <= 10 &&
    (!v.more || v.entries.length === 10) &&
    v.entries.every(row) &&
    new Set(v.entries.map((r: any) => r[key])).size === v.entries.length &&
    (v.total === undefined ||
      (nonnegative(v.total) &&
        v.entries.length === Math.max(0, Math.min(10, v.total - (v.page - 1) * 10)) &&
        v.more === v.total > v.page * 10))
  );
}
function snapshot(input: unknown) {
  const v = JSON.stringify(input);
  if (new TextEncoder().encode(v).length > 60000) throw Error("Oversized fleet run");
  return JSON.parse(v);
}
function context(v: any, expected?: RunContext) {
  return (
    object(v) &&
    id(v.organization_id) &&
    id(v.mission_id) &&
    (!expected ||
      (v.organization_id === expected.organization_id && v.mission_id === expected.mission_id))
  );
}
function policy(v: any, model: any) {
  return (
    object(v) &&
    !!admitFleetStart({
      contract_version: 1,
      context: model.context,
      policy: v,
      defaults: {
        horizon_start: model.horizon_start,
        horizon_end: model.horizon_end,
        include_recurring: false,
      },
    })
  );
}
function repair(r: any, m: any) {
  if (!object(r) || typeof r.available !== "boolean" || !optional(r.reason, (v) => text(v, 120)))
    return false;
  if (!r.evidence) return r.available === false && typeof r.reason === "string";
  const e = r.evidence;
  return (
    object(e) &&
    Object.keys(e).length === 12 &&
    e.contract_version === 1 &&
    e.organization_id === m.context.organization_id &&
    e.mission_id === m.context.mission_id &&
    e.run_id === m.id &&
    e.run_sha256 === m.evidence.sha256 &&
    hash(e.sha256) &&
    id(e.plan_id) &&
    positive(e.plan_version) &&
    hash(e.plan_sha256) &&
    object(m.candidate) &&
    e.plan_id === m.candidate.id &&
    e.plan_version === m.candidate.version &&
    e.plan_sha256 === m.candidate.content_sha256 &&
    object(r.plan) &&
    r.plan.id === e.plan_id &&
    r.plan.version === e.plan_version &&
    ["executing", "partially_reserved", "failed"].includes(r.plan.lifecycle_state) &&
    policy(r.policy, m) &&
    e.policy_id === r.policy.id &&
    e.policy_version === r.policy.version &&
    e.policy_sha256 === r.policy.content_sha256 &&
    positive(r.policy.max_repair_horizon_seconds) &&
    r.policy.max_repair_horizon_seconds <= r.policy.max_horizon_seconds &&
    nonnegative(r.policy.max_attempts) &&
    positive(r.attempt) &&
    r.available === r.attempt <= r.policy.max_attempts &&
    object(r.defaults) &&
    range(r.defaults.horizon_start, r.defaults.horizon_end) &&
    Date.parse(r.defaults.horizon_end) - Date.parse(r.defaults.horizon_start) <=
      r.policy.max_repair_horizon_seconds * 1000 &&
    nonnegative(r.commitments?.total) &&
    r.commitments.total <= 10000 &&
    page(
      r.commitments,
      m.query.commitments_page,
      (c) =>
        object(c) &&
        id(c.id) &&
        hash(c.content_sha256) &&
        id(c.spacecraft_id) &&
        range(c.starts_at, c.ends_at),
    )
  );
}
export function admitFleetRun(
  input: unknown,
  expected?: RunContext,
  identity?: { id: string; query: RunQuery },
): FleetRunModel | null {
  try {
    const m = snapshot(input),
      e = m?.evidence;
    if (
      !object(m) ||
      m.contract_version !== 1 ||
      !context(m.context, expected) ||
      !id(m.id) ||
      !states.includes(m.lifecycle_state) ||
      !phases.includes(m.phase) ||
      !["manual", "scheduled", "repair"].includes(m.trigger_kind) ||
      !object(m.algorithm) ||
      !id(m.algorithm.key) ||
      !positive(m.algorithm.version) ||
      !range(m.horizon_start, m.horizon_end) ||
      !time(m.inserted_at) ||
      !optional(m.started_at, time) ||
      !optional(m.completed_at, time) ||
      !policy(m.policy, m)
    )
      return null;
    if (
      !object(m.query) ||
      Object.keys(m.query).length !== 5 ||
      !runQueryKeys.every((k) => positive(m.query[k]) && m.query[k] <= 1000000) ||
      (identity && (m.id !== identity.id || !sameFleetEvidence(m.query, identity.query)))
    )
      return null;
    if (
      !object(e) ||
      Object.keys(e).length !== 7 ||
      e.contract_version !== 1 ||
      e.organization_id !== m.context.organization_id ||
      e.mission_id !== m.context.mission_id ||
      e.run_id !== m.id ||
      e.lifecycle_state !== m.lifecycle_state ||
      e.phase !== m.phase ||
      !hash(e.sha256) ||
      m.can_continue !==
        (["queued", "running"].includes(m.lifecycle_state) && m.phase !== "finished")
    )
      return null;
    if (
      !optional(
        m.candidate,
        (c) =>
          object(c) &&
          id(c.id) &&
          positive(c.version) &&
          hash(c.content_sha256) &&
          [
            "draft",
            "pending_approval",
            "approved",
            "executing",
            "partially_reserved",
            "reserved",
            "failed",
            "canceled",
            "superseded",
          ].includes(c.lifecycle_state) &&
          positive(c.current_version) &&
          c.current_version >= c.version,
      ) ||
      !optional(
        m.source,
        (s) => object(s) && id(s.run_id) && id(s.plan_id) && positive(s.plan_version),
      )
    )
      return null;
    if (
      !positive(m.requirements?.total) ||
      m.requirements.total > 10000 ||
      !page(
        m.requirements,
        m.query.requirements_page,
        (r) =>
          object(r) &&
          id(r.id) &&
          id(r.requirement_id) &&
          positive(r.version) &&
          hash(r.content_sha256) &&
          id(r.spacecraft_id) &&
          range(r.earliest_start, r.latest_end) &&
          ["pending", "searching", "searched", "failed"].includes(r.input_state) &&
          ["pending", "satisfied", "partial", "unsatisfied", "failed"].includes(r.result_state) &&
          optional(r.planning_run_id, id) &&
          ["critical", "high", "routine"].includes(r.priority),
      )
    )
      return null;
    if (
      !page(
        m.decisions,
        m.query.decisions_page,
        (d) =>
          object(d) &&
          id(d.id) &&
          id(d.snapshot_id) &&
          id(d.spacecraft_id) &&
          range(d.starts_at, d.ends_at) &&
          ["selected", "displaced", "ineligible", "locked"].includes(d.disposition) &&
          Number.isSafeInteger(d.score) &&
          optional(d.rank, positive) &&
          optional(d.code, (v) => text(v, 320)) &&
          optional(d.rationale, (v) => text(v, 1600)) &&
          typeof d.constraints_satisfied === "boolean" &&
          Array.isArray(d.failures) &&
          d.failures.length <= 8 &&
          d.failures.every((v: any) => optional(v, (x) => text(x, 320))),
      )
    )
      return null;
    if (
      !nonnegative(m.resources?.total) ||
      m.resources.total > 10000 ||
      !page(
        m.resources,
        m.query.resources_page,
        (r) =>
          object(r) &&
          text(r.key, 4096) &&
          r.key.length > 0 &&
          nonnegative(r.peak_parallel) &&
          positive(r.capacity) &&
          nonnegative(r.selected_count) &&
          r.over_capacity === r.peak_parallel > r.capacity,
        "key",
      )
    )
      return null;
    if (
      !page(
        m.automation,
        m.query.automation_page,
        (a) =>
          object(a) &&
          id(a.id) &&
          ["plan", "repair", "submit", "approve", "execute"].includes(a.action) &&
          ["running", "succeeded", "failed", "skipped"].includes(a.lifecycle_state) &&
          positive(a.attempt_count) &&
          id(a.grant_id) &&
          id(a.service_identity_id) &&
          optional(a.plan_id, id) &&
          optional(a.plan_version, positive) &&
          (a.plan_id === null) === (a.plan_version === null) &&
          time(a.started_at) &&
          optional(a.completed_at, time),
      )
    )
      return null;
    if (
      !optional(m.failure, (f) => object(f) && optional(f.code, (v) => text(v, 320))) ||
      !repair(m.repair, m)
    )
      return null;
    return m;
  } catch {
    return null;
  }
}
export function fleetRunReceipt(
  input: unknown,
  model: FleetRunModel,
  action: "continue" | "repair",
): FleetRunReceipt | null {
  try {
    const r = snapshot(input),
      e = action === "continue" ? model.evidence : model.repair.evidence;
    if (
      !object(r) ||
      r.contract_version !== 1 ||
      r.organization_id !== model.context.organization_id ||
      r.mission_id !== model.context.mission_id ||
      !id(r.fleetPlanningRunId) ||
      !sameFleetEvidence(r.evidence, e)
    )
      return null;
    if (
      action === "continue"
        ? r.outcome !== "continued" ||
          r.fleetPlanningRunId !== model.id ||
          r.phase !== "finished" ||
          !["completed", "partial", "failed", "canceled"].includes(r.lifecycleState)
        : r.outcome !== "repair_created" ||
          r.fleetPlanningRunId === model.id ||
          r.phase !== "queued" ||
          r.lifecycleState !== "queued"
    )
      return null;
    return r;
  } catch {
    return null;
  }
}
export function fleetRunPage(model: FleetRunModel, key: keyof RunQuery, page: number) {
  const params = new URLSearchParams();
  for (const k of runQueryKeys) {
    const v = k === key ? page : model.query[k];
    if (v > 1) params.set(k, String(v));
  }
  const base = `/missions/${encodeURIComponent(model.context.mission_id)}/ops/planning/runs/${encodeURIComponent(model.id)}`;
  return `${base}${params.size ? `?${params}` : ""}`;
}
