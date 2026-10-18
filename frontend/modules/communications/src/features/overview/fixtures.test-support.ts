import type { CommsOverviewResponse } from "./contracts";

const fixture: CommsOverviewResponse = {
  queryVersion: 1,
  presentation: {
    root: { attrs: { class: "space-y-6", id: "comms-overview-page" } },
    header: {
      attrs: { class: "border-b border-primary/20 pb-4" },
      body: { attrs: {} },
      content: { attrs: {} },
      eyebrow: { attrs: { class: "hud-label" }, text: "Communications" },
      title: { attrs: { class: "mission-title" }, text: "Firebird" },
      title_suffix: { attrs: { class: "mission-title-suffix" }, text: "· Mission Comms" },
    },
    overview: {
      transport: {
        id: "comms-transports",
        eyebrow: "Transport",
        count: 0,
        count_label: "transports configured",
        description: "Mission transport readiness.",
        status: { tone: "attention", label: "Needs Work" },
        empty: true,
        empty_state: {
          title: "No transports configured",
          description: "Add a transport.",
          action_label: "Add a transport",
          action_href: "/missions/mission-1/comms/transports/new",
        },
        rows: [],
        manage_label: "Manage transports →",
        manage_href: "/missions/mission-1/comms/transports",
        add_label: "+ Add a transport",
        add_href: "/missions/mission-1/comms/transports/new",
      },
      validation: {
        id: "comms-validation-page",
        eyebrow: "Setup Checks",
        title: "What's missing or broken",
        description: "Checks on saved configuration.",
        status: { tone: "ready", label: "No Findings" },
        empty: true,
        empty_state: { title: "All clear", description: "The saved configuration is consistent." },
        findings_id: "comms-validation-findings",
        finding_groups: [],
      },
    },
  },
};

export function overviewResponse(): CommsOverviewResponse {
  return structuredClone(fixture);
}
