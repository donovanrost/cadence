import { record, present, text } from "../../shared/contracts";

type Organization = Readonly<{ organization_id: string; display_name: string }>;
type Mission = Readonly<{ mission_id: string; display_name: string; slug: string }>;
export type NavigationContext = Readonly<{
  csrf_token: string;
  capabilities: readonly string[];
  nav_context: string | null;
  nav_item: string | null;
  organization: Organization | null;
  mission: Mission | null;
}>;
const organization = (value: unknown): value is Organization =>
  record(value) && present(value.organization_id, 512) && present(value.display_name);
const currentMission = (value: unknown): value is Mission =>
  record(value) &&
  present(value.mission_id, 512) &&
  present(value.display_name) &&
  present(value.slug);

export function readNavigationContext(value: unknown, mission: boolean): NavigationContext | null {
  if (
    !record(value) ||
    value.version !== 1 ||
    !present(value.csrf_token) ||
    !Array.isArray(value.capabilities) ||
    !value.capabilities.every((capability: unknown): capability is string =>
      present(capability, 128),
    ) ||
    !(value.nav_context === null || text(value.nav_context)) ||
    !(value.nav_item === null || text(value.nav_item)) ||
    !(value.organization === null || organization(value.organization)) ||
    !(value.mission === null || currentMission(value.mission)) ||
    (mission && value.mission === null)
  )
    return null;
  return {
    csrf_token: value.csrf_token,
    capabilities: value.capabilities,
    nav_context: value.nav_context,
    nav_item: value.nav_item,
    organization: value.organization,
    mission: value.mission,
  };
}
