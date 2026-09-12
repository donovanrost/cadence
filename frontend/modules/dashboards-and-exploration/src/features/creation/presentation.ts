import type { CreationModel } from "./contracts";
import type { Page, DashboardForm } from "./presentation.contracts";
export const directoryHref = (mission: string) =>
  `/missions/${encodeURIComponent(mission)}/ops/dashboards`;
export const editorHref = (mission: string, id: string) =>
  `${directoryHref(mission)}/${encodeURIComponent(id)}/edit`;
export function presentation(model: CreationModel): { page: Page; form: DashboardForm } {
  const mode = model.mode,
    source = model.source;
  const heading =
    mode === "clone" ? "Clone Dashboard" : mode === "import" ? "Import Dashboard" : "New Dashboard";
  return {
    page: {
      id: "ops-dashboard-new",
      mode,
      eyebrow: "Author / Dashboards",
      heading,
      description: "Create a mission-shared dashboard definition. Personal stars remain yours.",
      source: source && {
        id: "dashboard-clone-source",
        dashboard_id: source.id,
        name: source.name,
        widget_count: source.widget_count,
        latest_version: source.version,
      },
      import_guidance:
        mode === "import"
          ? "Paste a Cadence dashboard document or export bundle. The new dashboard receives this mission's identity."
          : null,
      cancel: {
        id: "dashboard-new-cancel",
        label: "Cancel",
        href: directoryHref(model.mission_id),
      },
    },
    form: {
      id: "dashboard-new-form",
      name: {
        id: "dashboard-name",
        name: "dashboard[name]",
        type: "text",
        label: "Name",
        value: source ? `Copy of ${source.name}` : "",
        required: true,
      },
      description: {
        id: "dashboard-description",
        name: "dashboard[description]",
        type: "text",
        label: "Description",
        value: source?.description ?? "",
        required: false,
      },
      document_json:
        mode === "import"
          ? {
              id: "dashboard-document-json",
              name: "dashboard[document_json]",
              type: "textarea",
              label: "Dashboard JSON",
              value: "",
              required: true,
            }
          : null,
      submit: { id: "dashboard-new-submit", label: heading },
    },
  };
}
