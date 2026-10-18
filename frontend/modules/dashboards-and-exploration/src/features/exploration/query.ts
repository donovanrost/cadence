import type { ExplorationModel, ExplorationQuery } from "./contracts";
export const queryKeys = [
  "point_id",
  "spacecraft_id",
  "scope_kind",
  "scope_id",
  "time_mode",
  "time_axis",
  "from",
  "to",
  "replay_run_id",
  "order",
  "limit",
  "selection_view",
  "validity_state",
  "realm",
  "logical_source",
  "data_source_id",
  "source_binding_id",
  "source_dashboard_id",
  "sample_id",
  "selected_time",
  "selected_data_source_id",
  "selected_source_binding_id",
  "question",
  "limit_mode",
] as const;
export const options: Record<string, readonly string[]> = {
  time_mode: [
    "latest",
    "live",
    "last_15m",
    "last_1h",
    "last_6h",
    "last_24h",
    "range",
    "archive",
    "replay_run",
  ],
  time_axis: ["receipt_time", "generation_time"],
  selection_view: ["canonical", "as_recorded", "all_revisions", "recomputed"],
  realm: ["flight", "rehearsal", "replay", "simulation"],
  scope_kind: [
    "",
    "mission",
    "spacecraft",
    "contact",
    "source_endpoint",
    "ground_station",
    "transport",
    "link",
  ],
  logical_source: ["telemetry", "operational_observables"],
  order: ["desc", "asc"],
  validity_state: ["", "canonical", "duplicate", "conflict", "superseded", "advisory"],
  limit_mode: ["observed", "current", "recomputed", "compare"],
  question: ["", "recent_anomalies", "what_changed", "missing_history", "link_degradation"],
};
export const defaults: ExplorationQuery = {
  time_mode: "latest",
  time_axis: "receipt_time",
  limit: "100",
  order: "desc",
  selection_view: "canonical",
  realm: "flight",
  logical_source: "telemetry",
  limit_mode: "observed",
};
export function validQueryText(value: unknown): value is string {
  if (typeof value !== "string" || new TextEncoder().encode(value).length > 256) return false;
  return Array.from(value).every((character) => {
    const code = character.charCodeAt(0);
    return code >= 32 && code !== 127;
  });
}
export function readQuery(value: unknown): ExplorationQuery {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid exploration query");
  const entries = Object.entries(value);
  for (const [key, text] of entries) {
    if (
      !queryKeys.includes(key as (typeof queryKeys)[number]) ||
      !validQueryText(text) ||
      text.length === 0 ||
      (options[key] && !options[key].includes(text))
    )
      throw Error("Invalid exploration query");
  }
  const query = value as ExplorationQuery;
  if (
    !!query.selected_data_source_id !== !!query.selected_source_binding_id ||
    (query.selected_data_source_id && !query.sample_id)
  )
    throw Error("Invalid inspection source selection");
  if (
    query.limit &&
    (!/^\d+$/.test(query.limit) || Number(query.limit) < 1 || Number(query.limit) > 1000)
  )
    throw Error("Invalid exploration limit");
  return query;
}
export function explorationHref(
  model: Pick<ExplorationModel, "mission_id" | "query">,
  query = model.query,
): string {
  readQuery(query);
  const search = new URLSearchParams();
  for (const key of queryKeys) if (query[key] !== undefined) search.set(key, query[key]);
  return `/missions/${encodeURIComponent(model.mission_id)}/ops/explore${search.size ? `?${search}` : ""}`;
}
