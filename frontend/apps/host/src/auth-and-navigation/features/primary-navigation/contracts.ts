import { record, present, text } from "../../shared/contracts";
export function readNavigationContext(value: unknown, mission: boolean) {
  if (
    !record(value) ||
    value.version !== 1 ||
    !Array.isArray(value.capabilities) ||
    !value.capabilities.every((capability) => present(capability, 128)) ||
    !(value.nav_context === null || text(value.nav_context)) ||
    !(value.nav_item === null || text(value.nav_item))
  )
    return null;
  const organization = value.organization;
  const currentMission = value.mission;
  if (
    !(
      organization === null ||
      (record(organization) &&
        present(organization.organization_id, 512) &&
        present(organization.display_name))
    )
  )
    return null;
  if (
    !(
      currentMission === null ||
      (record(currentMission) &&
        present(currentMission.mission_id, 512) &&
        present(currentMission.display_name) &&
        present(currentMission.slug))
    )
  )
    return null;
  if (mission && !currentMission) return null;
  return {
    capabilities: value.capabilities as string[],
    nav_context: value.nav_context,
    nav_item: value.nav_item,
    organization: organization as { organization_id: string; display_name: string } | null,
    mission: currentMission as { mission_id: string; display_name: string; slug: string } | null,
  };
}
