import type { FleetStartPolicy } from "./OpsFleetPlanningNew.contracts";
import { record as object, oneOf, arrayOf } from "@cadence/plugin-sdk/admission";
import type {
  FleetRunModel,
  FleetRunReceipt,
  RunContext,
  RunQuery,
  RunPage,
} from "./OpsFleetPlanningRun.contracts";
import { admitFleetStart, sameFleetEvidence } from "./fleet-start";
const text = (v: unknown, max = 240): v is string =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  v.split("").every((c) => c.charCodeAt(0) > 31 && c.charCodeAt(0) !== 127) &&
  encodeURIComponent(v).length >= 0;
const id = (v: unknown): v is string =>
  text(v) && v.length > 0 && !/\s/u.test(v) && encodeURIComponent(v).length > 0;
const hash = (v: unknown): v is string => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const positive = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) > 0;
const nonnegative = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const optional = (v: unknown, check: (v: unknown) => boolean) => v === null || check(v);
const range = (a: unknown, b: unknown) => time(a) && time(b) && Date.parse(a) < Date.parse(b);
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
function page(
  v: unknown,
  expected: number,
  row: (v: unknown) => boolean,
  key = "id",
): v is RunPage<Record<string, unknown>> {
  return (
    object(v) &&
    v.page === expected &&
    positive(v.page) &&
    typeof v.more === "boolean" &&
    arrayOf(v.entries, object) &&
    v.entries.length <= 10 &&
    (!v.more || v.entries.length === 10) &&
    v.entries.every(row) &&
    new Set(v.entries.map((r) => r[key])).size === v.entries.length &&
    (v.total === undefined ||
      (nonnegative(v.total) &&
        v.entries.length === Math.max(0, Math.min(10, v.total - (v.page - 1) * 10)) &&
        v.more === v.total > v.page * 10))
  );
}
function query(v: unknown): v is RunQuery {
  return (
    object(v) &&
    Object.keys(v).length === 5 &&
    runQueryKeys.every((k) => positive(v[k]) && v[k] <= 1000000)
  );
}
function snapshot(input: unknown): unknown {
  const v = JSON.stringify(input);
  if (new TextEncoder().encode(v).length > 60000) throw Error("Oversized fleet run");
  return JSON.parse(v);
}
function context(v: unknown, expected?: RunContext): v is RunContext {
  return (
    object(v) &&
    id(v.organization_id) &&
    id(v.mission_id) &&
    (!expected ||
      (v.organization_id === expected.organization_id && v.mission_id === expected.mission_id))
  );
}
function policy(
  v: unknown,
  model: Record<string, unknown>,
): v is FleetStartPolicy & Record<string, unknown> {
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
function repair(r: unknown, m: Record<string, unknown>) {
  if (
    !object(m.context) ||
    !object(m.evidence) ||
    !object(m.query) ||
    !positive(m.query.commitments_page)
  )
    return false;
  if (!object(r) || typeof r.available !== "boolean" || !optional(r.reason, (v) => text(v, 120)))
    return false;
  if (r.evidence === undefined || r.evidence === null)
    return r.available === false && typeof r.reason === "string";
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
    oneOf(["executing", "partially_reserved", "failed"], r.plan.lifecycle_state) &&
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
    time(r.defaults.horizon_start) &&
    time(r.defaults.horizon_end) &&
    Date.parse(r.defaults.horizon_end) - Date.parse(r.defaults.horizon_start) <=
      r.policy.max_repair_horizon_seconds * 1000 &&
    object(r.commitments) &&
    nonnegative(r.commitments.total) &&
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
    const value = snapshot(input);
    return validFleetRun(value, expected, identity) ? value : null;
  } catch {
    return null;
  }
}
function validFleetRun(
  m: unknown,
  expected?: RunContext,
  identity?: { id: string; query: RunQuery },
): m is FleetRunModel {
  if (!object(m)) return false;
  const e = m.evidence;
  if (
    !object(m) ||
    m.contract_version !== 1 ||
    !context(m.context, expected) ||
    !id(m.id) ||
    !oneOf(states, m.lifecycle_state) ||
    !oneOf(phases, m.phase) ||
    !oneOf(["manual", "scheduled", "repair"], m.trigger_kind) ||
    !object(m.algorithm) ||
    !id(m.algorithm.key) ||
    !positive(m.algorithm.version) ||
    !range(m.horizon_start, m.horizon_end) ||
    !time(m.inserted_at) ||
    !optional(m.started_at, time) ||
    !optional(m.completed_at, time) ||
    !policy(m.policy, m)
  )
    return false;
  if (
    !query(m.query) ||
    (identity && (m.id !== identity.id || !sameFleetEvidence(m.query, identity.query)))
  )
    return false;
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
    m.can_continue !== (oneOf(["queued", "running"], m.lifecycle_state) && m.phase !== "finished")
  )
    return false;
  if (
    !optional(
      m.candidate,
      (c) =>
        object(c) &&
        id(c.id) &&
        positive(c.version) &&
        hash(c.content_sha256) &&
        oneOf(
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
          ],
          c.lifecycle_state,
        ) &&
        positive(c.current_version) &&
        c.current_version >= c.version,
    ) ||
    !optional(
      m.source,
      (s) => object(s) && id(s.run_id) && id(s.plan_id) && positive(s.plan_version),
    )
  )
    return false;
  if (
    !object(m.requirements) ||
    !positive(m.requirements.total) ||
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
        oneOf(["pending", "searching", "searched", "failed"], r.input_state) &&
        oneOf(["pending", "satisfied", "partial", "unsatisfied", "failed"], r.result_state) &&
        optional(r.planning_run_id, id) &&
        oneOf(["critical", "high", "routine"], r.priority),
    )
  )
    return false;
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
        oneOf(["selected", "displaced", "ineligible", "locked"], d.disposition) &&
        Number.isSafeInteger(d.score) &&
        optional(d.rank, positive) &&
        optional(d.code, (v) => text(v, 320)) &&
        optional(d.rationale, (v) => text(v, 1600)) &&
        typeof d.constraints_satisfied === "boolean" &&
        Array.isArray(d.failures) &&
        d.failures.length <= 8 &&
        d.failures.every((v: unknown) => optional(v, (x) => text(x, 320))),
    )
  )
    return false;
  if (
    !object(m.resources) ||
    !nonnegative(m.resources.total) ||
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
    return false;
  if (
    !page(
      m.automation,
      m.query.automation_page,
      (a) =>
        object(a) &&
        id(a.id) &&
        oneOf(["plan", "repair", "submit", "approve", "execute"], a.action) &&
        oneOf(["running", "succeeded", "failed", "skipped"], a.lifecycle_state) &&
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
    return false;
  if (
    !optional(m.failure, (f) => object(f) && optional(f.code, (v) => text(v, 320))) ||
    !repair(m.repair, m)
  )
    return false;
  return true;
}
export function fleetRunReceipt(
  input: unknown,
  model: FleetRunModel,
  action: "continue" | "repair",
): FleetRunReceipt | null {
  try {
    const value = snapshot(input);
    return validFleetRunReceipt(value, model, action) ? value : null;
  } catch {
    return null;
  }
}
function validFleetRunReceipt(
  r: unknown,
  model: FleetRunModel,
  action: "continue" | "repair",
): r is FleetRunReceipt {
  const e = action === "continue" ? model.evidence : model.repair.evidence;
  if (
    !object(r) ||
    r.contract_version !== 1 ||
    r.organization_id !== model.context.organization_id ||
    r.mission_id !== model.context.mission_id ||
    !id(r.fleetPlanningRunId) ||
    !sameFleetEvidence(r.evidence, e)
  )
    return false;
  if (
    action === "continue"
      ? r.outcome !== "continued" ||
        r.fleetPlanningRunId !== model.id ||
        r.phase !== "finished" ||
        !oneOf(["completed", "partial", "failed", "canceled"], r.lifecycleState)
      : r.outcome !== "repair_created" ||
        r.fleetPlanningRunId === model.id ||
        r.phase !== "queued" ||
        r.lifecycleState !== "queued"
  )
    return false;
  return true;
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
