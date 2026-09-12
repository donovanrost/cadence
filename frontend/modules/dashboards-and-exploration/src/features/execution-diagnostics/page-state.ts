import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { ExecutionDiagnostics } from "./contracts";
import { readExecutionDiagnostics } from "./validation";
import { readSelection, type DiagnosticSelection } from "./selection";
export type DiagnosticsPageState = {
  model: ExecutionDiagnostics;
  selection: DiagnosticSelection;
  runtime_query: Record<string, string>;
  publication_changed: boolean;
  sequence: number;
};
export function exact(value: unknown, keys: string[]): Record<string, unknown> {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(value, key))
  )
    throw Error("Invalid diagnostics page state");
  return value as Record<string, unknown>;
}
const enums: Record<string, string[]> = {
  time_mode: ["live", "range", "archive"],
  time_axis: ["generation_time", "receipt_time"],
  realm: ["flight", "rehearsal", "replay", "simulation"],
  selection_view: ["canonical", "as_recorded", "all_revisions", "recomputed"],
  limit_mode: ["observed", "current", "recomputed", "compare"],
};
function micros(value: string): bigint {
  const match =
    /^(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})(?:[.,](\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match || value.length > 40) throw Error("Invalid diagnostics time");
  const date = match[1].replace(" ", "T");
  const calendar = Date.parse(date + "Z"),
    instant = Date.parse(date + match[3]);
  if (
    !Number.isFinite(instant) ||
    !Number.isFinite(calendar) ||
    new Date(calendar).toISOString().slice(0, 19) !== date
  )
    throw Error("Invalid diagnostics time");
  return BigInt(instant) * 1000n + BigInt((match[2] ?? "").padEnd(6, "0"));
}
export function readRuntimeQuery(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid runtime query");
  const query = value as Record<string, unknown>;
  for (const [key, value] of Object.entries(query)) {
    if (
      typeof value !== "string" ||
      (!Object.hasOwn(enums, key) && !["from", "to"].includes(key)) ||
      (Object.hasOwn(enums, key) && !enums[key].includes(value))
    )
      throw Error("Invalid runtime query");
  }
  if (["range", "archive"].includes(query.time_mode as string)) {
    if (typeof query.from !== "string" || typeof query.to !== "string")
      throw Error("Missing time bounds");
    const duration = micros(query.to) - micros(query.from);
    if (duration <= 0n || duration > 31n * 86400000000n) throw Error("Invalid time range");
  } else if (Object.hasOwn(query, "from") || Object.hasOwn(query, "to"))
    throw Error("Unexpected time bounds");
  return value as Record<string, string>;
}
export function readDiagnosticsPage(value: unknown, context: OpsPageContext): DiagnosticsPageState {
  const state = exact(value, [
    "model",
    "selection",
    "runtime_query",
    "publication_changed",
    "sequence",
  ]);
  readExecutionDiagnostics(state.model, context);
  readSelection(state.selection);
  readRuntimeQuery(state.runtime_query);
  if (
    typeof state.publication_changed !== "boolean" ||
    !Number.isSafeInteger(state.sequence) ||
    (state.sequence as number) < 0 ||
    (state.sequence as number) > 1_000_000
  )
    throw Error("Invalid diagnostics sequence");
  return value as DiagnosticsPageState;
}
export function diagnosticsHref(
  state: DiagnosticsPageState,
  selection?: DiagnosticSelection,
): string {
  const model = state.model;
  const base = `/missions/${encodeURIComponent(model.mission_id)}/ops/dashboards/${encodeURIComponent(model.dashboard_id)}`;
  const query = new URLSearchParams(state.runtime_query);
  if (selection) {
    query.set("collection", selection.collection);
    if (selection.row !== null) query.set("row", selection.row);
    if (selection.filter) query.set("filter", selection.filter);
  }
  query.sort();
  return `${base}${selection ? "/diagnostics" : ""}${query.size ? `?${query}` : ""}`;
}
