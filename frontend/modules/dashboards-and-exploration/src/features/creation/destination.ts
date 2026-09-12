import { destination, identity, pathIdentity } from "../../shared/legacy-destination";

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function creationDestination(model: unknown, organization: unknown, mission: unknown) {
  if (
    !identity(organization) ||
    !pathIdentity(mission) ||
    !record(model) ||
    model.version !== 1 ||
    !record(model.context) ||
    model.context.organization_id !== organization ||
    model.context.mission_id !== mission
  )
    return null;

  const mode = model.mode;
  if (mode !== "new" && mode !== "clone" && mode !== "import") return null;
  const source = model.source_dashboard_id;
  if (mode === "clone" ? !identity(source) : source !== null) return null;

  const query: Record<string, string> = mode === "new" ? {} : { mode };
  if (mode === "clone") query.source_dashboard_id = source as string;
  return {
    href: destination(mission, "new", query),
    title:
      mode === "clone"
        ? "Clone Dashboard"
        : mode === "import"
          ? "Import Dashboard"
          : "New Dashboard",
  };
}
