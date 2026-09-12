import type { DashboardRuntimeDiagnosticsProps } from "./contracts";

type Check = (value: unknown) => boolean;
const text: Check = (value) => typeof value === "string";
const boolean: Check = (value) => typeof value === "boolean";
const count: Check = (value) =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
const nullable =
  (check: Check): Check =>
  (value) =>
    value === null || check(value);
const list =
  (check: Check): Check =>
  (value) =>
    Array.isArray(value) && value.length <= 1000 && value.every(check);
const shape =
  (fields: Record<string, Check>): Check =>
  (value) =>
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.entries(fields).every(
      ([key, check]) => Object.hasOwn(value, key) && check((value as Record<string, unknown>)[key]),
    );
const state: Check = (value) =>
  ["none", "missing", "visible", "outside_results"].includes(value as string);
const filterKey: Check = (value) =>
  [
    "dashboard_id",
    "mission_id",
    "boundary",
    "context_reason",
    "replay_run_id",
    "affected_placement_id",
  ].includes(value as string);
const fact = shape({ key: text, label: text, value: text });
// This slot only navigates the existing relative diagnostics route. Avoid a
// dynamic URL constructor in release artifacts as well as origin ambiguity.
const link: Check = (value) =>
  typeof value === "string" && /^\/admin\/runtime(?:\?[^#\\\s]*)?(?:#[^\\\s]*)?$/.test(value);
const detail = shape({
  id: text,
  subtitle: text,
  close_action: shape({ id: text, href: link }),
  evidence: shape({
    id: text,
    decision_key: text,
    source: text,
    groups: list(shape({ key: text, label: text, facts: list(fact) })),
  }),
  sections: list(shape({ id: text, key: text, label: text, empty_copy: text, pairs: list(fact) })),
});
const valid = shape({
  summary: shape({
    decision_count: count,
    status_summary: text,
    refresh_summary: text,
    source_summary: text,
    selected_decision_state: state,
    empty_state: shape({ id: text, copy: text }),
    stats: list(shape({ id: text, label: text, value: count })),
  }),
  filters: shape({
    values: shape({
      dashboard_id: text,
      mission_id: text,
      boundary: text,
      context_reason: text,
      replay_run_id: text,
      affected_placement_id: text,
    }),
    fields: list(shape({ key: filterKey, id: text, name: text, label: text, placeholder: text })),
    clear_href: link,
  }),
  decisions: list(
    shape({
      __dom_id: text,
      id: text,
      key: text,
      dashboard: text,
      mission: text,
      source: text,
      boundary: text,
      status: text,
      context: text,
      replay_run: text,
      refresh: text,
      artifacts: text,
      affected_count: text,
      affected_placements: text,
      affected_impact: text,
      observed: text,
      inspect_action: shape({ id: text, href: link, selected: boolean }),
    }),
  ),
  selection: shape({
    state,
    decision_key: nullable(text),
    missing: boolean,
    outside_results: boolean,
    context_href: nullable(link),
    detail: nullable(detail),
  }),
  navigation: shape({ admin_href: (value) => value === "/admin" }),
});

export function assertRuntimeDiagnostics(
  value: unknown,
): asserts value is DashboardRuntimeDiagnosticsProps {
  if (!valid(value)) throw new Error("Invalid dashboard runtime diagnostics contract.");
}
