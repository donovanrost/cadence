import type { OpsContactRequirementListProps } from "./OpsContactRequirementList.contracts";
import {
  requirementDirectoryHref,
  requirementSegment,
  type RequirementDirectory,
  type RequirementRow,
} from "./requirement-directory";
const label = (v: string) => v.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
const outcome = (r: RequirementRow) => {
  switch (r.success_measure) {
    case "any_contact":
      return "Any eligible contact";
    case "minimum_duration":
      return `At least ${r.minimum_duration_seconds} seconds`;
    case "minimum_data_volume":
      return `At least ${r.minimum_data_volume_bytes} bytes`;
    case "contact_count":
      return `${r.contact_count} contacts · at least ${r.minimum_separation_seconds} seconds apart`;
  }
};
export const requirementRowDomId = (id: string) =>
  "requirement-" +
  btoa(String.fromCharCode(...new TextEncoder().encode(id)))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
export function requirementDirectoryPresentation(
  d: RequirementDirectory,
): OpsContactRequirementListProps {
  const base = `/missions/${requirementSegment(d.context.mission_id)}/ops/requirements`;
  return {
    contract_version: 1,
    context: d.context,
    query: d.query,
    page: {
      id: "ops-contact-requirement-list-page",
      list_id: "contact-requirements",
      header: {
        eyebrow: "Mission operations",
        title: "Contact Requirements",
        description:
          "Declare the mission outcome first. Cadence searches every ready provider route, preserves their evidence, and lets operators commit an exact plan.",
        create_action: {
          id: "new-contact-requirement-link",
          label: "Declare need",
          href: base + "/new",
        },
      },
      journey_steps: [
        { number: "01", label: "Need", detail: "Mission outcome", active: true },
        { number: "02", label: "Options", detail: "Provider evidence", active: false },
        { number: "03", label: "Plan", detail: "Exact commitment", active: false },
        { number: "04", label: "Reserved", detail: "Provider capacity", active: false },
      ],
      empty_state: {
        id: "contact-requirements-empty",
        title: "No matching contact requirements",
        description: "Choose another lifecycle or page, or declare a new mission need.",
      },
    },
    filters: (["all", "active", "closed", "canceled"] as const).map((state) => ({
      id: "requirements-filter-" + state,
      label: label(state),
      href: requirementDirectoryHref(d, 1, state),
      active: d.query.state === state,
    })),
    pagination: {
      label: `Page ${d.query.page}`,
      previous_href: d.query.page > 1 ? requirementDirectoryHref(d, d.query.page - 1) : null,
      next_href: d.requirements.more ? requirementDirectoryHref(d, d.query.page + 1) : null,
    },
    requirements: d.requirements.entries.map((r) => {
      const tone =
        r.priority === "critical" ? "error" : r.priority === "high" ? "warning" : "neutral";
      return {
        id: r.id,
        __dom_id: requirementRowDomId(r.id),
        priority: { label: label(r.priority), tone, class: "text-" + tone },
        version_direction: `v${r.version} · ${r.direction}`,
        intent_label: label(r.intent),
        outcome_detail: outcome(r),
        window: {
          label: "Acceptable window (UTC)",
          detail: `${r.earliest_start} → ${r.latest_end}`,
        },
        lifecycle: {
          label: label(r.state),
          detail: "Requirement lifecycle, not reservation status",
        },
        detail_href: base + "/" + requirementSegment(r.id),
      };
    }),
  };
}
