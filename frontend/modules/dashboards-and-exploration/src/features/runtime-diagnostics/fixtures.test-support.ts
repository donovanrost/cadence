import type { DashboardRuntimeDiagnosticsProps, FilterKey } from "./contracts";

export function diagnosticsFixture(): DashboardRuntimeDiagnosticsProps {
  const values = {
    dashboard_id: "",
    mission_id: "",
    boundary: "",
    context_reason: "",
    replay_run_id: "",
    affected_placement_id: "",
  };
  return {
    summary: {
      decision_count: 0,
      status_summary: "-",
      refresh_summary: "-",
      source_summary: "-",
      selected_decision_state: "none",
      empty_state: { id: "admin-runtime-decisions-empty", copy: "No decisions recorded." },
      stats: [{ id: "runtime-decision-count", label: "Decisions", value: 0 }],
    },
    filters: {
      values,
      fields: Object.keys(values).map((key) => ({
        key: key as FilterKey,
        id: `runtime_decision_filters_${key}`,
        name: `runtime_decision_filters[${key}]`,
        label: key,
        placeholder: key,
      })),
      clear_href: "/admin/runtime",
    },
    decisions: [],
    selection: {
      state: "none",
      decision_key: null,
      missing: false,
      outside_results: false,
      context_href: null,
      detail: null,
    },
    navigation: { admin_href: "/admin" },
  };
}
