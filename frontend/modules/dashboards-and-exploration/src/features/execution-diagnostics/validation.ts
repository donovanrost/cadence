import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { collectionIds, type ExecutionDiagnostics } from "./contracts";

const invalid = (): never => {
  throw Error("Invalid dashboard execution diagnostics");
};
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
function exact(v: unknown, keys: string[]): Record<string, unknown> {
  if (!record(v) || Object.keys(v).length !== keys.length || keys.some((k) => !Object.hasOwn(v, k)))
    return invalid();
  return v;
}
function text(v: unknown, limit = 256): string {
  if (
    typeof v !== "string" ||
    !v ||
    /[\u0000-\u001f\u007f]/.test(v) ||
    new TextEncoder().encode(v).length > limit
  )
    return invalid();
  return v;
}
const detailKeys: Record<string, string[]> = {
  plan_warning: [
    "warning_code",
    "scope",
    "placement_id",
    "frame_id",
    "field_name",
    "source_request_id",
    "logical_source",
  ],
  plan: [
    "resolve_mode",
    "requests",
    "executed_requests",
    "skipped_requests",
    "returned_frames",
    "warnings",
    "live_append_eligible",
    "snapshot",
  ],
  requests: [
    "logical_source",
    "observable_count",
    "observables",
    "consumer_count",
    "placements",
    "time_mode",
    "time_axis",
    "from",
    "to",
    "realm",
    "data_view",
    "limit_mode",
  ],
  frames: ["placement_id", "frame_id", "role", "source", "shape", "time_axis", "field_count"],
  cache: ["layer", "placement_id", "request_id", "fingerprint", "source_result_status"],
  source_execution: [
    "logical_source",
    "executed",
    "degraded",
    "severity",
    "actionable",
    "retryable",
    "cache_status",
    "operator_action",
    "runtime_action",
    "warning_codes",
  ],
  refresh: [
    "observed_at",
    "refresh_allowed",
    "decision_status",
    "context_reason",
    "affected_placement_count",
  ],
  invalidation: [
    "observed_at",
    "invalidation_event_id",
    "boundary",
    "domain_fact",
    "matches",
    "context_matches",
    "context_reason",
    "invalidated_artifacts",
    "affected_placement_count",
    "affected_placements",
  ],
};
const counts = new Set([
  "requests",
  "executed_requests",
  "skipped_requests",
  "returned_frames",
  "warnings",
  "observable_count",
  "consumer_count",
  "field_count",
  "affected_placement_count",
  "invalidated_artifacts",
]);
const booleans = new Set([
  "live_append_eligible",
  "snapshot",
  "executed",
  "degraded",
  "actionable",
  "retryable",
  "refresh_allowed",
  "matches",
  "context_matches",
]);
function detailValue(key: string, value: unknown) {
  if (value === null) return;
  if (counts.has(key)) {
    if (!Number.isSafeInteger(value) || (value as number) < 0) invalid();
  } else if (booleans.has(key)) {
    if (typeof value !== "boolean") invalid();
  } else if (value !== "") text(value);
}
export function readExecutionDiagnostics(
  value: unknown,
  context: OpsPageContext,
): ExecutionDiagnostics {
  const model = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "dashboard_id",
    "name",
    "document_version",
    "loaded_at",
    "collections",
  ]);
  if (
    model.version !== 2 ||
    text(model.organization_id) !== context.organizationId ||
    text(model.mission_id) !== context.missionId ||
    text(model.dashboard_id) !== context.resourceId
  )
    invalid();
  text(model.name, 4096);
  if (!Number.isSafeInteger(model.document_version) || (model.document_version as number) < 1)
    invalid();
  const loaded = text(model.loaded_at, 64);
  if (
    !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(loaded) ||
    !Number.isFinite(Date.parse(loaded))
  )
    invalid();
  if (!Array.isArray(model.collections) || model.collections.length !== collectionIds.length)
    return invalid();
  const rowIds = new Set<string>();
  for (const [index, value] of model.collections.entries()) {
    const c = exact(value, ["id", "state", "source", "limited", "rows"]);
    if (
      c.id !== collectionIds[index] ||
      !["ready", "unavailable"].includes(c.state as string) ||
      typeof c.limited !== "boolean" ||
      !Array.isArray(c.rows) ||
      c.rows.length > 50
    )
      return invalid();
    if (c.state === "unavailable") {
      if (c.source !== null || c.rows.length || c.limited) invalid();
    } else if (
      index < 5
        ? c.source !== "inspection"
        : !["durable", "process_local"].includes(c.source as string)
    )
      invalid();
    for (const value of c.rows) {
      const row = exact(value, ["kind", "id", "identity", "title", "status", "details"]);
      if (row.kind !== c.id && !(c.id === "plan" && row.kind === "plan_warning")) invalid();
      const keys = detailKeys[row.kind as string];
      const id = text(row.id, 64);
      if (!/^[a-f0-9]{64}$/.test(id) || rowIds.has(id)) invalid();
      rowIds.add(id);
      text(row.identity);
      text(row.title);
      text(row.status);
      if (!Array.isArray(row.details) || row.details.length !== keys.length) return invalid();
      for (const [i, value] of row.details.entries()) {
        const d = exact(value, ["key", "value"]);
        if (d.key !== keys[i]) invalid();
        detailValue(keys[i], d.value);
      }
      if (row.kind === "plan_warning") {
        if (!["info", "warning", "error"].includes(row.status as string)) invalid();
        if (!["dashboard", "placement", "frame", "field"].includes(row.details[1].value)) invalid();
        for (const [index, detail] of row.details.entries()) {
          if (index < 2 || detail.value !== null) text(detail.value);
        }
      }
    }
  }
  return value as ExecutionDiagnostics;
}
