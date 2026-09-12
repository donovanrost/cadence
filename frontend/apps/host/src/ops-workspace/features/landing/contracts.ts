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
