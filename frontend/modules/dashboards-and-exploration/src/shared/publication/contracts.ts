import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
export type PublicationRequirement = {
  state: "publication_required";
  version: 1;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  author: boolean;
};
export function readPublicationRequirement(
  value: unknown,
  context: OpsPageContext,
): PublicationRequirement | null {
  if (
    !value ||
    typeof value !== "object" ||
    !("state" in value) ||
    value.state !== "publication_required"
  )
    return null;
  const data = value as Record<string, unknown>;
  const keys = ["state", "version", "organization_id", "mission_id", "dashboard_id", "author"];
  if (
    Object.keys(data).length !== keys.length ||
    keys.some((key) => !(key in data)) ||
    data.version !== 1 ||
    typeof data.author !== "boolean" ||
    data.organization_id !== context.organizationId ||
    data.mission_id !== context.missionId ||
    data.dashboard_id !== context.resourceId ||
    [data.organization_id, data.mission_id, data.dashboard_id].some(
      (id) =>
        typeof id !== "string" ||
        !id ||
        id.length > 256 ||
        id === "." ||
        id === ".." ||
        Array.from(id).some((character) => character.charCodeAt(0) < 32),
    )
  )
    throw Error("Invalid dashboard publication requirement");
  return data as PublicationRequirement;
}
