import { fleetStates, type FleetDirectory } from "./OpsFleetPlanning.contracts";
const object = (v: any) => v !== null && typeof v === "object" && !Array.isArray(v);
const id = (v: any) =>
  typeof v === "string" &&
  v.length > 0 &&
  new TextEncoder().encode(v).length <= 240 &&
  !/\s/u.test(v) &&
  v.split("").every((char) => char.charCodeAt(0) > 31 && char.charCodeAt(0) !== 127);
const number = (v: any) => Number.isSafeInteger(v) && v > 0;
const time = (v: any) =>
  typeof v === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
export function admitFleetDirectory(
  value: unknown,
  context?: FleetDirectory["context"],
): FleetDirectory | null {
  try {
    if (!object(value)) return null;
    const raw = JSON.stringify(value);
    if (new TextEncoder().encode(raw).length > 60_000) return null;
    const v = JSON.parse(raw);
    if (
      v.contract_version !== 1 ||
      !object(v.context) ||
      !id(v.context.organization_id) ||
      !id(v.context.mission_id)
    )
      return null;
    if (
      context &&
      (v.context.organization_id !== context.organization_id ||
        v.context.mission_id !== context.mission_id)
    )
      return null;
    const q = v.query,
      p = v.active_policy,
      runs = v.runs;
    if (
      !object(q) ||
      !number(q.page) ||
      q.page > 1_000_000 ||
      (q.state !== null && !fleetStates.includes(q.state))
    )
      return null;
    if (
      p !== null &&
      (!object(p) ||
        !id(p.id) ||
        !number(p.version) ||
        typeof p.content_sha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(p.content_sha256) ||
        !number(p.max_horizon_seconds))
    )
      return null;
    if (
      !object(runs) ||
      runs.page !== q.page ||
      typeof runs.more !== "boolean" ||
      !Array.isArray(runs.entries) ||
      runs.entries.length > 25 ||
      (runs.more && runs.entries.length !== 25)
    )
      return null;
    const seen = new Set();
    for (const r of runs.entries) {
      if (
        !object(r) ||
        !id(r.id) ||
        seen.has(r.id) ||
        !fleetStates.includes(r.lifecycle_state) ||
        (q.state !== null && r.lifecycle_state !== q.state)
      )
        return null;
      seen.add(r.id);
      if (
        ![
          "queued",
          "materializing",
          "searching",
          "optimizing",
          "materializing_plan",
          "finished",
        ].includes(r.phase) ||
        !["manual", "scheduled", "repair"].includes(r.trigger_kind)
      )
        return null;
      if (
        !time(r.horizon_start) ||
        !time(r.horizon_end) ||
        Date.parse(r.horizon_start) >= Date.parse(r.horizon_end) ||
        !time(r.inserted_at)
      )
        return null;
      if (
        !id(r.policy_id) ||
        !number(r.policy_version) ||
        !number(r.requirement_count) ||
        r.requirement_count > 10_000
      )
        return null;
      if (
        r.candidate_plan !== null &&
        (!object(r.candidate_plan) || !id(r.candidate_plan.id) || !number(r.candidate_plan.version))
      )
        return null;
    }
    return v as FleetDirectory;
  } catch {
    return null;
  }
}
export function fleetBase(directory: FleetDirectory) {
  return `/missions/${encodeURIComponent(directory.context.mission_id)}/ops/planning`;
}
export function fleetPageHref(directory: FleetDirectory, page: number) {
  const q = new URLSearchParams({ page: String(page) });
  if (directory.query.state !== null) q.set("state", directory.query.state);
  return `${fleetBase(directory)}?${q}`;
}
