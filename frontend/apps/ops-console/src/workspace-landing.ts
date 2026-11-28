export type WorkspaceLandingModel = {
  version: 1;
  context: { organization_id: string; mission_id: string };
  mission_name: string;
  can_administer: boolean;
};

const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);
const identity = (value: unknown): value is string =>
  typeof value === "string" && value.length <= 512 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value);

export function readWorkspaceLanding(
  value: unknown,
  organizationId: unknown,
  missionId: unknown,
): WorkspaceLandingModel {
  if (
    !identity(organizationId) ||
    !identity(missionId) ||
    !record(value) ||
    value.version !== 1 ||
    !record(value.context) ||
    value.context.organization_id !== organizationId ||
    value.context.mission_id !== missionId ||
    typeof value.mission_name !== "string" ||
    value.mission_name.trim().length === 0 ||
    new TextEncoder().encode(value.mission_name).length > 8192 ||
    typeof value.can_administer !== "boolean"
  )
    throw Error("The mission operations navigation is unavailable.");
  return value as WorkspaceLandingModel;
}

export type WorkspaceDestination = { key: string; label: string; icon: string; href: string };
export type WorkspaceGroup = { key: string; label: string; items: WorkspaceDestination[] };

export function workspaceGroups(href: (path: string) => string): WorkspaceGroup[] {
  const item = (key: string, label: string, icon: string, path = key.replaceAll("_", "-")) => ({
    key,
    label,
    icon,
    href: href(path),
  });
  return [
    {
      key: "observe",
      label: "Observe",
      items: [item("dashboards", "Dashboards", "hero-squares-2x2")],
    },
    {
      key: "system",
      label: "System",
      items: [item("data_sources", "Data Sources", "hero-circle-stack")],
    },
  ];
}

export const navigateAttrs = (href: string) => ({
  href,
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
});
