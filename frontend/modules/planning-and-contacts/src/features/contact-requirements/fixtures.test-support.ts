import type { OpsContactRequirementListProps } from "./OpsContactRequirementList.contracts";
export const requirementListFixture = (): OpsContactRequirementListProps => ({
  contract_version: 1,
  context: { organization_id: "org-1", mission_id: "mission-1" },
  query: { page: 1, state: "all" },
  filters: ["all", "active", "closed", "canceled"].map((state) => ({
    id: "requirements-filter-" + state,
    label: state,
    href: "/missions/mission-1/ops/requirements?page=1&state=" + state,
    active: state === "all",
  })),
  pagination: { label: "Page 1", previous_href: null, next_href: null },
  page: {
    id: "requirements-page",
    header: {
      eyebrow: "Plan",
      title: "Contact requirements",
      description: "Mission demand",
      create_action: {
        id: "new-requirement",
        label: "New requirement",
        href: "/missions/mission-1/ops/requirements/new",
      },
    },
    journey_steps: [],
    empty_state: {
      id: "requirements-empty",
      title: "No requirements",
      description: "Declare mission demand",
    },
    list_id: "requirements-list",
  },
  requirements: [
    {
      id: "requirement-1",
      __dom_id: "requirement-row-1",
      priority: { label: "High", tone: "warning", class: "text-warning" },
      version_direction: "Version 2",
      intent_label: "Downlink",
      outcome_detail: "Acquire telemetry",
      window: { label: "Window", detail: "2026-09-08" },
      lifecycle: { label: "Active", detail: "Requirement lifecycle, not reservation status" },
      detail_href: "/missions/mission-1/ops/requirements/requirement-1",
    },
  ],
});
