import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { ExplorationModel, ExplorationRow } from "./contracts";
import { readQuery } from "./query";
import { readInspection } from "./sample-validation";
function exact(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid exploration object");
  const object = value as Record<string, unknown>;
  if (Object.keys(object).length !== keys.length || keys.some((key) => !Object.hasOwn(object, key)))
    throw Error("Invalid exploration fields");
  return object;
}
function text(value: unknown, max = 256): value is string {
  return (
    typeof value === "string" && value.length > 0 && new TextEncoder().encode(value).length <= max
  );
}
function optional(value: unknown, max = 256) {
  return value === null || text(value, max);
}
function time(value: unknown): boolean {
  return (
    text(value, 40) &&
    /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}
function row(value: unknown): ExplorationRow {
  const r = exact(value, [
    "key",
    "point_id",
    "sample_id",
    "time",
    "axis",
    "value",
    "value_kind",
    "unit",
    "source",
  ]);
  const s = exact(r.source, ["data_source_id", "source_binding_id", "dataset", "realm"]);
  if (
    !text(r.key, 64) ||
    !/^[a-f0-9]{64}$/.test(r.key) ||
    !text(r.point_id) ||
    !optional(r.sample_id) ||
    !(r.time === null || time(r.time)) ||
    !["generation_time", "receipt_time"].includes(String(r.axis)) ||
    !(
      r.unit === null ||
      (typeof r.unit === "string" && new TextEncoder().encode(r.unit).length <= 128)
    ) ||
    !["flight", "rehearsal", "replay", "simulation"].includes(String(s.realm)) ||
    ![s.data_source_id, s.source_binding_id, s.dataset].every((v) => optional(v))
  )
    throw Error("Invalid exploration row");
  const validValue =
    r.value === null ||
    (r.value_kind === "number" &&
      typeof r.value === "number" &&
      Number.isFinite(r.value) &&
      Math.abs(r.value) <= Number.MAX_SAFE_INTEGER) ||
    (r.value_kind === "boolean" && typeof r.value === "boolean") ||
    (["string", "enum"].includes(String(r.value_kind)) &&
      typeof r.value === "string" &&
      new TextEncoder().encode(r.value).length <= 4096);
  if (!validValue || !["number", "boolean", "string", "enum"].includes(String(r.value_kind)))
    throw Error("Invalid exploration value");
  return value as ExplorationRow;
}
export function readExploration(value: unknown, context: OpsPageContext): ExplorationModel {
  const m = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "query",
    "origin",
    "loaded_at",
    "status",
    "effective_time",
    "rows",
    "limited",
    "warnings",
    "warnings_limited",
    "inspection",
  ]);
  if (
    m.version !== 3 ||
    !text(m.organization_id) ||
    !text(m.mission_id) ||
    m.organization_id !== context.organizationId ||
    m.mission_id !== context.missionId ||
    context.resourceId !== undefined ||
    !time(m.loaded_at) ||
    ![
      "ready",
      "empty",
      "unavailable",
      "point_required",
      "unsupported_exploration_source",
      "unsupported_exploration_scope",
    ].includes(String(m.status)) ||
    typeof m.limited !== "boolean" ||
    typeof m.warnings_limited !== "boolean"
  )
    throw Error("Invalid exploration model");
  const query = readQuery(m.query);
  const origin = exact(m.origin, ["status", "dashboard"]);
  if (origin.status === "ready") {
    const dashboard = exact(origin.dashboard, ["id", "name"]);
    if (
      !text(dashboard.id) ||
      dashboard.id !== query.source_dashboard_id ||
      [".", ".."].includes(dashboard.id) ||
      [".", ".."].includes(m.mission_id as string) ||
      !text(dashboard.name, 512)
    )
      throw Error("Invalid exploration origin");
  } else if (
    origin.dashboard !== null ||
    origin.status !== (query.source_dashboard_id ? "unavailable" : "not_provided")
  )
    throw Error("Invalid exploration origin state");
  readInspection(m.inspection, query);
  if (!Array.isArray(m.rows) || m.rows.length > Number(query.limit ?? 100))
    throw Error("Invalid exploration rows");
  const rows = m.rows.map(row);
  if (
    new Set(rows.map((r) => r.key)).size !== rows.length ||
    rows.some((r) => r.point_id !== query.point_id) ||
    (m.status === "ready") !== rows.length > 0
  )
    throw Error("Invalid exploration result state");
  if (m.effective_time !== null) {
    const t = exact(m.effective_time, ["mode", "axis", "from", "to"]);
    if (
      !["live", "range", "replay_run"].includes(String(t.mode)) ||
      !["generation_time", "receipt_time"].includes(String(t.axis)) ||
      ![t.from, t.to].every((v) => v === null || time(v))
    )
      throw Error("Invalid effective exploration time");
  }
  if (!Array.isArray(m.warnings) || m.warnings.length > 50)
    throw Error("Invalid exploration warnings");
  for (const value of m.warnings) {
    const w = exact(value, ["code", "severity"]);
    if (
      !text(w.code, 128) ||
      !/^[a-z][a-z0-9_]*$/.test(w.code) ||
      !["info", "warning", "error"].includes(String(w.severity))
    )
      throw Error("Invalid exploration warning");
  }
  return value as ExplorationModel;
}
